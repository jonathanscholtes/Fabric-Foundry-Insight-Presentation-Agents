resource "azurerm_storage_account" "main" {
  name                            = var.storage_account_name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
  tags                            = var.tags
}

# ── Blob containers (all private) ─────────────────────────────────────────────

resource "azurerm_storage_container" "templates" {
  name                  = "templates"
  storage_account_id    = azurerm_storage_account.main.id
  container_access_type = "private"
}

resource "azurerm_storage_container" "thumbnails" {
  name                  = "thumbnails"
  storage_account_id    = azurerm_storage_account.main.id
  container_access_type = "private"
}

resource "azurerm_storage_container" "decks" {
  name                  = "decks"
  storage_account_id    = azurerm_storage_account.main.id
  container_access_type = "private"
}

resource "azurerm_storage_container" "exports" {
  name                  = "exports"
  storage_account_id    = azurerm_storage_account.main.id
  container_access_type = "private"
}

resource "azurerm_storage_container" "conversations" {
  name                  = "conversations"
  storage_account_id    = azurerm_storage_account.main.id
  container_access_type = "private"
}

resource "azurerm_storage_container" "decks_metadata" {
  name                  = "decks-metadata"
  storage_account_id    = azurerm_storage_account.main.id
  container_access_type = "private"
}

# ── RBAC: Storage Blob Data Contributor for app runtime identity ──────────────
resource "azurerm_role_assignment" "app_blob_contributor" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.app_identity_principal_id
}

# ── RBAC: Storage Blob Data Contributor for deploy identity (uploads blobs) ──
resource "azurerm_role_assignment" "deploy_blob_contributor" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.deploy_identity_principal_id
}

# ── RBAC: Storage Blob Data Contributor for current caller (az login user) ───
resource "azurerm_role_assignment" "current_user_blob_contributor" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.current_user_principal_id
}
