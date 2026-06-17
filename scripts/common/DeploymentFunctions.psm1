# Common deployment functions for LONGHAUL MBR AI Agents

function Write-Title {
    param([string]$Title)
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host $Title -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Warn {
    param([string]$Message)
    Write-Host "WARNING: $Message" -ForegroundColor Yellow
}

function Initialize-AzureContext {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Subscription
    )

    # Suppress Windows broker popup and legacy login experience.
    az config set core.enable_broker_on_windows=false | Out-Null
    az config set core.login_experience_v2=off        | Out-Null

    try {
        $current = az account show --query id -o tsv 2>$null
        if ($current) {
            Write-Success "Already authenticated"
        } else {
            throw "Not authenticated"
        }
    } catch {
        Write-Info "Logging into Azure..."
        az login | Out-Null
    }

    az account set --subscription $Subscription
    if ($LASTEXITCODE -ne 0) { throw "Failed to set subscription: $Subscription" }

    Write-Success "Connected to subscription: $Subscription"
}

function Test-RequiredTools {
    param(
        [string[]]$Tools = @("az", "terraform", "python", "docker")
    )

    $missing = @()
    foreach ($tool in $Tools) {
        if (Get-Command $tool -ErrorAction SilentlyContinue) {
            Write-Success "$tool found"
        } else {
            Write-Host "[X] $tool not found" -ForegroundColor Red
            $missing += $tool
        }
    }

    if ($missing.Count -gt 0) {
        throw "Missing required tools: $($missing -join ', '). Install and retry."
    }
}

function Get-RandomAlphaNumeric {
    param(
        [int]$Length = 8,
        [Parameter(Mandatory=$true)]
        [string]$Seed
    )

    $chars = "abcdefghijklmnopqrstuvwxyz123456789"
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $hash = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Seed))

    $sb = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $Length; $i++) {
        [void]$sb.Append($chars[$hash[$i % $hash.Length] % $chars.Length])
    }
    return $sb.ToString()
}

function Get-ResourceToken {
    <#
    .SYNOPSIS
        Returns a deterministic 8-character token for resource naming.
    .DESCRIPTION
        Seeded with SubscriptionId alone (stable across runs) or with
        SubscriptionId + Timestamp when -Timestamp is supplied (unique per install).
        New-TerraformVarsFile passes a timestamp only on a genuinely fresh install,
        so re-runs reuse the token already written to terraform.tfvars.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$SubscriptionId,

        [string]$Timestamp = "",

        [int]$Length = 8
    )

    $seed = if ($Timestamp) { "$SubscriptionId$Timestamp" } else { $SubscriptionId }
    return Get-RandomAlphaNumeric -Length $Length -Seed $seed
}

function New-TerraformVarsFile {
    <#
    .SYNOPSIS
        Generates infra/terraform.tfvars from terraform.tfvars.tpl on first run.
    .DESCRIPTION
        Substitutes ${SubscriptionId}, ${TenantId}, ${Location}, ${Environment},
        ${ProjectName}, ${ResourceToken}, ${FabricWorkspaceId}, ${FabricSqlServer},
        ${GitHubOrg}, ${GitHubRepository} placeholders into the template.

        Reuses the existing resource_token if terraform.tfvars already exists so
        re-runs always target the same Azure resources (and never collide with
        soft-deleted names).
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$SubscriptionId,

        [Parameter(Mandatory=$true)]
        [string]$TenantId,

        [Parameter(Mandatory=$true)]
        [string]$Location,

        [Parameter(Mandatory=$true)]
        [string]$Environment,

        [string]$ProjectName = "mbrtrucking",

        [string]$FabricWorkspaceId = "",

        [string]$FabricSqlServer = "",

        [string]$GitHubOrg = "",

        [string]$GitHubRepository = "",

        [string]$InfraDir = "infra"
    )

    Write-Title "Generating terraform.tfvars"

    $infraAbs = (Resolve-Path -Path $InfraDir -ErrorAction Stop).Path
    $tfvars   = Join-Path $infraAbs "terraform.tfvars"
    $tpl      = Join-Path $infraAbs "terraform.tfvars.tpl"

    if (-not (Test-Path $tpl)) {
        throw "Template not found: $tpl"
    }

    # Reuse sticky values already in terraform.tfvars when present.
    $resourceToken = $null
    if (Test-Path $tfvars) {
        $existing = Get-Content $tfvars -Raw
        if ($existing -match 'resource_token\s*=\s*"([a-z0-9]+)"') {
            $resourceToken = $Matches[1]
            Write-Info "Reusing existing resource token: $resourceToken"
        }
        # Preserve fabric_workspace_id if the caller did not supply one.
        if (-not $FabricWorkspaceId -and $existing -match 'fabric_workspace_id\s*=\s*"([^"]+)"') {
            $FabricWorkspaceId = $Matches[1]
            Write-Info "Reusing existing fabric_workspace_id: $FabricWorkspaceId"
        }
        # Preserve fabric_sql_server if the caller did not supply one.
        if (-not $FabricSqlServer -and $existing -match 'fabric_sql_server\s*=\s*"([^"]+)"') {
            $FabricSqlServer = $Matches[1]
            Write-Info "Reusing existing fabric_sql_server: $FabricSqlServer"
        }
    }
    if (-not $resourceToken) {
        $timestamp     = Get-Date -Format 'yyyyMMddHHmmss'
        $resourceToken = Get-ResourceToken -SubscriptionId $SubscriptionId -Timestamp $timestamp
        Write-Info "Generated new resource token: $resourceToken"
    }

    $content = Get-Content -Path $tpl -Raw
    $content = $content -replace '\$\{SubscriptionId\}',    $SubscriptionId
    $content = $content -replace '\$\{TenantId\}',          $TenantId
    $content = $content -replace '\$\{Location\}',          $Location
    $content = $content -replace '\$\{Environment\}',       $Environment
    $content = $content -replace '\$\{ProjectName\}',       $ProjectName
    $content = $content -replace '\$\{ResourceToken\}',     $resourceToken
    $content = $content -replace '\$\{FabricWorkspaceId\}', $FabricWorkspaceId
    $content = $content -replace '\$\{FabricSqlServer\}',   $FabricSqlServer
    $content = $content -replace '\$\{GitHubOrg\}',         $GitHubOrg
    $content = $content -replace '\$\{GitHubRepository\}',  $GitHubRepository

    Set-Content -Path $tfvars -Value $content -Encoding UTF8 -Force
    Write-Success "terraform.tfvars written: $tfvars"
    Write-Info    "Resource token: $resourceToken"
}

Export-ModuleMember -Function @(
    'Write-Title',
    'Write-Success',
    'Write-Info',
    'Write-Warn',
    'Initialize-AzureContext',
    'Test-RequiredTools',
    'Get-RandomAlphaNumeric',
    'Get-ResourceToken',
    'New-TerraformVarsFile'
)
