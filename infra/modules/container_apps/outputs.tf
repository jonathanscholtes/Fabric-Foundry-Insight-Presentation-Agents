output "mbr_api_fqdn" {
  description = "Public FQDN of the mbr-api Container App"
  value       = azurerm_container_app.mbr_api.ingress[0].fqdn
}

output "mbr_tools_api_fqdn" {
  description = "Internal FQDN of the mbr-tools-mcp Container App (ACA internal ingress — agents only)"
  value       = azurerm_container_app.mbr_tools_api.ingress[0].fqdn
}

output "longhaul_ui_fqdn" {
  description = "Public FQDN of the mbr-ui Container App"
  value       = azurerm_container_app.longhaul_ui.ingress[0].fqdn
}

output "container_app_environment_id" {
  description = "Resource ID of the Container App Environment"
  value       = azurerm_container_app_environment.main.id
}
