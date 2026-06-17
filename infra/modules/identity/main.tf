# ── App managed identity — used by Container Apps at runtime ──────────────────
resource "azurerm_user_assigned_identity" "app" {
  name                = var.app_identity_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

# ── Deploy managed identity — used by GitHub Actions CI/CD ───────────────────
resource "azurerm_user_assigned_identity" "deploy" {
  name                = var.deploy_identity_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

# ── GitHub OIDC federated credential (optional) ───────────────────────────────
resource "azurerm_federated_identity_credential" "github_main" {
  count               = var.github_org != "" ? 1 : 0
  name                = "github-main"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.deploy.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  subject             = "repo:${var.github_org}/${var.github_repository}:ref:refs/heads/main"
}

resource "azurerm_federated_identity_credential" "github_pr" {
  count               = var.github_org != "" ? 1 : 0
  name                = "github-pr"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.deploy.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  subject             = "repo:${var.github_org}/${var.github_repository}:pull_request"
}

# ── Contributor on the resource group for the deploy identity ─────────────────
resource "azurerm_role_assignment" "deploy_contributor" {
  scope                = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${var.resource_group_name}"
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.deploy.principal_id
}

data "azurerm_subscription" "current" {}
