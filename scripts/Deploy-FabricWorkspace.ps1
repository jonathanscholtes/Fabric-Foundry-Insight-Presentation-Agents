<#
.SYNOPSIS
    Create the LONGHAUL Fabric Lakehouse and discover its SQL analytics endpoint.

.DESCRIPTION
    Uses the Fabric REST API to:
      1. Create Lakehouse 'lh_mbr_trucking' in the specified workspace (idempotent).
      2. Poll the long-running operation until provisioning completes.
      3. Poll GET Lakehouse until sqlEndpointProperties.provisioningStatus = "Success".
      4. Return the SQL analytics endpoint hostname.
      5. Optionally update infra/terraform.tfvars with fabric_sql_server.

    The Semantic Model ('sm-mbr-trucking') and Data Agent ('da-mbr-trucking') still
    require manual Fabric portal steps  -  see docs/fabric-setup.md.

    Auth: uses the current 'az login' session.  The signed-in principal must have
    Contributor (or higher) access to the Fabric workspace.

.PARAMETER WorkspaceId
    Fabric workspace GUID.

.PARAMETER LakehouseName
    Lakehouse display name.  Default: lh_mbr_trucking

.PARAMETER UpdateTfvars
    When set, writes the resolved SQL server hostname into infra/terraform.tfvars.

.OUTPUTS
    SQL analytics endpoint hostname string, e.g.
    <token>.datawarehouse.fabric.microsoft.com

.EXAMPLE
    $sqlServer = .\scripts\Deploy-FabricWorkspace.ps1 -WorkspaceId "cfafbeb1-..."
    .\scripts\Deploy-FabricLakehouse.ps1 -SqlServer $sqlServer
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $WorkspaceId,

    [string] $LakehouseName = "lh_mbr_trucking",

    [switch] $UpdateTfvars
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module "$PSScriptRoot\common\DeploymentFunctions.psm1" -Force

$fabricBase = "https://api.fabric.microsoft.com/v1"

# ---------------------------------------------------------------------------
# Fabric bearer token (current az login context)
# ---------------------------------------------------------------------------
Write-Info "Acquiring Fabric API token..."
$token = (az account get-access-token `
    --resource "https://api.fabric.microsoft.com" `
    --query accessToken -o tsv 2>$null).Trim()

if (-not $token) {
    throw "Could not acquire Fabric API token. Run 'az login' and ensure the account has Contributor on the workspace."
}

$headers = @{
    "Authorization" = "Bearer $token"
}

# ---------------------------------------------------------------------------
# Helper: poll an LRO until terminal state
# ---------------------------------------------------------------------------
function Wait-FabricOperation {
    param([string]$OperationUrl, [int]$TimeoutSeconds = 300)

    $elapsed = 0
    $interval = 10
    Write-Info "Polling LRO: $OperationUrl"

    while ($elapsed -lt $TimeoutSeconds) {
        Start-Sleep -Seconds $interval
        $elapsed += $interval

        $resp = Invoke-RestMethod -Uri $OperationUrl -Headers $headers -Method Get -ContentType "application/json" -ErrorAction Stop
        $status = $resp.status

        Write-Info "  $($elapsed)s  -  status: $status"

        if ($status -eq "Succeeded") { return $resp }
        if ($status -in @("Failed", "Cancelled")) {
            throw "Fabric operation failed: $($resp | ConvertTo-Json -Compress)"
        }
    }
    throw "Fabric LRO timed out after ${TimeoutSeconds}s."
}

# ---------------------------------------------------------------------------
# Step 1: Check if Lakehouse already exists
# ---------------------------------------------------------------------------
Write-Title "Fabric Lakehouse  -  $LakehouseName"

$listUrl = "$fabricBase/workspaces/$WorkspaceId/lakehouses"
$existing = $null

try {
    $listResp = Invoke-RestMethod -Uri $listUrl -Headers $headers -Method Get -ErrorAction Stop
    $existing  = $listResp.value | Where-Object { $_.displayName -eq $LakehouseName }
} catch {
    Write-Warn "Could not list lakehouses (non-fatal): $_"
}

$lakehouseId = $null

