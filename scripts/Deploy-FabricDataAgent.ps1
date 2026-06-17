<#
.SYNOPSIS
    Create the LONGHAUL Fabric Data Agent connected to the lh_mbr_trucking Lakehouse.

.DESCRIPTION
    Uses the Fabric REST API to create 'da_mbr_trucking' (idempotent).
    The Data Agent exposes the Lakehouse SQL analytics endpoint to AI Foundry agents
    via natural language queries - no Semantic Model required.

    Optionally writes fabric-data-agent-id and fabric-data-agent-url to Key Vault
    so Deploy-FoundryAgents.ps1 can pass them to agents/deploy.py at runtime.

.PARAMETER WorkspaceId
    Fabric workspace GUID.

.PARAMETER LakehouseId
    Fabric Lakehouse item GUID (lh_mbr_trucking).

.PARAMETER DataAgentName
    Display name for the Data Agent. Default: da_mbr_trucking

.PARAMETER KeyVaultUri
    Key Vault URI to store fabric-data-agent-id and fabric-data-agent-url secrets.
    Optional - skipped when not provided.

.OUTPUTS
    PSCustomObject with DataAgentId and DataAgentUrl.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]  [string]$WorkspaceId,
    [Parameter(Mandatory=$true)]  [string]$LakehouseId,
    [string]$DataAgentName = "da_mbr_trucking",
    [string]$KeyVaultUri   = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module "$PSScriptRoot\common\DeploymentFunctions.psm1" -Force

$fabricBase = "https://api.fabric.microsoft.com/v1"

# ---------------------------------------------------------------------------
# Fabric bearer token
# ---------------------------------------------------------------------------
Write-Info "Acquiring Fabric API token..."
$token = (az account get-access-token `
    --resource "https://api.fabric.microsoft.com" `
    --query accessToken -o tsv 2>$null).Trim()

if (-not $token) {
    throw "Could not acquire Fabric API token. Run 'az login'."
}

$headers = @{ "Authorization" = "Bearer $token" }

# ---------------------------------------------------------------------------
# Helper: poll Fabric LRO
# ---------------------------------------------------------------------------
function Wait-FabricOperation {
    param([string]$OperationUrl, [int]$TimeoutSeconds = 180)
    $elapsed = 0; $interval = 10
    while ($elapsed -lt $TimeoutSeconds) {
        Start-Sleep -Seconds $interval
        $elapsed += $interval
        $resp   = Invoke-RestMethod -Uri $OperationUrl -Headers $headers -Method Get -ContentType "application/json" -ErrorAction Stop
        $status = $resp.status
        Write-Info "  ${elapsed}s - status: $status"
        if ($status -eq "Succeeded") { return $resp }
        if ($status -in @("Failed","Cancelled")) { throw "Fabric operation failed: $($resp | ConvertTo-Json -Compress)" }
    }
    throw "Fabric LRO timed out after ${TimeoutSeconds}s."
}

# ---------------------------------------------------------------------------
# Check if Data Agent already exists
# ---------------------------------------------------------------------------
Write-Title "Fabric Data Agent  -  $DataAgentName"

$listUrl   = "$fabricBase/workspaces/$WorkspaceId/dataAgents"
$existing  = $null

try {
    $listResp = Invoke-RestMethod -Uri $listUrl -Headers $headers -Method Get -ContentType "application/json" -ErrorAction Stop
    $existing  = $listResp.value | Where-Object { $_.displayName -eq $DataAgentName }
} catch {
    Write-Warn "Could not list Data Agents (non-fatal): $_"
}

$dataAgentId = $null

