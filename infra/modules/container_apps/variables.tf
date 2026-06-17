variable "resource_group_name"             { type = string }
variable "location"                         { type = string }
variable "container_app_env_name"           { type = string }
variable "tags"                             { type = map(string) }
variable "identity_id"                      { type = string }
variable "registry_server"                  { type = string }
variable "app_insights_connection_string" {
  type      = string
  sensitive = true
}
variable "fabric_sql_server"        { type = string }
variable "fabric_sql_database"      { type = string }
variable "storage_account_name"     { type = string }
variable "foundry_project_endpoint" { type = string }
