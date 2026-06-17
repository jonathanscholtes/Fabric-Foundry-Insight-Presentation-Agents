# Seed the Fabric Lakehouse, upload the MBR PowerPoint template, and
# pre-render slide thumbnail placeholders for the LONGHAUL application.

param(
    [Parameter(Mandatory=$true)]
    [string]$SqlServer,

    [Parameter(Mandatory=$false)]
    [string]$WorkspaceId = "",

    [Parameter(Mandatory=$false)]
    [string]$LakehouseId = "",

    [Parameter(Mandatory=$false)]
    [string]$StorageAccountName = "",

    # Skip seed_data.py (tables still created; useful on re-runs when data already exists).
    [Parameter(Mandatory=$false)]
    [switch]$SkipSeed
)

Import-Module "$PSScriptRoot\common\DeploymentFunctions.psm1" -Force

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root     = Resolve-Path "$PSScriptRoot\.."
$infraDir = Join-Path $root "infra"

# ---------------------------------------------------------------------------
# Resolve storage account name from Terraform outputs if not passed
# ---------------------------------------------------------------------------
if (-not $StorageAccountName) {
    Write-Info "Reading storage_account_name from Terraform outputs..."
    Push-Location $infraDir
    try {
        $StorageAccountName = terraform output -raw storage_account_name 2>$null
    } finally {
        Pop-Location
    }

    if (-not $StorageAccountName) {
        throw "Could not determine storage_account_name. Pass -StorageAccountName or ensure Terraform outputs are available."
    }
}

Write-Info "Workspace ID          : $WorkspaceId"
Write-Info "Lakehouse ID          : $LakehouseId"
Write-Info "SQL Server            : $SqlServer"
Write-Info "Storage Account       : $StorageAccountName"

# ---------------------------------------------------------------------------
# Install Python dependencies
# ---------------------------------------------------------------------------
Write-Title "Installing Python dependencies"
pip install pyodbc azure-identity openpyxl requests deltalake pandas pyarrow --quiet
if ($LASTEXITCODE -ne 0) { throw "pip install failed (exit $LASTEXITCODE)" }
Write-Success "Python dependencies installed"

# ---------------------------------------------------------------------------
# Run setup_lakehouse.py  -  creates tables in the Fabric Lakehouse
# ---------------------------------------------------------------------------
Write-Title "Setting up Lakehouse tables"
Push-Location $root
try {
    if (-not $WorkspaceId -or -not $LakehouseId) {
        Write-Warn "WorkspaceId or LakehouseId missing - cannot create Lakehouse tables via OneLake. Skipping."
    } else {
        $setupArgs = @("fabric/scripts/setup_lakehouse.py", "--workspace-id", $WorkspaceId, "--lakehouse-id", $LakehouseId)
        python @setupArgs
        if ($LASTEXITCODE -ne 0) { throw "setup_lakehouse.py failed (exit $LASTEXITCODE)" }
        Write-Success "Lakehouse tables created"
    }
} finally {
    Pop-Location
}

# ---------------------------------------------------------------------------
# Run seed_data.py  -  loads 13 months of synthetic trucking KPI data
# ---------------------------------------------------------------------------
if ($SkipSeed) {
    Write-Info "Skipping seed_data.py (-SkipSeed)"
} else {
    Write-Title "Seeding Lakehouse data"
    Push-Location $root
    try {
        if (-not $WorkspaceId -or -not $LakehouseId) {
            Write-Warn "WorkspaceId or LakehouseId missing - cannot seed via OneLake. Skipping."
        } else {
            $seedArgs = @("fabric/scripts/seed_data.py", "--workspace-id", $WorkspaceId, "--lakehouse-id", $LakehouseId)
            python @seedArgs
        }
        if ($LASTEXITCODE -ne 0) { throw "seed_data.py failed (exit $LASTEXITCODE)" }
        Write-Success "Lakehouse seeded with 13 months of synthetic data"
    } finally {
        Pop-Location
    }
}

