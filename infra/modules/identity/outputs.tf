output "app_identity_id"           { value = azurerm_user_assigned_identity.app.id }
output "app_identity_principal_id" { value = azurerm_user_assigned_identity.app.principal_id }
output "app_identity_client_id"    { value = azurerm_user_assigned_identity.app.client_id }

output "deploy_identity_id"           { value = azurerm_user_assigned_identity.deploy.id }
output "deploy_identity_principal_id" { value = azurerm_user_assigned_identity.deploy.principal_id }
output "deploy_identity_client_id"    { value = azurerm_user_assigned_identity.deploy.client_id }
