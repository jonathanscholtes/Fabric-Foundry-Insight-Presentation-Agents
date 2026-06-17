variable "ai_account_name" {
  description = "Name of the AI Services account"
  type        = string
}

variable "ai_project_name" {
  description = "Name of the AI Foundry project"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group to deploy into"
  type        = string
}

variable "subscription_id" {
  description = "Azure subscription ID (used to build role definition IDs)"
  type        = string
}

variable "identity_id" {
  description = "Resource ID of the user-assigned managed identity attached to the account"
  type        = string
}

variable "identity_principal_id" {
  description = "Principal ID of the runtime managed identity (granted 5 RBAC roles)"
  type        = string
}

variable "gpt41_capacity" {
  description = "TPM capacity for the GPT-4.1 deployment (thousands)"
  type        = number
  default     = 150
}

variable "gpt41_mini_capacity" {
  description = "TPM capacity for the GPT-4.1-mini deployment (thousands)"
  type        = number
  default     = 50
}

variable "app_insights_id" {
  description = "Resource ID of the Application Insights instance registered as a project connection"
  type        = string
}

variable "app_insights_connection_string" {
  description = "App Insights connection string stored as the connection credential"
  type        = string
  sensitive   = true
}
