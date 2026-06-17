# Build and push LONGHAUL container images to ACR, then update ACA revisions.

param(
    [Parameter(Mandatory=$false)]
    [string]$Registry = "",

    # Resource group name  -  passed from deploy.ps1 Phase 2 to avoid a redundant TF output read.
    # When omitted the script reads resource_group_name from Terraform outputs directly.
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroup = "",

    [Parameter(Mandatory=$false)]
    [string]$Environment = "dev"
)

Import-Module "$PSScriptRoot\common\DeploymentFunctions.psm1" -Force

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root     = Resolve-Path "$PSScriptRoot\.."
$infraDir = Join-Path $root "infra"

# ---------------------------------------------------------------------------
# Resolve ACR login server from Terraform outputs if not explicitly passed
# ---------------------------------------------------------------------------
if (-not $Registry) {
    Write-Info "Reading container_registry_login_server from Terraform outputs..."
    Push-Location $infraDir
    try {
        $Registry = terraform output -raw container_registry_login_server 2>$null
    } finally {
        Pop-Location
    }

    if (-not $Registry) {
        throw "Could not determine ACR login server. Pass -Registry or ensure Terraform outputs are available."
    }
}

Write-Info "ACR login server : $Registry"

# ---------------------------------------------------------------------------
# Retry helper for docker build/push (handles transient Docker Hub rate limits)
# ---------------------------------------------------------------------------
function Invoke-Docker {
    param([string[]]$DockerArgs, [int]$MaxAttempts = 3)
    for ($i = 1; $i -le $MaxAttempts; $i++) {
        docker @DockerArgs
        if ($LASTEXITCODE -eq 0) { return }
        if ($i -lt $MaxAttempts) {
            $delay = $i * 30
            Write-Warn "docker $($DockerArgs[0]) failed (attempt $i/$MaxAttempts) - retrying in ${delay}s..."
            Start-Sleep -Seconds $delay
        }
    }
    throw "docker $($DockerArgs -join ' ') failed after $MaxAttempts attempts (exit $LASTEXITCODE)"
}

# Derive registry name (hostname without domain suffix) for 'az acr login'
$registryName = ($Registry -split '\.')[0]

# ---------------------------------------------------------------------------
# Resolve resource group from param or Terraform outputs
# ---------------------------------------------------------------------------
$resourceGroup = $ResourceGroup
if (-not $resourceGroup) {
    Write-Info "Reading resource_group_name from Terraform outputs..."
    Push-Location $infraDir
    try {
        $tfOutputs = terraform output -json 2>$null | ConvertFrom-Json
        $resourceGroup = if ($tfOutputs -and $tfOutputs.resource_group_name) { $tfOutputs.resource_group_name.value } else { $null }
    } finally {
        Pop-Location
    }
}

if (-not $resourceGroup) {
    throw "Could not determine resource_group_name. Pass -ResourceGroup or ensure Terraform outputs are available."
}

Write-Info "Resource group   : $resourceGroup"

# ---------------------------------------------------------------------------
# ACR login
# ---------------------------------------------------------------------------
Write-Info "Logging in to ACR '$registryName'..."
az acr login --name $registryName
if ($LASTEXITCODE -ne 0) { throw "az acr login failed (exit $LASTEXITCODE)" }

# ---------------------------------------------------------------------------
# Build and push mbr-api
# ---------------------------------------------------------------------------
Write-Title "Building mbr-api"
$mbrApiImage = "$Registry/mbr-api:latest"
Invoke-Docker @("build", "-t", $mbrApiImage, "$root\apps\mbr-api")
Invoke-Docker @("push", $mbrApiImage)
Write-Success "mbr-api pushed: $mbrApiImage"

# ---------------------------------------------------------------------------
# Build and push mbr-tools-mcp
# ---------------------------------------------------------------------------
Write-Title "Building mbr-tools-mcp"
$mbrToolsImage = "$Registry/mbr-tools-mcp:latest"
Invoke-Docker @("build", "-t", $mbrToolsImage, "$root\apps\mbr-tools-mcp")
Invoke-Docker @("push", $mbrToolsImage)
Write-Success "mbr-tools-mcp pushed: $mbrToolsImage"

# ---------------------------------------------------------------------------
# Build and push mbr-ui
# ---------------------------------------------------------------------------
Write-Title "Building mbr-ui"
$longhaulUiImage = "$Registry/mbr-ui:latest"
Invoke-Docker @("build", "-t", $longhaulUiImage, "$root\apps\mbr-ui")
Invoke-Docker @("push", $longhaulUiImage)
Write-Success "mbr-ui pushed: $longhaulUiImage"

# ---------------------------------------------------------------------------
# Update ACA revisions
# ---------------------------------------------------------------------------
Write-Title "Updating Container App revisions"

Write-Info "Updating ca-mbr-api..."
az containerapp update `
    --name "ca-mbr-api" `
    --resource-group $resourceGroup `
    --image $mbrApiImage `
    --output none
if ($LASTEXITCODE -ne 0) { throw "az containerapp update ca-mbr-api failed (exit $LASTEXITCODE)" }
Write-Success "ca-mbr-api updated"

Write-Info "Updating ca-mbr-tools-mcp..."
az containerapp update `
    --name "ca-mbr-tools-mcp" `
    --resource-group $resourceGroup `
    --image $mbrToolsImage `
    --output none
if ($LASTEXITCODE -ne 0) { throw "az containerapp update ca-mbr-tools-mcp failed (exit $LASTEXITCODE)" }
Write-Success "ca-mbr-tools-mcp updated"

Write-Info "Updating ca-mbr-ui..."
az containerapp update `
    --name "ca-mbr-ui" `
    --resource-group $resourceGroup `
    --image $longhaulUiImage `
    --output none
if ($LASTEXITCODE -ne 0) { throw "az containerapp update ca-mbr-ui failed (exit $LASTEXITCODE)" }
Write-Success "ca-mbr-ui updated"

Write-Success "All container images built, pushed, and ACA revisions updated."
