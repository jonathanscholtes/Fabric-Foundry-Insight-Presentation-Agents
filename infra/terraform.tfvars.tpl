subscription_id = "${SubscriptionId}"
tenant_id       = "${TenantId}"
location        = "${Location}"
environment     = "${Environment}"
resource_token  = "${ResourceToken}"

# ---------------------------------------------------------------------------
# Naming convention: <caf-abbr>-mbr-<env>-<token>
# Token prevents soft-delete conflicts on globally-scoped resources.
# Key Vault names are reserved for 90 days after destroy.
# ACR and Storage names are globally unique (alphanumeric only; no dashes).
# ---------------------------------------------------------------------------

resource_group_name = "rg-mbr-${Environment}-${ResourceToken}"

# Identity
app_identity_name    = "id-mbr-${Environment}-app"
deploy_identity_name = "id-mbr-${Environment}-deploy"

# Secrets
key_vault_name = "kv-mbr-${Environment}-${ResourceToken}"

# Observability
app_insights_name            = "appi-mbr-${Environment}-${ResourceToken}"
log_analytics_workspace_name = "log-mbr-${Environment}-${ResourceToken}"

# AI Foundry
ai_services_name = "ais-mbr-${Environment}-${ResourceToken}"
ai_project_name  = "proj-mbr-${Environment}-${ResourceToken}"

# Container infrastructure
# ACR: alphanumeric only (no dashes), 5-50 chars
# Storage: alphanumeric lowercase only (no dashes), 3-24 chars
container_registry_name = "crmbr${ResourceToken}"
storage_account_name    = "sambr${Environment}${ResourceToken}"
container_app_env_name  = "cae-mbr-${Environment}-${ResourceToken}"

# ---------------------------------------------------------------------------
# Fabric (populated by Deploy-FabricWorkspace.ps1 or supplied manually)
# ---------------------------------------------------------------------------
fabric_workspace_id = "${FabricWorkspaceId}"
fabric_sql_server   = "${FabricSqlServer}"
fabric_sql_database = "lh-mbr-trucking"

# ---------------------------------------------------------------------------
# GitHub OIDC (populated by New-GitHubOidc.ps1 or -SetupGitHub flag)
# ---------------------------------------------------------------------------
github_org        = "${GitHubOrg}"
github_repository = "${GitHubRepository}"

tags = {
  project     = "longhaul-mbr-ai-agents"
  environment = "${Environment}"
}
