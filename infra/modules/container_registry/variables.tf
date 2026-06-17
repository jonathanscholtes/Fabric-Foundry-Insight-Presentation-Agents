variable "resource_group_name" { type = string }
variable "location"            { type = string }
variable "registry_name"       { type = string }
variable "tags"                { type = map(string) }
variable "pull_principal_id"   { type = string }
variable "push_principal_id"   { type = string }