if ($existing) {
    $dataAgentId = $existing.id
    Write-Info "Data Agent '$DataAgentName' already exists (id: $dataAgentId)"
} else {
    # -----------------------------------------------------------------------
    # Build dataAgent.json definition
    # -----------------------------------------------------------------------
    $dataAgentJson = @{
        entities = @(
            @{
                name        = "lh_mbr_trucking"
                type        = "Lakehouse"
                workspaceId = $WorkspaceId
                artifactId  = $LakehouseId
            }
        )
        instructionSets = @(
            @{
                role         = "Agent"
                instructions = @"
You are da_mbr_trucking, the data agent for LONGHAUL, a long-haul trucking company.
You have access to 13 months of operational KPI data (May 2024 to May 2025) across
5 regions (North, South, East, West, Central) and 20 vehicle types.

Available tables:
- dim_month: time dimension (month_id, period_date, period_label, year, month_num, month_name, sort_order)
- dim_region: region dimension (region_id, region_name, region_code)
- dim_vehicle_type: vehicle type dimension (vehicle_type_id, vehicle_type_name)
- fact_monthly_kpis: monthly KPIs per region (revenue, miles, costs, deliveries, driver counts, incidents)
- fact_vehicle_kpis: monthly KPIs per region and vehicle type (miles, fuel cost, delivery performance)

Always join fact tables with dimension tables to return human-readable labels.
Express financial values in dollars. Express miles as whole numbers.
When comparing periods, calculate percentage change and indicate direction (up/down).
"@
            }
        )
    } | ConvertTo-Json -Depth 10 -Compress

    $encodedDefinition = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($dataAgentJson))

    $createBody = @{
        displayName = $DataAgentName
        description = "LONGHAUL MBR trucking data agent - queries lh_mbr_trucking Lakehouse"
        definition  = @{
            parts = @(
                @{
                    path        = "dataAgent.json"
                    payload     = $encodedDefinition
                    payloadType = "InlineBase64"
                }
            )
        }
    } | ConvertTo-Json -Depth 10 -Compress

    Write-Info "Creating Data Agent '$DataAgentName'..."

    try {
        $createResp = Invoke-WebRequest `
            -Uri             "$fabricBase/workspaces/$WorkspaceId/dataAgents" `
            -Headers         $headers `
            -Method          Post `
            -Body            ([System.Text.Encoding]::UTF8.GetBytes($createBody)) `
            -ContentType     "application/json" `
            -UseBasicParsing `
            -ErrorAction     Stop
    } catch {
        $errBody = $null
        if ($_.Exception.Response) {
            try {
                $stream  = $_.Exception.Response.GetResponseStream()
                $reader  = New-Object System.IO.StreamReader($stream)
                $errBody = $reader.ReadToEnd()
            } catch {}
        }
        $detail = if ($errBody) { " - $errBody" } else { "" }
        throw "Data Agent creation failed: $_$detail"
    }

    if ($createResp.StatusCode -eq 201) {
        $dataAgentId = ($createResp.Content | ConvertFrom-Json).id
        Write-Success "Data Agent created (id: $dataAgentId)"
    } elseif ($createResp.StatusCode -eq 202) {
        $operationUrl = $createResp.Headers["Location"]
        if (-not $operationUrl) {
            $opId         = $createResp.Headers["x-ms-operation-id"]
            $operationUrl = "$fabricBase/operations/$opId"
        }
        Write-Info "Data Agent provisioning async - polling..."
        $null = Wait-FabricOperation -OperationUrl $operationUrl

        $listResp    = Invoke-RestMethod -Uri $listUrl -Headers $headers -Method Get -ContentType "application/json" -ErrorAction Stop
        $created     = $listResp.value | Where-Object { $_.displayName -eq $DataAgentName }
        if (-not $created) { throw "Data Agent not found after async creation." }
        $dataAgentId = $created.id
        Write-Success "Data Agent provisioned (id: $dataAgentId)"
    } else {
        throw "Unexpected status $($createResp.StatusCode) from Fabric create Data Agent."
    }
}

# ---------------------------------------------------------------------------
# Build inference URL (chat completions endpoint)
# ---------------------------------------------------------------------------
$dataAgentUrl = "$fabricBase/workspaces/$WorkspaceId/dataAgents/$dataAgentId/chat/completions"
Write-Info "Data Agent URL: $dataAgentUrl"

# ---------------------------------------------------------------------------
# Store in Key Vault (optional)
# ---------------------------------------------------------------------------
if ($KeyVaultUri) {
    $kvName = ($KeyVaultUri -split '\.')[0] -replace 'https://',''
    Write-Info "Storing Data Agent secrets in Key Vault '$kvName'..."

    az keyvault secret set --vault-name $kvName --name "fabric-data-agent-id"  --value $dataAgentId  --output none
    az keyvault secret set --vault-name $kvName --name "fabric-data-agent-url" --value $dataAgentUrl --output none

    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Key Vault secret write failed - continuing without KV storage."
    } else {
        Write-Success "Secrets written: fabric-data-agent-id, fabric-data-agent-url"
    }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== Fabric Data Agent Ready ===" -ForegroundColor Cyan
Write-Host "  Workspace ID  : $WorkspaceId"  -ForegroundColor Gray
Write-Host "  Data Agent ID : $dataAgentId"  -ForegroundColor Gray
Write-Host "  URL           : $dataAgentUrl" -ForegroundColor Green
Write-Host ""

[PSCustomObject]@{
    DataAgentId  = $dataAgentId
    DataAgentUrl = $dataAgentUrl
}
