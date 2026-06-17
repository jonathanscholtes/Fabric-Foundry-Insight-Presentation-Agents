terraform {
  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
  }
}

resource "azapi_resource" "ai_account" {
  type      = "Microsoft.CognitiveServices/accounts@2025-09-01"
  name      = var.ai_account_name
  location  = var.location
  parent_id = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}"

  identity {
    type         = "UserAssigned"
    identity_ids = [var.identity_id]
  }

  body = {
    kind = "AIServices"
    sku  = { name = "S0" }
    properties = {
      customSubDomainName    = var.ai_account_name
      allowProjectManagement = true
      publicNetworkAccess    = "Enabled"
      disableLocalAuth       = false
      networkAcls = {
        defaultAction       = "Allow"
        virtualNetworkRules = []
        ipRules             = []
      }
    }
  }
}

resource "azapi_resource" "gpt41_deployment" {
  type      = "Microsoft.CognitiveServices/accounts/deployments@2025-09-01"
  name      = "gpt-4.1"
  parent_id = azapi_resource.ai_account.id

  body = {
    sku = {
      name     = "Standard"
      capacity = var.gpt41_capacity
    }
    properties = {
      model = {
        format  = "OpenAI"
        name    = "gpt-4.1"
        version = "2025-04-14"
      }
      versionUpgradeOption = "OnceNewDefaultVersionAvailable"
    }
  }

  depends_on = [azapi_resource.ai_account]
}

resource "azapi_resource" "gpt41_mini_deployment" {
  type      = "Microsoft.CognitiveServices/accounts/deployments@2025-09-01"
  name      = "gpt-4.1-mini"
  parent_id = azapi_resource.ai_account.id

  body = {
    sku = {
      name     = "Standard"
      capacity = var.gpt41_mini_capacity
    }
    properties = {
      model = {
        format  = "OpenAI"
        name    = "gpt-4.1-mini"
        version = "2025-04-14"
      }
      versionUpgradeOption = "OnceNewDefaultVersionAvailable"
    }
  }

  depends_on = [azapi_resource.gpt41_deployment]
}

resource "azapi_resource" "ai_project" {
  type      = "Microsoft.CognitiveServices/accounts/projects@2025-09-01"
  name      = var.ai_project_name
  location  = var.location
  parent_id = azapi_resource.ai_account.id

  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {}
  }

  depends_on = [azapi_resource.gpt41_deployment]
}

resource "azapi_resource" "appinsights_connection" {
  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-09-01"
  name      = "mbr-appinsights"
  parent_id = azapi_resource.ai_project.id

  body = {
    properties = {
      category          = "AppInsights"
      authType          = "ApiKey"
      target            = var.app_insights_id
      isSharedToAll     = true
      useWorkspaceManagedIdentity = false
      credentials = {
        key = var.app_insights_connection_string
      }
      metadata = {
        ApiType    = "Azure"
        ResourceId = var.app_insights_id
      }
      peRequirement = "NotRequired"
      peStatus      = "NotApplicable"
    }
  }

  lifecycle {
    ignore_changes = [body]
  }

  depends_on = [azapi_resource.ai_project]
}

# ── Runtime identity RBAC (5 roles for agent invoke/read) ─────────────────────

resource "azurerm_role_assignment" "openai_user" {
  scope                = azapi_resource.ai_account.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = var.identity_principal_id
}

resource "azurerm_role_assignment" "ai_developer" {
  scope              = azapi_resource.ai_account.id
  role_definition_id = "/subscriptions/${var.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/a001fd3d-188f-4b5d-821b-7da978bf7442"
  principal_id       = var.identity_principal_id
}

resource "azurerm_role_assignment" "cognitive_services_user" {
  scope                = azapi_resource.ai_account.id
  role_definition_name = "Cognitive Services User"
  principal_id         = var.identity_principal_id
}

resource "azurerm_role_assignment" "ai_user" {
  scope              = azapi_resource.ai_account.id
  role_definition_id = "/subscriptions/${var.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/53ca6127-db72-4b80-b1b0-d745d6d5456d"
  principal_id       = var.identity_principal_id
}

resource "azurerm_role_assignment" "ai_project_manager" {
  scope              = azapi_resource.ai_account.id
  role_definition_id = "/subscriptions/${var.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/eadc314b-1a2d-4efa-be10-5d325db5065e"
  principal_id       = var.identity_principal_id
}
