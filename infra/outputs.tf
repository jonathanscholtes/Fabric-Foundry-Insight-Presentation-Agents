output "resource_group_name" {
  description = "Name of the main resource group"
  value       = azurerm_resource_group.main.name
}

output "mbr_api_url" {
  description = "Public URL of the mbr-api Container App"
  value       = "https://${module.container_apps.mbr_api_fqdn}"
}

output "longhaul_ui_url" {
  description = "Public URL of the mbr-ui Container App"
  value       = "https://${module.container_apps.longhaul_ui_fqdn}"
}

output "mcp_tools_api_fqdn" {
  description = "Internal FQDN of the mbr-tools-mcp Container App (ACA internal ingress — agents only)"
  value       = module.container_apps.mbr_tools_api_fqdn
}

output "storage_account_name" {
  description = "Storage account name (used by Deploy-FabricLakehouse.ps1 for template upload + thumbnail pre-render)"
  value       = module.storage.storage_account_name
}

output "foundry_project_endpoint" {
  description = "Foundry project endpoint URL (set as FOUNDRY_PROJECT_ENDPOINT env var for agents/deploy.py)"
  value       = module.ai_services.foundry_project_endpoint
}

output "app_identity_client_id" {
  description = "Client ID of the app managed identity (for Fabric workspace Managed Identity grant)"
  value       = module.identity.app_identity_client_id
}

output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = module.key_vault.key_vault_name
}

output "container_registry_login_server" {
  description = "ACR login server for pushing/pulling images"
  value       = module.container_registry.login_server
}

output "ai_account_id" {
  description = "Resource ID of the AI Services account"
  value       = module.ai_services.ai_account_id
}

output "model_deployment" {
  description = "Name of the full-tier model deployment (gpt-4.1)"
  value       = module.ai_services.model_deployment
}

output "mini_model_deployment" {
  description = "Name of the mini-tier model deployment (gpt-4.1-mini)"
  value       = module.ai_services.mini_model_deployment
}

output "key_vault_uri" {
  description = "URI of the Key Vault (used as --key-vault-uri for MCP URL resolution)"
  value       = module.key_vault.vault_uri
}

output "fabric_workspace_id" {
  description = "Fabric workspace GUID (pass-through; used by setup scripts)"
  value       = var.fabric_workspace_id
}
