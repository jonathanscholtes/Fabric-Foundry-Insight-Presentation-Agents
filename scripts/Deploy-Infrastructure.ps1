# Apply or destroy Terraform infrastructure for LONGHAUL MBR AI Agents.

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("plan", "apply", "destroy")]
    [string]$Action = "apply",

    [Parameter(Mandatory=$false)]
    [string]$Subscription = $env:ARM_SUBSCRIPTION_ID,

    [Parameter(Mandatory=$false)]
    [string]$Location = "eastus2",

    [Parameter(Mandatory=$false)]
    [string]$Environment = "dev",

    [Parameter(Mandatory=$false)]
    [string]$TfStateStorageAccount = "",

    [Parameter(Mandatory=$false)]
    [string]$TfStateResourceGroup = "rg-tfstate-mbr",

    [Parameter(Mandatory=$false)]
    [string]$FabricWorkspaceId = "",

    [Parameter(Mandatory=$false)]
    [string]$FabricSqlServer = "",

    [Parameter(Mandatory=$false)]
    [string]$GitHubOrg = "",

    [Parameter(Mandatory=$false)]
    [string]$GitHubRepository = ""
)

Import-Module "$PSScriptRoot\common\DeploymentFunctions.psm1" -Force

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Initialize-AzureContext -Subscription $Subscription
$subscriptionId = az account show --query id        -o tsv
$tenantId       = az account show --query tenantId  -o tsv

# Expose ARM env vars so the azurerm backend resolves the tenant without prompting.
$env:ARM_TENANT_ID       = $tenantId
$env:ARM_SUBSCRIPTION_ID = $subscriptionId

if (-not $TfStateStorageAccount) {
    $suffix = ($subscriptionId -replace '-', '').Substring(0, 8).ToLower()
    $TfStateStorageAccount = "stotfmbr$suffix"
    Write-Info "TF state storage account: $TfStateStorageAccount"
}

$infraDir = Resolve-Path "$PSScriptRoot\..\infra"

# Generate terraform.tfvars from the template (reuses resource_token on re-runs).
New-TerraformVarsFile `
    -SubscriptionId    $subscriptionId `
    -TenantId          $tenantId `
    -Location          $Location `
    -Environment       $Environment `
    -ProjectName       "mbrtrucking" `
    -FabricWorkspaceId $FabricWorkspaceId `
    -FabricSqlServer   $FabricSqlServer `
    -GitHubOrg         $GitHubOrg `
    -GitHubRepository  $GitHubRepository `
    -InfraDir          $infraDir

Push-Location $infraDir
try {
    Write-Info "terraform init"
    # NOTE: PowerShell 5.1 mangles native-command args of the form `-flag=value`,
    # so all terraform calls below use the space-separated form `-flag value`.
    terraform init -upgrade `
        -backend-config "resource_group_name=$TfStateResourceGroup" `
        -backend-config "storage_account_name=$TfStateStorageAccount" `
        -backend-config "container_name=tfstate" `
        -backend-config "key=mbr-trucking.tfstate"
    if ($LASTEXITCODE -ne 0) { throw "terraform init failed (exit $LASTEXITCODE)" }

    switch ($Action) {
        "plan" {
            Write-Info "terraform plan"
            terraform plan -var-file terraform.tfvars
            if ($LASTEXITCODE -ne 0) { throw "terraform plan failed (exit $LASTEXITCODE)" }
        }
        "apply" {
            Write-Info "terraform plan"
            terraform plan -out tfplan -var-file terraform.tfvars
            if ($LASTEXITCODE -ne 0) { throw "terraform plan failed (exit $LASTEXITCODE)" }

            # Retry apply up to 3 times with backoff (handles transient platform errors)
            $maxAttempts = 3
            $attempt     = 0
            $applied     = $false
            while (-not $applied -and $attempt -lt $maxAttempts) {
                $attempt++
                Write-Info "terraform apply (attempt $attempt/$maxAttempts)"
                terraform apply tfplan
                if ($LASTEXITCODE -eq 0) {
                    $applied = $true
                } elseif ($attempt -lt $maxAttempts) {
                    $delay = $attempt * 120
                    Write-Warn "terraform apply failed (attempt $attempt) - retrying in ${delay}s..."
                    Start-Sleep -Seconds $delay
                    Write-Info "terraform plan (retry - no refresh)"
                    terraform plan -refresh=false -out tfplan -var-file terraform.tfvars
                    if ($LASTEXITCODE -ne 0) { throw "terraform plan failed on retry (exit $LASTEXITCODE)" }
                }
            }
            if (-not $applied) { throw "terraform apply failed after $maxAttempts attempts" }

            Write-Info "Capturing outputs"
            $outputs = terraform output -json | ConvertFrom-Json

            Write-Success "Infrastructure deployed"
            Write-Host "  mbr_api_url                  : $($outputs.mbr_api_url.value)"                   -ForegroundColor Gray
            Write-Host "  longhaul_ui_url              : $($outputs.longhaul_ui_url.value)"               -ForegroundColor Gray
            Write-Host "  mcp_tools_api_fqdn           : $($outputs.mcp_tools_api_fqdn.value)"            -ForegroundColor Gray
            Write-Host "  container_registry_server    : $($outputs.container_registry_login_server.value)" -ForegroundColor Gray
            Write-Host "  storage_account_name         : $($outputs.storage_account_name.value)"          -ForegroundColor Gray
            Write-Host "  app_identity_client_id       : $($outputs.app_identity_client_id.value)"        -ForegroundColor Gray
            Write-Host "  foundry_project_endpoint     : $($outputs.foundry_project_endpoint.value)"      -ForegroundColor Gray
            Write-Host "  key_vault_name               : $($outputs.key_vault_name.value)"                -ForegroundColor Gray
        }
        "destroy" {
            Write-Info "terraform plan -destroy"
            terraform plan -destroy -out tfplan -var-file terraform.tfvars
            if ($LASTEXITCODE -ne 0) { throw "terraform plan -destroy failed (exit $LASTEXITCODE)" }

            Write-Info "terraform apply (destroy)"
            terraform apply tfplan
            if ($LASTEXITCODE -ne 0) { throw "terraform destroy failed (exit $LASTEXITCODE)" }
        }
    }
} finally {
    Pop-Location
}
