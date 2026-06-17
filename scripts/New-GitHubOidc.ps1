<#
.SYNOPSIS
    Creates an Entra ID app registration + federated credential for GitHub Actions OIDC.

.DESCRIPTION
    Registers an Entra ID application and service principal, assigns Contributor
    on the subscription, and adds a federated identity credential so GitHub Actions
    can authenticate without storing secrets.

    Run once per environment (dev / staging / prod).

.PARAMETER SubscriptionId
    Azure subscription ID.

.PARAMETER TenantId
    Azure tenant ID.

.PARAMETER GitHubOrg
    GitHub organisation or user name.

.PARAMETER GitHubRepo
    GitHub repository name.

.PARAMETER Environment
    GitHub Actions environment name (dev | staging | prod).  Used to scope the
    federated credential.  Also accepted: 'main' to trust the main branch.

.EXAMPLE
    .\scripts\New-GitHubOidc.ps1 `
        -SubscriptionId 00000000-0000-0000-0000-000000000000 `
        -TenantId       00000000-0000-0000-0000-000000000000 `
        -GitHubOrg      myorg `
        -GitHubRepo     Azure-Fabric-MBR-AI-Agents `
        -Environment    dev
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $SubscriptionId,
    [Parameter(Mandatory)] [string] $TenantId,
    [Parameter(Mandatory)] [string] $GitHubOrg,
    [Parameter(Mandatory)] [string] $GitHubRepo,
    [string] $Environment = 'dev'
)

$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot\common\DeploymentFunctions.psm1" -Force
Initialize-AzureContext -SubscriptionId $SubscriptionId -TenantId $TenantId

$AppName = "longhaul-github-actions-$Environment"

# Create or retrieve existing app registration
$ExistingApp = az ad app list --display-name $AppName --query "[0].appId" -o tsv 2>$null
if ($ExistingApp) {
    Write-Info "App registration already exists: $ExistingApp"
    $AppId = $ExistingApp
} else {
    Write-Info "Creating app registration: $AppName"
    $AppId = az ad app create --display-name $AppName --query appId -o tsv
    Write-Success "Created app: $AppId"
}

# Ensure service principal
$SpId = az ad sp show --id $AppId --query id -o tsv 2>$null
if (-not $SpId) {
    Write-Info "Creating service principal…"
    $SpId = az ad sp create --id $AppId --query id -o tsv
}

# Assign Contributor at subscription scope
$ExistingRole = az role assignment list `
    --assignee $AppId `
    --role Contributor `
    --scope "/subscriptions/$SubscriptionId" `
    --query "[0].id" -o tsv 2>$null

if ($ExistingRole) {
    Write-Info "Contributor role already assigned."
} else {
    Write-Info "Assigning Contributor role…"
    az role assignment create `
        --assignee $AppId `
        --role Contributor `
        --scope "/subscriptions/$SubscriptionId" | Out-Null
    Write-Success "Role assigned."
}

# Federated credential  -  trust GitHub Actions environment
$FedName    = "github-$GitHubOrg-$GitHubRepo-$Environment"
$FedSubject = "repo:${GitHubOrg}/${GitHubRepo}:environment:$Environment"

$ExistingFed = az ad app federated-credential list --id $AppId `
    --query "[?name=='$FedName'].id" -o tsv 2>$null

if ($ExistingFed) {
    Write-Info "Federated credential already exists."
} else {
    Write-Info "Creating federated credential ($FedSubject)…"
    az ad app federated-credential create --id $AppId --parameters "{
        `"name`": `"$FedName`",
        `"issuer`": `"https://token.actions.githubusercontent.com`",
        `"subject`": `"$FedSubject`",
        `"description`": `"GitHub Actions OIDC for $Environment`",
        `"audiences`": [`"api://AzureADTokenExchange`"]
    }" | Out-Null
    Write-Success "Federated credential created."
}

# Output values to set as GitHub Actions secrets / variables
Write-Title "GitHub Actions Configuration"
Write-Host ""
Write-Host "Add these as GitHub repository variables / secrets:" -ForegroundColor Cyan
Write-Host "  AZURE_CLIENT_ID:       $AppId"        -ForegroundColor White
Write-Host "  AZURE_TENANT_ID:       $TenantId"     -ForegroundColor White
Write-Host "  AZURE_SUBSCRIPTION_ID: $SubscriptionId" -ForegroundColor White
Write-Host ""
