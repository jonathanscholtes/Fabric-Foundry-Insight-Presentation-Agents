output "ai_account_id" {
  description = "Resource ID of the AI Services account"
  value       = azapi_resource.ai_account.id
}

output "ai_account_name" {
  description = "Name of the AI Services account"
  value       = var.ai_account_name
}

output "ai_project_id" {
  description = "Resource ID of the AI Foundry project"
  value       = azapi_resource.ai_project.id
}

output "ai_project_name" {
  description = "Name of the AI Foundry project"
  value       = var.ai_project_name
}

output "foundry_project_endpoint" {
  description = "Endpoint URL for the Foundry project (azure-ai-projects SDK FOUNDRY_PROJECT_ENDPOINT)"
  value       = "https://${var.ai_account_name}.services.ai.azure.com/api/projects/${var.ai_project_name}"
}

output "model_deployment" {
  description = "Name of the full-tier model deployment (gpt-4.1)"
  value       = azapi_resource.gpt41_deployment.name
}

output "mini_model_deployment" {
  description = "Name of the mini-tier model deployment (gpt-4.1-mini)"
  value       = azapi_resource.gpt41_mini_deployment.name
}
