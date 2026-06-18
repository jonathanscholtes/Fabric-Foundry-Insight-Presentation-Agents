# ── Current caller identity ────────────────────────────────────────────────────
data "azurerm_client_config" "current" {}

locals {
  tags = merge(var.tags, { environment = var.environment, managed-by = "terraform" })
}

# ── Resource group ─────────────────────────────────────────────────────────────
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}

# ── Modules ────────────────────────────────────────────────────────────────────

module "identity" {
  source               = "./modules/identity"
  resource_group_name  = azurerm_resource_group.main.name
  location             = var.location
  app_identity_name    = var.app_identity_name
  deploy_identity_name = var.deploy_identity_name
  github_org           = var.github_org
  github_repository    = var.github_repository
  tags                 = local.tags
}

module "key_vault" {
  source              = "./modules/key_vault"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  key_vault_name      = var.key_vault_name
  tenant_id           = var.tenant_id
  principal_ids = {
    app_identity    = module.identity.app_identity_principal_id
    deploy_identity = module.identity.deploy_identity_principal_id
    current_user    = data.azurerm_client_config.current.object_id
  }
  tags = local.tags
}

module "monitoring" {
  source                       = "./modules/monitoring"
  resource_group_name          = azurerm_resource_group.main.name
  location                     = var.location
  app_insights_name            = var.app_insights_name
  log_analytics_workspace_name = var.log_analytics_workspace_name
  tags                         = local.tags
}

module "container_registry" {
  source              = "./modules/container_registry"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  registry_name       = var.container_registry_name
  pull_principal_id   = module.identity.app_identity_principal_id
  push_principal_id   = module.identity.deploy_identity_principal_id
  tags                = local.tags
}

module "storage" {
  source                       = "./modules/storage"
  resource_group_name          = azurerm_resource_group.main.name
  location                     = var.location
  storage_account_name         = var.storage_account_name
  app_identity_principal_id    = module.identity.app_identity_principal_id
  deploy_identity_principal_id = module.identity.deploy_identity_principal_id
  current_user_principal_id    = data.azurerm_client_config.current.object_id
  tags                         = local.tags
}

module "ai_services" {
  source                         = "./modules/ai_services"
  resource_group_name            = azurerm_resource_group.main.name
  location                       = var.location
  subscription_id                = var.subscription_id
  ai_account_name                = var.ai_services_name
  ai_project_name                = var.ai_project_name
  identity_id                    = module.identity.app_identity_id
  identity_principal_id          = module.identity.app_identity_principal_id
  app_insights_id                = module.monitoring.app_insights_id
  app_insights_connection_string = module.monitoring.app_insights_connection_string
  gpt41_capacity                 = var.gpt41_capacity
  gpt41_mini_capacity            = var.gpt41_mini_capacity
}

module "container_apps" {
  source                         = "./modules/container_apps"
  resource_group_name            = azurerm_resource_group.main.name
  location                       = var.location
  container_app_env_name         = var.container_app_env_name
  identity_id                    = module.identity.app_identity_id
  registry_server                = module.container_registry.login_server
  app_insights_connection_string = module.monitoring.app_insights_connection_string
  fabric_sql_server              = var.fabric_sql_server
  fabric_sql_database            = var.fabric_sql_database
  storage_account_name           = module.storage.storage_account_name
  foundry_project_endpoint       = module.ai_services.foundry_project_endpoint
  tags                           = local.tags
}

# ── Wait for Key Vault RBAC to propagate before writing secrets ───────────────
# The current_user_officer role assignment is created in the same apply;
# Azure RBAC can take up to 90s to propagate after assignment creation.
resource "time_sleep" "wait_for_kv_rbac" {
  depends_on      = [module.key_vault]
  create_duration = "90s"
}

# ── Key Vault secrets ──────────────────────────────────────────────────────────

resource "azurerm_key_vault_secret" "app_insights_connection_string" {
  name         = "appinsights-connection-string"
  value        = module.monitoring.app_insights_connection_string
  key_vault_id = module.key_vault.key_vault_id
  depends_on   = [time_sleep.wait_for_kv_rbac]
}

resource "azurerm_key_vault_secret" "foundry_project_endpoint" {
  name         = "foundry-project-endpoint"
  value        = module.ai_services.foundry_project_endpoint
  key_vault_id = module.key_vault.key_vault_id
  depends_on   = [time_sleep.wait_for_kv_rbac]
}

resource "azurerm_key_vault_secret" "fabric_sql_server" {
  name         = "fabric-sql-server"
  value        = var.fabric_sql_server
  key_vault_id = module.key_vault.key_vault_id
  depends_on   = [time_sleep.wait_for_kv_rbac]
}

resource "azurerm_key_vault_secret" "fabric_sql_database" {
  name         = "fabric-sql-database"
  value        = var.fabric_sql_database
  key_vault_id = module.key_vault.key_vault_id
  depends_on   = [time_sleep.wait_for_kv_rbac]
}
