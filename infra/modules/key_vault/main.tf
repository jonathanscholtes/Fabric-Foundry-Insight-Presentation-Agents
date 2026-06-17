resource "azurerm_key_vault" "main" {
  name                       = var.key_vault_name
  resource_group_name        = var.resource_group_name
  location                   = var.location
  tenant_id                  = var.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  rbac_authorization_enabled = true
  tags                       = var.tags
}

# ── RBAC: Key Vault Secrets Officer for caller and deploy identity ────────────
resource "azurerm_role_assignment" "current_user_officer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.principal_ids["current_user"]
}

resource "azurerm_role_assignment" "deploy_officer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.principal_ids["deploy_identity"]
}

# ── RBAC: Key Vault Secrets User for app runtime identity ─────────────────────
resource "azurerm_role_assignment" "app_reader" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.principal_ids["app_identity"]
}