# ---------------------------------------------------------------------------
# Upload mbr_template.pptx to Storage templates container
# ---------------------------------------------------------------------------
Write-Title "Uploading MBR template to Storage"

$templatePath = Join-Path $root "data\templates\mbr_template.pptx"
if (-not (Test-Path $templatePath)) {
    Write-Warn "mbr_template.pptx not found - skipping template upload."
    Write-Warn "Place the file at data/templates/mbr_template.pptx and re-run Deploy-FabricLakehouse.ps1 to upload it."
} else {
    az storage blob upload `
        --account-name   $StorageAccountName `
        --container-name templates `
        --name           mbr_template.pptx `
        --file           $templatePath `
        --auth-mode      login `
        --overwrite      true
    if ($LASTEXITCODE -ne 0) { throw "Template upload failed (exit $LASTEXITCODE)" }
    Write-Success "mbr_template.pptx uploaded to templates container"
}

# ---------------------------------------------------------------------------
# Upload slide thumbnail placeholders to Storage thumbnails container
# ---------------------------------------------------------------------------
Write-Title "Uploading slide thumbnail placeholders to Storage"

$thumbnailsDir = Join-Path $root "data\templates\thumbnails"
$thumbnails    = Get-ChildItem $thumbnailsDir -Filter "*.png" -ErrorAction SilentlyContinue

if (-not $thumbnails -or $thumbnails.Count -eq 0) {
    Write-Warn "No .png thumbnails found in $thumbnailsDir  -  skipping thumbnail upload."
    Write-Warn "Create slide-01.png through slide-06.png (screenshots of the blank template slides)"
    Write-Warn "and re-run this script. See data/templates/thumbnails/README.md for guidance."
} else {
    foreach ($thumb in $thumbnails) {
        $blobName = "templates/mbr_template/$($thumb.Name)"
        az storage blob upload `
            --account-name  $StorageAccountName `
            --container-name thumbnails `
            --name          $blobName `
            --file          $thumb.FullName `
            --auth-mode     login `
            --overwrite     true
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Failed to upload thumbnail $($thumb.Name) (exit $LASTEXITCODE)  -  continuing."
        } else {
            Write-Success "Uploaded thumbnail: $blobName"
        }
    }
    Write-Success "Slide thumbnails uploaded to thumbnails/templates/mbr_template/"
}

Write-Success "Deploy-FabricLakehouse complete."
Write-Host ""
Write-Host "=== Next Steps ===" -ForegroundColor Cyan
Write-Host "  1. Complete Fabric portal steps (Section 11 of project.md):" -ForegroundColor Gray
Write-Host "       - Create Semantic Model 'sm-mbr-trucking' over the 5 Lakehouse tables" -ForegroundColor Gray
Write-Host "       - Define all DAX measures (see docs/fabric-setup.md)" -ForegroundColor Gray
Write-Host "       - Mark dim_month as Date Table on period_date column" -ForegroundColor Gray
Write-Host "       - Create Data Agent 'da-mbr-trucking' over sm-mbr-trucking" -ForegroundColor Gray
Write-Host "       - Connect da-mbr-trucking to AI Foundry project (connection name: da-mbr-trucking)" -ForegroundColor Gray
Write-Host "  2. Grant Managed Identity Contributor on the Fabric workspace:" -ForegroundColor Gray
$clientId = terraform -chdir="$root\infra" output -raw app_identity_client_id 2>$null
if ($clientId) {
    Write-Host "       Client ID: $clientId" -ForegroundColor Gray
    Write-Host "       Fabric portal -> Workspace 'mbr-trucking' -> Settings -> Manage access -> Add as Contributor" -ForegroundColor Gray
}
Write-Host "  3. Run Phase 4: .\scripts\Deploy-FoundryAgents.ps1" -ForegroundColor Gray
