# Build container images in ACR and update ACA revisions.
# Uses 'az acr build' - no local Docker daemon required.

param(
    [Parameter(Mandatory=$false)]
    [string]$Registry = "",

    # Resource group name - passed from deploy.ps1 Phase 2 to avoid a redundant TF output read.
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

# ACR name (hostname without .azurecr.io suffix) required by az acr build --registry
$registryName = ($Registry -split '\.')[0]

Write-Info "ACR               : $Registry"
Write-Info "ACR name          : $registryName"

# ---------------------------------------------------------------------------
# Resolve resource group from param or Terraform outputs
# ---------------------------------------------------------------------------
$resourceGroup = $ResourceGroup
if (-not $resourceGroup) {
    Write-Info "Reading resource_group_name from Terraform outputs..."
    Push-Location $infraDir
    try {
        $tfOutputs    = terraform output -json 2>$null | ConvertFrom-Json
        $resourceGroup = if ($tfOutputs -and $tfOutputs.resource_group_name) { $tfOutputs.resource_group_name.value } else { $null }
    } finally {
        Pop-Location
    }
}

if (-not $resourceGroup) {
    throw "Could not determine resource_group_name. Pass -ResourceGroup or ensure Terraform outputs are available."
}

Write-Info "Resource group    : $resourceGroup"

# ---------------------------------------------------------------------------
# Retry helper for az acr build (handles transient ACR Task failures)
# ---------------------------------------------------------------------------
function Invoke-AcrBuild {
    param(
        [string]   $RegistryName,
        [string]   $Image,
        [string]   $ContextPath,
        [string[]] $BuildArgs = @(),
        [int]      $MaxAttempts = 3
    )

    $acrArgs = @(
        "acr", "build",
        "--registry", $RegistryName,
        "--image",    $Image
    )
    foreach ($arg in $BuildArgs) { $acrArgs += @("--build-arg", $arg) }
    $acrArgs += $ContextPath

    for ($i = 1; $i -le $MaxAttempts; $i++) {
        Write-Info "az acr build $Image (attempt $i/$MaxAttempts)..."
        az @acrArgs
        if ($LASTEXITCODE -eq 0) { return }
        if ($i -lt $MaxAttempts) {
            $delay = $i * 30
            Write-Warn "az acr build failed (attempt $i) - retrying in ${delay}s..."
            Start-Sleep -Seconds $delay
        }
    }
    throw "az acr build $Image failed after $MaxAttempts attempts (exit $LASTEXITCODE)"
}

# ---------------------------------------------------------------------------
# Build mbr-api
# ---------------------------------------------------------------------------
Write-Title "Building mbr-api"
Invoke-AcrBuild -RegistryName $registryName `
                -Image        "mbr-api:latest" `
                -ContextPath  "$root\apps\mbr-api"
Write-Success "mbr-api built and pushed"

# ---------------------------------------------------------------------------
# Build mbr-tools-mcp
# ---------------------------------------------------------------------------
Write-Title "Building mbr-tools-mcp"
Invoke-AcrBuild -RegistryName $registryName `
                -Image        "mbr-tools-mcp:latest" `
                -ContextPath  "$root\apps\mbr-tools-mcp"
Write-Success "mbr-tools-mcp built and pushed"

# ---------------------------------------------------------------------------
# Build mbr-ui  (VITE_API_BASE_URL baked at build time)
# ---------------------------------------------------------------------------
Write-Title "Building mbr-ui"
Invoke-AcrBuild -RegistryName $registryName `
                -Image        "mbr-ui:latest" `
                -ContextPath  "$root\apps\mbr-ui" `
                -BuildArgs    @("VITE_API_BASE_URL=/api")
Write-Success "mbr-ui built and pushed"

# ---------------------------------------------------------------------------
# Update ACA revisions
# ---------------------------------------------------------------------------
Write-Title "Updating Container App revisions"

$images = @{
    "ca-mbr-api"       = "$Registry/mbr-api:latest"
    "ca-mbr-tools-mcp" = "$Registry/mbr-tools-mcp:latest"
    "ca-mbr-ui"        = "$Registry/mbr-ui:latest"
}

foreach ($app in $images.Keys) {
    Write-Info "Updating $app..."
    az containerapp update `
        --name           $app `
        --resource-group $resourceGroup `
        --image          $images[$app] `
        --output         none
    if ($LASTEXITCODE -ne 0) { throw "az containerapp update $app failed (exit $LASTEXITCODE)" }
    Write-Success "$app updated"
}

Write-Success "All images built in ACR and Container App revisions updated."
