variable "resource_group_name"          { type = string }
variable "location"                      { type = string }
variable "storage_account_name"          { type = string }
variable "tags"                          { type = map(string) }
variable "app_identity_principal_id"     { type = string }
variable "deploy_identity_principal_id"  { type = string }
