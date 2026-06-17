variable "resource_group_name"  { type = string }
variable "location"              { type = string }
variable "app_identity_name"     { type = string }
variable "deploy_identity_name"  { type = string }
variable "github_org" {
  type    = string
  default = ""
}
variable "github_repository" {
  type    = string
  default = ""
}
variable "tags" { type = map(string) }
