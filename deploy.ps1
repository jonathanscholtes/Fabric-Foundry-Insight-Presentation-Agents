# LONGHAUL MBR AI Agents - Main Deployment Orchestrator
# Phases:
#   0. Bootstrap Terraform remote state (skip with -SkipBootstrap after first run)
#   1. Terraform infrastructure
#   2. Container build and push
#   3. Fabric Lakehouse setup + seed
#   4. Foundry agent deployment
#   5. GitHub OIDC setup (optional, -SetupGitHub)

param (
    [Parameter(Mandatory = $true)]
    [string]$Subscription,

    [Parameter(Mandatory = $false)]
    [string]$Location = "eastus2",

    [Parameter(Mandatory = $false)]
    [ValidateSet("dev", "staging", "prod")]
    [string]$Environment = "dev",

    # Destroy all deployed resources (runs terraform destroy).
    [Parameter(Mandatory = $false)]
    [switch]$Destroy,

    # Storage account for Terraform remote state (must be globally unique).
    # Default: stotfmbr + first 8 hex chars of subscription ID.
    [Parameter(Mandatory = $false)]
    [string]$TfStateStorageAccount = "",

    [Parameter(Mandatory = $false)]
    [string]$TfStateResourceGroup = "rg-tfstate-mbr",

    # Skip Phase 0 once the TF backend exists.
    [Parameter(Mandatory = $false)]
    [switch]$SkipBootstrap,

    # Run New-GitHubOidc.ps1 to create/update the Entra app registration and
    # set the 3 GitHub Actions secrets automatically. Requires 'gh' CLI.
    [Parameter(Mandatory = $false)]
    [switch]$SetupGitHub,

    # Fabric SQL analytics endpoint hostname.
    # e.g. <workspace-id>-<lakehouse-id>.datawarehouse.fabric.microsoft.com
    [Parameter(Mandatory = $false)]
    [string]$FabricSqlServer = $env:FABRIC_SQL_SERVER,

    # Fabric workspace GUID (used for setup_lakehouse.py --workspace-id).
    [Parameter(Mandatory = $false)]
    [string]$FabricWorkspaceId = "",

    # Skip Fabric Lakehouse setup and seed (Phase 3).
    [Parameter(Mandatory = $false)]
    [switch]$SkipFabric,

    # Skip seed_data.py (tables still created; useful on re-runs when data already exists).
    [Parameter(Mandatory = $false)]
    [switch]$SkipSeed,

    # Skip Phase 2 container build and push (infra already has images).
    [Parameter(Mandatory = $false)]
    [switch]$SkipContainers
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scripts = "$PSScriptRoot\scripts"
Import-Module "$scripts\common\DeploymentFunctions.psm1" -Force

Write-Host @"

============================================================
  LONGHAUL MBR AI Agents - Deployment Orchestrator
============================================================

"@ -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Azure context
# ---------------------------------------------------------------------------
Initialize-AzureContext -Subscription $Subscription
$subId    = (az account show --query id        -o tsv).Trim()
$tenantId = (az account show --query tenantId  -o tsv).Trim()

# Expose ARM env vars so the azurerm backend resolves the tenant without prompting.
$env:ARM_TENANT_ID       = $tenantId
$env:ARM_SUBSCRIPTION_ID = $subId

if (-not $TfStateStorageAccount) {
    $suffix                = ($subId -replace '-', '').Substring(0, 8).ToLower()
    $TfStateStorageAccount = "stotfmbr$suffix"
}

Write-Host "  Subscription   : $subId"                -ForegroundColor Gray
Write-Host "  Tenant         : $tenantId"              -ForegroundColor Gray
Write-Host "  Location       : $Location"              -ForegroundColor Gray
Write-Host "  Environment    : $Environment"           -ForegroundColor Gray
Write-Host "  TF state SA    : $TfStateStorageAccount" -ForegroundColor Gray
if ($FabricSqlServer) {
    $fabricDisplay = $FabricSqlServer
} elseif ($FabricWorkspaceId) {
    $fabricDisplay = "(auto-discover from workspace $FabricWorkspaceId)"
} else {
    $fabricDisplay = "(not set - pass -FabricWorkspaceId or -FabricSqlServer)"
}
Write-Host "  Fabric SQL     : $fabricDisplay" -ForegroundColor Gray

# ---------------------------------------------------------------------------
# Destroy path
# ---------------------------------------------------------------------------
if ($Destroy) {
    Write-Host "`n=== DESTROY: Tearing down infrastructure ===" -ForegroundColor Red

    & "$scripts\Deploy-Infrastructure.ps1" `
        -Action                destroy `
        -Subscription          $Subscription `
        -Location              $Location `
        -Environment           $Environment `
        -TfStateStorageAccount $TfStateStorageAccount `
        -TfStateResourceGroup  $TfStateResourceGroup

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Destroy failed (exit $LASTEXITCODE)." -ForegroundColor Red
        exit 1
    }

    Write-Host @"

============================================================
  Infrastructure destroyed.
============================================================

"@ -ForegroundColor Green
    exit 0
}

