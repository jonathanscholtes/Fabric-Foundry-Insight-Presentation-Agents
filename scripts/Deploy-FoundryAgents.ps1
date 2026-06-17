<#
.SYNOPSIS
    Deploy or update LONGHAUL Foundry agents and inject their IDs into ca-mbr-api.

.DESCRIPTION
    Resolves the Foundry project endpoint and MCP server URL from Terraform outputs
    (or explicit params), creates/updates both agents via agents/deploy.py, then
    writes agent IDs to agents/agent_ids.json and injects them as environment
    variables on the ca-mbr-api Container App.

    MCP URL resolution (in priority order):
      1. -McpServerUrl param / MCP_SERVER_URL env var
      2. Foundry project connection named -McpConnectionName
      3. Key Vault secret 'mcp-server-url' (-KeyVaultUri / KEY_VAULT_URI env var)
      4. None - presentation agent created without MCP tools; re-run later.

.PARAMETER ProjectEndpoint
    Foundry project endpoint URL.  Falls back to FOUNDRY_PROJECT_ENDPOINT env var,
    then to the foundry_project_endpoint Terraform output.

.PARAMETER McpServerUrl
    Direct URL of the mbr-tools-mcp MCP server.  Falls back to MCP_SERVER_URL env var,
    then to https://<mcp_tools_api_fqdn> from Terraform outputs.

.PARAMETER ModelDeployment
    Full-tier model deployment name.  Default: gpt-4.1

.PARAMETER MiniModelDeployment
    Mini-tier model deployment name (used by agents with MODEL_TIER = "mini").
    Default: gpt-4.1-mini

.PARAMETER McpConnectionName
    Foundry project connection name that stores the MCP server URL.
    Default: mbr-tools-mcp

.PARAMETER FabricDataAgentUrl
    Direct chat/completions URL of the Fabric Data Agent (da_mbr_trucking).
    Falls back to Key Vault secret 'fabric-data-agent-url', then Foundry connection fallback.

.PARAMETER FabricConnectionName
    Foundry connection name for the Fabric Data Agent. Default: da-mbr-trucking

.PARAMETER KeyVaultUri
    Key Vault URI for MCP URL and Fabric Data Agent URL fallback lookup.
    Falls back to KEY_VAULT_URI env var, then to key_vault_uri Terraform output.

.EXAMPLE
    .\scripts\Deploy-FoundryAgents.ps1
    .\scripts\Deploy-FoundryAgents.ps1 -McpServerUrl https://ca-mbr-tools-mcp.internal.example.com