if ($existing) {
    $lakehouseId = $existing.id
    Write-Info "Lakehouse '$LakehouseName' already exists (id: $lakehouseId)"
} else {
    # ---------------------------------------------------------------------------
    # Step 2: Create Lakehouse
    # ---------------------------------------------------------------------------
    Write-Info "Creating Lakehouse '$LakehouseName'..."

    $body = @{ displayName = $LakehouseName; description = "LONGHAUL MBR trucking data" } | ConvertTo-Json -Compress

    try {
        $createResp = Invoke-WebRequest `
            -Uri             "$fabricBase/workspaces/$WorkspaceId/lakehouses" `
            -Headers         $headers `
            -Method          Post `
            -Body            ([System.Text.Encoding]::UTF8.GetBytes($body)) `
            -ContentType     "application/json" `
            -UseBasicParsing `
            -ErrorAction     Stop
    } catch {
        $errBody = $null
        if ($_.Exception.Response) {
            try {
                $stream = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($stream)
                $errBody = $reader.ReadToEnd()
            } catch {}
        }
        $detail = if ($errBody) { " - $errBody" } else { "" }
        throw "Lakehouse creation failed: $_$detail"
    }

    if ($createResp.StatusCode -eq 201) {
        # Synchronous creation  -  ID in body
        $lakehouseId = ($createResp.Content | ConvertFrom-Json).id
        Write-Success "Lakehouse created (id: $lakehouseId)"
    } elseif ($createResp.StatusCode -eq 202) {
        # Async creation  -  poll LRO then get item from Location or re-list
        $operationUrl = $createResp.Headers["Location"]
        if (-not $operationUrl) {
            $operationUrl = $createResp.Headers["x-ms-operation-id"]
            $operationUrl = "$fabricBase/operations/$operationUrl"
        }
        Write-Info "Lakehouse provisioning async  -  polling..."
        $null = Wait-FabricOperation -OperationUrl $operationUrl

        # Re-list to get the lakehouse ID
        $listResp  = Invoke-RestMethod -Uri $listUrl -Headers $headers -Method Get -ErrorAction Stop
        $created   = $listResp.value | Where-Object { $_.displayName -eq $LakehouseName }
        if (-not $created) { throw "Lakehouse not found after async creation." }
        $lakehouseId = $created.id
        Write-Success "Lakehouse provisioned (id: $lakehouseId)"
    } else {
        throw "Unexpected status $($createResp.StatusCode) from Fabric create Lakehouse."
    }
}

# ---------------------------------------------------------------------------
# Step 3: Poll GET Lakehouse until SQL endpoint is ready
# ---------------------------------------------------------------------------
Write-Info "Waiting for SQL analytics endpoint to provision..."

$getUrl   = "$fabricBase/workspaces/$WorkspaceId/lakehouses/$lakehouseId"
$sqlServer = $null
$maxWait   = 300
$waited    = 0
$interval  = 15

while ($waited -lt $maxWait) {
    $lh     = Invoke-RestMethod -Uri $getUrl -Headers $headers -Method Get -ErrorAction Stop
    $sqlProp = $lh.properties.sqlEndpointProperties

    if ($sqlProp -and $sqlProp.provisioningStatus -eq "Success" -and $sqlProp.connectionString) {
        $sqlServer = $sqlProp.connectionString.Trim()
        break
    }

    $status = if ($sqlProp) { $sqlProp.provisioningStatus } else { "pending" }
    Write-Info "  $($waited)s  -  SQL endpoint: $status"
    Start-Sleep -Seconds $interval
    $waited += $interval
}

if (-not $sqlServer) {
    throw "SQL analytics endpoint did not reach 'Success' within ${maxWait}s."
}

Write-Success "SQL analytics endpoint ready: $sqlServer"

# ---------------------------------------------------------------------------
# Step 4: Optionally write hostname back into terraform.tfvars
# ---------------------------------------------------------------------------
if ($UpdateTfvars) {
    $tfvarsPath = Join-Path (Resolve-Path "$PSScriptRoot\..\infra") "terraform.tfvars"
    if (Test-Path $tfvarsPath) {
        $content = Get-Content $tfvarsPath -Raw
        if ($content -match 'fabric_sql_server\s*=\s*"[^"]*"') {
            $content = $content -replace 'fabric_sql_server\s*=\s*"[^"]*"', "fabric_sql_server = `"$sqlServer`""
        } else {
            $content = $content.TrimEnd() + "`nfabric_sql_server = `"$sqlServer`"`n"
        }
        Set-Content -Path $tfvarsPath -Value $content -Encoding UTF8
        Write-Success "fabric_sql_server written to terraform.tfvars"
    } else {
        Write-Warn "terraform.tfvars not found  -  could not update fabric_sql_server."
    }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== Fabric Lakehouse Ready ===" -ForegroundColor Cyan
Write-Host "  Workspace ID  : $WorkspaceId"  -ForegroundColor Gray
Write-Host "  Lakehouse ID  : $lakehouseId"  -ForegroundColor Gray
Write-Host "  SQL Server    : $sqlServer"     -ForegroundColor Green
Write-Host ""
Write-Host "Next steps (manual  -  Fabric portal):" -ForegroundColor Cyan
Write-Host "  1. Create Semantic Model 'sm-mbr-trucking' over the 5 Lakehouse tables" -ForegroundColor Gray
Write-Host "  2. Define DAX measures + mark dim_month as Date Table (period_date column)" -ForegroundColor Gray
Write-Host "  3. Create Data Agent 'da-mbr-trucking' connected to sm-mbr-trucking" -ForegroundColor Gray
Write-Host "  4. Connect da-mbr-trucking to AI Foundry (connection name: da-mbr-trucking)" -ForegroundColor Gray
Write-Host "  See: docs/fabric-setup.md" -ForegroundColor Gray
Write-Host ""

# Return structured result so callers can capture both values
[PSCustomObject]@{
    SqlServer   = $sqlServer
    LakehouseId = $lakehouseId
}