# ---------------------------------------------------------------------------
# PHASE 0: Bootstrap Terraform remote state backend
# ---------------------------------------------------------------------------
if ($SkipBootstrap) {
    Write-Host "`n=== PHASE 0: Skipped ===" -ForegroundColor DarkGray
} else {
    Write-Host "`n=== PHASE 0: Terraform State Backend Bootstrap ===" -ForegroundColor Magenta
    Write-Host "  Resource group  : $TfStateResourceGroup"    -ForegroundColor Cyan
    Write-Host "  Storage account : $TfStateStorageAccount"   -ForegroundColor Cyan

    az group create --name $TfStateResourceGroup --location $Location --output none

    az storage account create `
        --name                  $TfStateStorageAccount `
        --resource-group        $TfStateResourceGroup `
        --sku                   Standard_LRS `
        --allow-blob-public-access false `
        --min-tls-version       TLS1_2 `
        --output                none

    $currentUserId = (az ad signed-in-user show --query id -o tsv 2>$null).Trim()
    $storageId     = (az storage account show `
        --name           $TfStateStorageAccount `
        --resource-group $TfStateResourceGroup `
        --query id -o tsv).Trim()

    try {
        az role assignment create `
            --assignee-object-id    $currentUserId `
            --assignee-principal-type User `
            --role                  "Storage Blob Data Contributor" `
            --scope                 $storageId `
            --output                none
    } catch {}

    # Poll until the role is effective (RBAC can take up to 5 minutes to propagate)
    Write-Host "  Waiting for role assignment to propagate..." -ForegroundColor Gray
    $maxWait = 300; $waited = 0; $interval = 10; $ready = $false
    while (-not $ready -and $waited -lt $maxWait) {
        try {
            $null = az storage container list `
                --account-name $TfStateStorageAccount `
                --auth-mode login --output none --only-show-errors 2>$null
            if ($LASTEXITCODE -eq 0) { $ready = $true }
        } catch {}
        if (-not $ready) {
            Write-Host "  Still propagating... ($waited s elapsed)" -ForegroundColor Gray
            Start-Sleep -Seconds $interval
            $waited += $interval
        }
    }
    if (-not $ready) {
        Write-Host "  WARNING: Role may not have propagated after ${maxWait}s - continuing anyway." -ForegroundColor Yellow
    } else {
        Write-Host "  Role assignment effective after ${waited}s." -ForegroundColor Green
    }

    az storage container create `
        --name         tfstate `
        --account-name $TfStateStorageAccount `
        --auth-mode    login `
        --output       none

    Write-Host "[OK] State backend ready." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# PHASE 1: Deploy Infrastructure (Terraform)
# ---------------------------------------------------------------------------
Write-Host "`n=== PHASE 1: Infrastructure Deployment ===" -ForegroundColor Magenta

& "$scripts\Deploy-Infrastructure.ps1" `
    -Action                apply `
    -Subscription          $Subscription `
    -Location              $Location `
    -Environment           $Environment `
    -TfStateStorageAccount $TfStateStorageAccount `
    -TfStateResourceGroup  $TfStateResourceGroup `
    -FabricWorkspaceId     $FabricWorkspaceId `
    -FabricSqlServer       $FabricSqlServer

if ($LASTEXITCODE -ne 0) {
    Write-Host "Infrastructure deployment failed." -ForegroundColor Red
    exit 1
}

Write-Host "[OK] Infrastructure deployed." -ForegroundColor Green

# Read Terraform outputs for use in subsequent phases
Write-Host "`nReading Terraform outputs..." -ForegroundColor Cyan
$infraDir = Join-Path $PSScriptRoot "infra"
Push-Location $infraDir
try {
    $tfOutputs = terraform output -json 2>$null | ConvertFrom-Json
} catch {
    Write-Host "  WARNING: Could not read Terraform outputs - summary will be incomplete." -ForegroundColor Yellow
    $tfOutputs = $null
}
Pop-Location

$script:AcrLoginSrv        = if ($tfOutputs) { $tfOutputs.container_registry_login_server.value } else { $null }
$script:RgName             = if ($tfOutputs) { $tfOutputs.resource_group_name.value }              else { $null }
$script:FoundryEp          = if ($tfOutputs) { $tfOutputs.foundry_project_endpoint.value }         else { $null }
$script:McpFqdn            = if ($tfOutputs) { $tfOutputs.mcp_tools_api_fqdn.value }               else { $null }
$script:MbrApiUrl          = if ($tfOutputs) { $tfOutputs.mbr_api_url.value }                      else { $null }
$script:UiUrl              = if ($tfOutputs) { $tfOutputs.longhaul_ui_url.value }                  else { $null }
$script:AiAccountId        = if ($tfOutputs) { $tfOutputs.ai_account_id.value }                    else { $null }
$script:KvName             = if ($tfOutputs) { $tfOutputs.key_vault_name.value }                   else { $null }
$script:KvUri              = if ($tfOutputs) { $tfOutputs.key_vault_uri.value }                    else { $null }
$script:StorageAcct        = if ($tfOutputs) { $tfOutputs.storage_account_name.value }             else { $null }
$script:ModelDeployment    = if ($tfOutputs) { $tfOutputs.model_deployment.value }                 else { $null }
$script:MiniModelDeployment = if ($tfOutputs) { $tfOutputs.mini_model_deployment.value }           else { $null }
$script:LakehouseId         = ""
$script:DataAgentUrl        = ""

if ($script:MbrApiUrl)   { Write-Host "  mbr-api URL     : $($script:MbrApiUrl)"   -ForegroundColor Gray }
if ($script:UiUrl)       { Write-Host "  UI URL          : $($script:UiUrl)"       -ForegroundColor Gray }
if ($script:FoundryEp)   { Write-Host "  Foundry project : $($script:FoundryEp)"   -ForegroundColor Gray }
if ($script:AcrLoginSrv) { Write-Host "  ACR             : $($script:AcrLoginSrv)" -ForegroundColor Gray }

# Grant deploying principal the Foundry agent roles
# eadc314b = Azure AI Project Manager (agents/write)
# 53ca6127 = Azure AI User             (agents/read + invoke)
if ($script:AiAccountId) {
    Write-Host "`nGranting Foundry agent roles to deploying principal..." -ForegroundColor Cyan

    $accountInfo   = az account show --output json 2>$null | ConvertFrom-Json
    $principalType = "User"
    $principalId   = $null

    if ($accountInfo -and $accountInfo.user.type -eq "servicePrincipal") {
        $principalType = "ServicePrincipal"
        $principalId   = az ad sp show --id $accountInfo.user.name --query id --output tsv 2>$null
    } else {
        $principalId = az ad signed-in-user show --query id --output tsv 2>$null
    }

    if ($principalId) {
        foreach ($roleId in @(
            "eadc314b-1a2d-4efa-be10-5d325db5065e",
            "53ca6127-db72-4b80-b1b0-d745d6d5456d"
        )) {
            az role assignment create `
                --role                    $roleId `
                --assignee-object-id      $principalId `
                --assignee-principal-type $principalType `
                --scope                   $script:AiAccountId `
                --output                  none 2>$null
        }
        Write-Host "  Roles granted to $($accountInfo.user.name) - RBAC may take a few minutes to propagate." -ForegroundColor Gray
    } else {
        Write-Host "  WARNING: Could not resolve deploying principal ID - skipping Foundry role grant." -ForegroundColor Yellow
        Write-Host "           Manually assign 'Azure AI Project Manager' on the AI account if Phase 4 fails." -ForegroundColor Gray
    }
}

# ---------------------------------------------------------------------------
# PHASE 2: Build and push container images
# ---------------------------------------------------------------------------
if ($SkipContainers) {
    Write-Host "`n=== PHASE 2: Container Build and Push - Skipped (-SkipContainers) ===" -ForegroundColor DarkGray
} else {
    Write-Host "`n=== PHASE 2: Container Build and Push ===" -ForegroundColor Magenta

    & "$scripts\Deploy-Containers.ps1" `
        -Registry      $script:AcrLoginSrv `
        -ResourceGroup $script:RgName

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Container build/push failed." -ForegroundColor Red
        exit 1
    }

    Write-Host "[OK] Container images built and pushed." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# PHASE 3: Fabric Lakehouse setup
# ---------------------------------------------------------------------------
Write-Host "`n=== PHASE 3: Fabric Lakehouse Setup ===" -ForegroundColor Magenta

if ($SkipFabric) {
    Write-Host "=== PHASE 3: Skipped (-SkipFabric) ===" -ForegroundColor DarkGray
} else {
    # Auto-create the Lakehouse and discover its SQL endpoint when
    # -FabricWorkspaceId is supplied but -FabricSqlServer is not.
    if (-not $FabricSqlServer -and $FabricWorkspaceId) {
        Write-Host "  FabricWorkspaceId supplied  -  creating Lakehouse and discovering SQL endpoint..." -ForegroundColor Cyan
        $fabricResult = & "$scripts\Deploy-FabricWorkspace.ps1" `
            -WorkspaceId  $FabricWorkspaceId `
            -UpdateTfvars

        if ($LASTEXITCODE -ne 0 -or -not $fabricResult) {
            Write-Warn "Deploy-FabricWorkspace.ps1 failed  -  skipping Lakehouse table setup."
            $FabricSqlServer = ""
        } else {
            $FabricSqlServer      = $fabricResult.SqlServer
            $script:LakehouseId   = $fabricResult.LakehouseId
            Write-Host "[OK] Lakehouse created. SQL server: $FabricSqlServer" -ForegroundColor Green
        }
    }

    if (-not $FabricSqlServer) {
        Write-Warn "FabricSqlServer not resolved  -  skipping table creation and seed. Options:"
        Write-Host "  a) Pass -FabricWorkspaceId <guid> to auto-create the Lakehouse."             -ForegroundColor Gray
        Write-Host "  b) Pass -FabricSqlServer <endpoint> after creating it manually."             -ForegroundColor Gray
        Write-Host "  c) Set the FABRIC_SQL_SERVER environment variable before running."           -ForegroundColor Gray
        Write-Host "  See docs/fabric-setup.md for step-by-step instructions."                    -ForegroundColor Gray
    } else {
        & "$scripts\Deploy-FabricLakehouse.ps1" `
            -SqlServer          $FabricSqlServer `
            -WorkspaceId        $FabricWorkspaceId `
            -LakehouseId        $script:LakehouseId `
            -StorageAccountName $script:StorageAcct `
            -SkipSeed:$SkipSeed

        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Fabric Lakehouse setup failed (exit $LASTEXITCODE) - continuing."
        } else {
            Write-Host "[OK] Fabric Lakehouse configured." -ForegroundColor Green
        }
    }
}

# ---------------------------------------------------------------------------
# PHASE 3b: Fabric Data Agent
# ---------------------------------------------------------------------------
Write-Host "`n=== PHASE 3b: Fabric Data Agent ===" -ForegroundColor Magenta

if ($SkipFabric) {
    Write-Host "=== PHASE 3b: Skipped (-SkipFabric) ===" -ForegroundColor DarkGray
} elseif (-not $FabricWorkspaceId -or -not $script:LakehouseId) {
    Write-Host "  FabricWorkspaceId or LakehouseId not available - skipping Data Agent creation." -ForegroundColor Yellow
} else {
    try {
        $daResult = & "$scripts\Deploy-FabricDataAgent.ps1" `
            -WorkspaceId $FabricWorkspaceId `
            -LakehouseId $script:LakehouseId `
            -KeyVaultUri ($script:KvUri -as [string])

        $script:DataAgentUrl = if ($daResult -and $daResult.DataAgentUrl) { $daResult.DataAgentUrl } else { "" }
        Write-Host "[OK] Fabric Data Agent configured." -ForegroundColor Green
    } catch {
        Write-Host "WARNING: Deploy-FabricDataAgent.ps1 failed - continuing. Error: $_" -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------------------
# PHASE 4: Deploy Foundry agents
# ---------------------------------------------------------------------------
Write-Host "`n=== PHASE 4: Deploy Foundry Agents ===" -ForegroundColor Magenta

if (-not $script:FoundryEp) {
    Write-Warn "foundry_project_endpoint not found in Terraform outputs - skipping agent deployment."
} else {
    $mcpUrl = if ($script:McpFqdn) { "https://$($script:McpFqdn)" } else { $null }

    $foundryArgs = @("-ProjectEndpoint", $script:FoundryEp)
    if ($mcpUrl)                     { $foundryArgs += @("-McpServerUrl",         $mcpUrl) }
    if ($script:ModelDeployment)     { $foundryArgs += @("-ModelDeployment",      $script:ModelDeployment) }
    if ($script:MiniModelDeployment) { $foundryArgs += @("-MiniModelDeployment",  $script:MiniModelDeployment) }
    if ($script:KvUri)               { $foundryArgs += @("-KeyVaultUri",          $script:KvUri) }
    if ($script:DataAgentUrl)        { $foundryArgs += @("-FabricDataAgentUrl",   $script:DataAgentUrl) }

    if (-not $mcpUrl) {
        Write-Host "  WARNING: mcp_tools_api_fqdn not in TF outputs - presentation agent deployed without MCP tools." -ForegroundColor Yellow
        Write-Host "           Key Vault / Foundry connection fallback will be tried by deploy.py." -ForegroundColor Gray
    }

    & "$scripts\Deploy-FoundryAgents.ps1" @foundryArgs

    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Deploy-FoundryAgents.ps1 failed (exit $LASTEXITCODE) - continuing."
    } else {
        Write-Host "[OK] Foundry agents deployed." -ForegroundColor Green
    }
}

# ---------------------------------------------------------------------------
# PHASE 5: GitHub Actions OIDC setup (optional, -SetupGitHub)
# ---------------------------------------------------------------------------
$githubOidcConfigured = $false

if ($SetupGitHub) {
    Write-Host "`n=== PHASE 5: GitHub Actions OIDC Setup ===" -ForegroundColor Magenta

    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-Warn "'gh' CLI not found - skipping GitHub secret setup."
        Write-Host "         Install from https://cli.github.com then re-run with -SetupGitHub" -ForegroundColor Gray
    } else {
        & "$scripts\New-GitHubOidc.ps1" -Subscription $Subscription -Environment $Environment

        if ($LASTEXITCODE -eq 0) {
            $githubOidcConfigured = $true
            Write-Host "[OK] GitHub OIDC configured - secrets written to repo." -ForegroundColor Green
        } else {
            Write-Warn "GitHub OIDC setup failed (exit $LASTEXITCODE) - continuing."
        }
    }
} else {
    Write-Host "`n=== PHASE 5: Skipped ===" -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# Deployment Summary
# ---------------------------------------------------------------------------
Write-Host @"

============================================================
                 Deployment Summary
============================================================

"@ -ForegroundColor Cyan

Write-Host "[OK] Azure Infrastructure deployed (AI Foundry, Container Apps, ACR, Key Vault, Storage)" -ForegroundColor Green
Write-Host "[OK] Container images built and pushed to ACR"                                              -ForegroundColor Green
if (-not $SkipFabric -and $FabricSqlServer) {
    Write-Host "[OK] Fabric Lakehouse tables created$(if (-not $SkipSeed) { ' and seeded' })" -ForegroundColor Green
}
Write-Host "[OK] Foundry agents deployed (conversational + mbr-presentation)"                          -ForegroundColor Green

Write-Host "`n=== Next Steps ===" -ForegroundColor Cyan
if (-not $FabricSqlServer -and -not $FabricWorkspaceId) {
    Write-Host "  Fabric not configured. To automate Lakehouse creation:" -ForegroundColor Yellow
    Write-Host "    .\deploy.ps1 -Subscription ... -FabricWorkspaceId <guid>" -ForegroundColor White
    Write-Host "  OR pass -FabricSqlServer <endpoint> after creating the Lakehouse manually." -ForegroundColor Yellow
}
Write-Host "  Fabric portal still required for (cannot be scripted):" -ForegroundColor Cyan
Write-Host "    1. Create Semantic Model 'sm-mbr-trucking' over the 5 Lakehouse tables" -ForegroundColor Gray
Write-Host "    2. Define DAX measures + mark dim_month as Date Table (period_date column)" -ForegroundColor Gray
Write-Host "    3. Create Data Agent 'da-mbr-trucking' connected to sm-mbr-trucking" -ForegroundColor Gray
Write-Host "    4. Connect da-mbr-trucking to AI Foundry (connection name: da-mbr-trucking)" -ForegroundColor Gray
Write-Host "  See docs/fabric-setup.md for step-by-step instructions." -ForegroundColor Gray
$saHint = if ($script:StorageAcct) { $script:StorageAcct } else { '<storage-account>' }
Write-Host "  * Upload MBR template: az storage blob upload --account-name $saHint --container-name templates ..." -ForegroundColor Gray
Write-Host "  * Verify agents in Foundry portal -> Agents" -ForegroundColor Gray
Write-Host "  * Check Container App revisions are healthy in the portal" -ForegroundColor Gray

Write-Host "`n=== GitHub Actions Secrets ===" -ForegroundColor Cyan
if ($githubOidcConfigured) {
    Write-Host "  [OK] OIDC configured - AZURE_CLIENT_ID / AZURE_TENANT_ID / AZURE_SUBSCRIPTION_ID written to repo." -ForegroundColor Green
} else {
    Write-Host "  Not configured. Re-run with -SetupGitHub to do this automatically, or run manually:" -ForegroundColor Yellow
    Write-Host "    .\scripts\New-GitHubOidc.ps1 -Subscription $Subscription -Environment $Environment" -ForegroundColor White
    Write-Host "  Requires: az login + gh auth login" -ForegroundColor Gray
}

Write-Host "`n=== Service Endpoints ===" -ForegroundColor Cyan
if ($script:UiUrl)     { Write-Host "  LONGHAUL UI  : $($script:UiUrl)"     -ForegroundColor Green }
if ($script:MbrApiUrl) { Write-Host "  mbr-api      : $($script:MbrApiUrl)" -ForegroundColor Green }
if ($script:FoundryEp) { Write-Host "  Foundry      : $($script:FoundryEp)" -ForegroundColor Green }
if (-not $script:UiUrl -and -not $script:MbrApiUrl) {
    Write-Host "  Endpoints not yet available - run: terraform -chdir=infra output" -ForegroundColor Yellow
}

Write-Host @"

============================================================
  LONGHAUL MBR AI Agents Deployment Complete!
============================================================

"@ -ForegroundColor Green