#>
[CmdletBinding()]
param(
    [string] $ProjectEndpoint      = $env:FOUNDRY_PROJECT_ENDPOINT,
    [string] $McpServerUrl         = $env:MCP_SERVER_URL,
    [string] $ModelDeployment      = "gpt-4.1",
    [string] $MiniModelDeployment  = "gpt-4.1-mini",
    [string] $McpConnectionName    = "mbr-tools-mcp",
    [string] $FabricDataAgentUrl   = $env:FABRIC_DATA_AGENT_URL,
    [string] $FabricConnectionName = "da-mbr-trucking",
    [string] $KeyVaultUri          = $env:KEY_VAULT_URI
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module "$PSScriptRoot\common\DeploymentFunctions.psm1" -Force

$root     = Resolve-Path "$PSScriptRoot\.."
$infraDir = Join-Path $root "infra"

# ---------------------------------------------------------------------------
# Resolve endpoint, MCP URL, and Key Vault URI from Terraform outputs when not supplied
# ---------------------------------------------------------------------------
if (-not $ProjectEndpoint -or -not $McpServerUrl -or -not $KeyVaultUri) {
    Write-Info "Reading Terraform outputs..."
    Push-Location $infraDir
    try {
        $tfOut = terraform output -json 2>$null | ConvertFrom-Json
    } finally {
        Pop-Location
    }

    if (-not $ProjectEndpoint -and $tfOut -and $tfOut.foundry_project_endpoint) {
        $ProjectEndpoint = $tfOut.foundry_project_endpoint.value
    }
    if (-not $McpServerUrl -and $tfOut -and $tfOut.mcp_tools_api_fqdn) {
        $McpServerUrl = "https://$($tfOut.mcp_tools_api_fqdn.value)"
    }
    if (-not $KeyVaultUri -and $tfOut -and $tfOut.key_vault_uri) {
        $KeyVaultUri = $tfOut.key_vault_uri.value
    }
    if (-not $ModelDeployment -and $tfOut -and $tfOut.model_deployment) {
        $ModelDeployment = $tfOut.model_deployment.value
    }
    if (-not $MiniModelDeployment -and $tfOut -and $tfOut.mini_model_deployment) {
        $MiniModelDeployment = $tfOut.mini_model_deployment.value
    }
    if ($tfOut -and $tfOut.resource_group_name) {
        $script:RgName = $tfOut.resource_group_name.value
    }
}

if (-not $ProjectEndpoint) {
    throw "-ProjectEndpoint not set and foundry_project_endpoint not in Terraform outputs."
}

Write-Info "Foundry endpoint       : $ProjectEndpoint"
Write-Info "MCP server URL         : $(if ($McpServerUrl) { $McpServerUrl } else { '(none - Key Vault or Foundry connection fallback)' })"
Write-Info "Model deployment       : $ModelDeployment"
Write-Info "Mini model deployment  : $MiniModelDeployment"
Write-Info "MCP connection         : $McpConnectionName"
Write-Info "Fabric Data Agent URL  : $(if ($FabricDataAgentUrl) { $FabricDataAgentUrl } else { '(none - Key Vault or Foundry connection fallback)' })"
Write-Info "Fabric connection name : $FabricConnectionName"
Write-Info "Key Vault URI          : $(if ($KeyVaultUri) { $KeyVaultUri } else { '(not set)' })"

# ---------------------------------------------------------------------------
# Python venv + dependencies
# ---------------------------------------------------------------------------
Write-Title "Installing agent SDK dependencies"

if (-not (Test-Path "$root\.venv")) {
    python -m venv "$root\.venv"
}
& "$root\.venv\Scripts\python.exe" -m pip install -q -r "$root\agents\requirements.txt"
if ($LASTEXITCODE -ne 0) { throw "pip install failed (exit $LASTEXITCODE)" }

# ---------------------------------------------------------------------------
# Run agents/deploy.py
# ---------------------------------------------------------------------------
Write-Title "Deploying agents"

$agentIdsFile = Join-Path $root "agents" "agent_ids.json"

$agentArgs = @(
    "$root\agents\deploy.py",
    "--project-endpoint",      $ProjectEndpoint,
    "--model-deployment",      $ModelDeployment,
    "--mini-model-deployment",  $MiniModelDeployment,
    "--mcp-connection-name",   $McpConnectionName,
    "--output",                $agentIdsFile
)
if ($McpServerUrl)       { $agentArgs += @("--mcp-server-url",         $McpServerUrl)       }
if ($KeyVaultUri)        { $agentArgs += @("--key-vault-uri",          $KeyVaultUri)        }
if ($FabricDataAgentUrl) { $agentArgs += @("--fabric-data-agent-url",  $FabricDataAgentUrl) }
if ($FabricConnectionName) { $agentArgs += @("--fabric-connection-name", $FabricConnectionName) }

& "$root\.venv\Scripts\python.exe" @agentArgs
if ($LASTEXITCODE -ne 0) { throw "agents/deploy.py failed (exit $LASTEXITCODE)" }

Write-Success "Agents deployed. IDs written to agents/agent_ids.json"

# ---------------------------------------------------------------------------
# Inject agent IDs into ca-mbr-api Container App
# ---------------------------------------------------------------------------
if (-not (Test-Path $agentIdsFile)) {
    Write-Warn "agent_ids.json not found - skipping Container App env-var update."
    return
}

$ids = Get-Content $agentIdsFile -Raw | ConvertFrom-Json

$convId = $ids.'longhaul-conversational-agent'
$presId = $ids.'longhaul-mbr-presentation-agent'

if (-not $convId -or -not $presId) {
    Write-Warn "Could not read agent IDs from agent_ids.json - skipping env-var update."
    return
}

Write-Info "Conversational Agent ID   : $convId"
Write-Info "MBR Presentation Agent ID : $presId"

if (-not $script:RgName) {
    Push-Location $infraDir
    try {
        $script:RgName = terraform output -raw resource_group_name 2>$null
    } finally {
        Pop-Location
    }
}

if ($script:RgName) {
    Write-Info "Injecting agent IDs into ca-mbr-api (RG: $($script:RgName))..."
    az containerapp update `
        --name           "ca-mbr-api" `
        --resource-group $script:RgName `
        --set-env-vars   "CONVERSATIONAL_AGENT_ID=$convId" "MBR_PRESENTATION_AGENT_ID=$presId" `
        --output         none
    if ($LASTEXITCODE -ne 0) { throw "az containerapp update failed (exit $LASTEXITCODE)" }
    Write-Success "Agent IDs injected into ca-mbr-api."
} else {
    Write-Warn "resource_group_name not available - skipping Container App update."
    Write-Info "Set manually:"
    Write-Info "  CONVERSATIONAL_AGENT_ID    = $convId"
    Write-Info "  MBR_PRESENTATION_AGENT_ID  = $presId"
}
