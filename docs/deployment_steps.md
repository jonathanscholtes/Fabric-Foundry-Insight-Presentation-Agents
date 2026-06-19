# Deployment Guide

> Back to [README](../README.md)

End-to-end deployment guide for the Conversational Agents for Operational Data project: natural-language insight discovery and presentation generation using Microsoft Fabric, Microsoft Foundry, and Azure Container Apps.

---

## Contents

- [Prerequisites](#prerequisites)
- [Step 1 — Create the Fabric Workspace and Lakehouse](#step-1--create-the-fabric-workspace-and-lakehouse)
- [Step 2 — Clone the Repository](#step-2--clone-the-repository)
- [Step 3 — Login to Azure](#step-3--login-to-azure)
- [Step 4 — Deploy Everything](#step-4--deploy-everything)
- [Step 5 — Configure the Fabric Data Agent (Manual — Portal)](#step-5--configure-the-fabric-data-agent-manual--portal)
- [Step 6 — Verify the Deployment](#step-6--verify-the-deployment)
- [GitHub Actions (Optional)](#github-actions-optional)
- [Teardown](#teardown)

---

## Prerequisites

### Tools

| Tool | Version | Install |
|---|---|---|
| Azure CLI | Latest | [Install guide](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) |
| Terraform | ≥ 1.9 | **Windows:** `winget install HashiCorp.Terraform` · **macOS:** `brew install hashicorp/tap/terraform` · **Linux:** [Install guide](https://developer.hashicorp.com/terraform/install) |
| PowerShell | 7+ | **Windows:** `winget install Microsoft.PowerShell` · **Linux/macOS:** [Install guide](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell) |
| Python | 3.12+ | Required for agent deployment and Lakehouse seed scripts |
| Git | Latest | [Install guide](https://git-scm.com/downloads) |

> Docker is **not** required — container images are built remotely in Azure Container Registry via `az acr build`.

### Azure Access Requirements

| Requirement | Reason |
|---|---|
| **Owner** or **Contributor** on the target subscription | Terraform creates all resource groups and resources |
| **User Access Administrator** on the subscription | Terraform assigns RBAC roles to the managed identity |

### Microsoft Fabric Requirement

A **Microsoft Fabric workspace** must exist before running `deploy.ps1`. The workspace ID is passed as a parameter — the deployment scripts create the Lakehouse and Data Agent inside it.

A Fabric administrator must also enable **"Allow service principals and managed identities to use Fabric APIs"** under Tenant settings before managed identity authentication will work. See [Step 5 — Fabric Admin Prerequisite](#fabric-admin-prerequisite).

---

## Step 1 — Create the Fabric Workspace and Lakehouse

Fabric resources cannot be created via Terraform and require a one-time manual setup.

### 1a. Create the Workspace

1. Go to [app.fabric.microsoft.com](https://app.fabric.microsoft.com)
2. Click **+ New workspace** and name it — e.g. `longhaul-mbr`
3. Note the **Workspace ID** from the URL:
   `https://app.fabric.microsoft.com/groups/<workspace-id>/...`

### 1b. Create the Lakehouse

1. Inside the workspace, click **New item → Lakehouse**
2. Name it: `lh_mbr_trucking`
3. Once created, open the Lakehouse and note the **Lakehouse ID** from the URL
4. Navigate to **Lakehouse settings → SQL analytics endpoint**
5. Copy the **Server** hostname — it looks like:
   `<workspace-id>.<lakehouse-id>.datawarehouse.fabric.microsoft.com`

> The server hostname is passed to `deploy.ps1` via the `-FabricSqlServer` parameter if you need to supply it explicitly. The `Deploy-FabricWorkspace.ps1` script also attempts to discover it automatically after the Lakehouse is created.

---

## Step 2 — Clone the Repository

```bash
git clone https://github.com/jonathanscholtes/Azure-Fabric-MBR-AI-Agents.git
cd Azure-Fabric-MBR-AI-Agents
```

---

## Step 3 — Login to Azure

```powershell
az login
az account set --subscription "YOUR-SUBSCRIPTION-NAME-OR-ID"
```

---

## Step 4 — Deploy Everything

Run the deployment orchestrator. Pass your subscription and the Fabric Workspace ID from Step 1:

```powershell
.\deploy.ps1 `
    -Subscription      "YOUR-SUBSCRIPTION-NAME-OR-ID" `
    -FabricWorkspaceId "<workspace-guid>"
```

The deployment runs six phases automatically:

| Phase | Script | What it does |
|---|---|---|
| 0 — Bootstrap | *(inline)* | Creates Terraform remote state backend (Storage Account + container) |
| 1 — Infrastructure | `Deploy-Infrastructure.ps1` | Provisions all Azure resources via Terraform |
| 2 — Containers | `Deploy-Containers.ps1` | Builds and pushes `mbr-api`, `mbr-tools-mcp`, and `mbr-ui` images to ACR |
| 3 — Fabric Lakehouse | `Deploy-FabricLakehouse.ps1` | Creates tables, seeds 13 months of KPI data, uploads `mbr_template.pptx` |
| 3b — Fabric Data Agent | `Deploy-FabricDataAgent.ps1` | Creates `da_mbr_trucking`, assigns managed identity Contributor access to the workspace |
| 4 — Foundry Agents | `Deploy-FoundryAgents.ps1` | Deploys `conversational-agent` and `mbr-presentation-agent`, injects agent IDs as Container App environment variables |

**Optional parameters:**

| Parameter | Default | Description |
|---|---|---|
| `-Location` | `eastus` | Azure region for all resources |
| `-Environment` | `dev` | Environment tag applied to resources |
| `-SkipBootstrap` | off | Skip Phase 0 — use when the state backend already exists (subsequent deploys) |
| `-SetupGitHub` | off | Configure GitHub Actions OIDC secrets automatically (requires `gh` CLI) |
| `-Destroy` | off | Tear down all deployed resources |

**Subsequent deploys** (infrastructure already exists):

```powershell
.\deploy.ps1 -Subscription "<subscription>" -FabricWorkspaceId "<guid>" -SkipBootstrap
```

> **Estimated time:** 20–30 minutes.

**Resources created:**

| Resource | Purpose |
|---|---|
| Microsoft Foundry account + project | Hosts `conversational-agent` and `mbr-presentation-agent`; GPT-4.1 and GPT-4.1-mini deployments |
| Container Apps environment | Hosts `mbr-api`, `mbr-tools-mcp`, and `mbr-ui` |
| Azure Container Registry | Stores container images |
| Azure Key Vault | Stores runtime secrets (MCP server URL, Fabric Data Agent URL) |
| User-Assigned Managed Identity | Runtime identity for Container Apps — no stored credentials |
| Azure Blob Storage | Stores PowerPoint templates, generated decks, thumbnails, and conversation history |
| Log Analytics + Application Insights | Monitoring and diagnostics |

---

## Step 5 — Configure the Fabric Data Agent (Manual — Portal)

The `Deploy-FabricDataAgent.ps1` script creates the `da_mbr_trucking` agent via the Fabric REST API. However, the Fabric API does not reliably apply data sources or agent instructions — these two steps must be completed in the portal.

### Fabric Admin Prerequisite

Before managed identity authentication can work, a Fabric administrator must enable the following setting **once per tenant**:

1. Go to [app.fabric.microsoft.com/admin](https://app.fabric.microsoft.com/admin)
2. Navigate to **Tenant settings → Developer settings**
3. Enable **"Allow service principals and managed identities to use Fabric APIs"**
4. Save

Without this setting, the `Deploy-FabricDataAgent.ps1` RBAC call returns 403 and the deploy script prints a warning. Re-run the relevant phase after enabling it, or add the identity manually (see below).

### 5a. Add the Lakehouse as a Data Source

1. Go to [app.fabric.microsoft.com](https://app.fabric.microsoft.com) and open your workspace
2. Open **`da_mbr_trucking`**
3. Click **Add data** → **Lakehouse**
4. Select **`lh_mbr_trucking`** from the workspace list
5. Confirm — the Lakehouse should appear in the **Data** tab
6. Open the `lh_mbr_trucking` data source and fill in the two fields below

**Data source description:**
```
Contains 13 months of monthly operational KPI data (May 2024 – May 2025) for LONGHAUL's
long-haul trucking fleet. Use this source to answer questions about revenue, mileage, costs,
on-time delivery, and fleet efficiency across 5 US regions and 4 vehicle types.
```

**Data source instructions:**
```
## Join logic
Always join fact tables to dimension tables:
- JOIN dim_month ON month_id
- JOIN dim_region ON region_id
- JOIN dim_vehicle_type ON vehicle_type_id (fact_vehicle_kpis only)

## Value formats
- period_label: 3-letter month abbreviation + space + 4-digit year — e.g. 'Mar 2025', 'Feb 2025', 'Nov 2024'. Never use the full month name ('March 2025' returns no data).
- region_name: 'North', 'South', 'East', 'West', 'Central'
- For all-region queries, omit the region filter

## Query guidelines
- Use SUM() for all fact columns
- Always GROUP BY when aggregating across multiple dimensions
- For MoM comparisons, prior month = sort_order - 1
- Express financial values in dollars. Express miles as whole numbers.
```

### 5b. Add Agent Instructions

1. Click **Agent instructions** in the top toolbar
2. Paste the following system prompt:

```
You are da_mbr_trucking, the data agent for LONGHAUL, a long-haul trucking company.
You have access to 13 months of operational KPI data (May 2024 to May 2025) across
5 regions (North, South, East, West, Central) and 4 vehicle types
(Flatbed, Refrigerated, Dry Van, Tanker).

## Data sources
Use fact_monthly_kpis and fact_vehicle_kpis as the primary fact tables.
Always join to dimension tables to return human-readable labels:
- JOIN dim_month ON month_id
- JOIN dim_region ON region_id
- JOIN dim_vehicle_type ON vehicle_type_id (fact_vehicle_kpis only)

## Value formats
- period_label format: 'May 2025' (full month name, space, 4-digit year)
- region_name values: 'North', 'South', 'East', 'West', 'Central'
- For all-region queries, omit the region filter

## Query guidelines
- Use SUM() for all fact columns
- Always GROUP BY when aggregating across multiple dimensions
- For MoM comparisons, use sort_order: prior month is sort_order - 1
- Express financial values in dollars. Express miles as whole numbers.
- Filter for the most recent record when no explicit period is given.
```

### 5c. Add Example Queries

Example queries feed the vector similarity search that runs on every user question — the agent retrieves the top 3 most relevant examples before generating SQL. Without them the agent cold-generates SQL every time, adding 10–20 seconds of latency. Add the following under **Example queries** in the data source configuration.

**Total revenue for a period (all regions)**
```sql
SELECT SUM(f.total_revenue) AS total_revenue
FROM fact_monthly_kpis f
JOIN dim_month m ON f.month_id = m.month_id
WHERE m.period_label = 'Mar 2025'
```

**All KPIs for a period and region**
```sql
SELECT
    SUM(f.total_revenue)      AS total_revenue,
    SUM(f.total_miles)        AS total_miles,
    SUM(f.empty_miles)        AS empty_miles,
    SUM(f.total_cost)         AS total_cost,
    SUM(f.fuel_cost)          AS fuel_cost,
    SUM(f.driver_cost)        AS driver_cost,
    SUM(f.maintenance_cost)   AS maintenance_cost,
    SUM(f.on_time_deliveries) AS on_time_deliveries,
    SUM(f.total_deliveries)   AS total_deliveries
FROM fact_monthly_kpis f
JOIN dim_month  m ON f.month_id  = m.month_id
JOIN dim_region r ON f.region_id = r.region_id
WHERE m.period_label = 'Mar 2025'
  AND r.region_name = 'North'
```

**Trailing 6 months revenue trend for a region**
```sql
SELECT m.period_label, m.sort_order, SUM(f.total_revenue) AS revenue
FROM fact_monthly_kpis f
JOIN dim_month  m ON f.month_id  = m.month_id
JOIN dim_region r ON f.region_id = r.region_id
WHERE m.sort_order BETWEEN 7 AND 12
  AND r.region_name = 'North'
GROUP BY m.period_label, m.sort_order
ORDER BY m.sort_order ASC
```

**MoM KPI comparison (current and prior period)**
```sql
SELECT m.period_label, m.sort_order,
    SUM(f.total_revenue)    AS total_revenue,
    SUM(f.total_miles)      AS total_miles,
    SUM(f.total_cost)       AS total_cost,
    SUM(f.fuel_cost)        AS fuel_cost,
    SUM(f.driver_cost)      AS driver_cost
FROM fact_monthly_kpis f
JOIN dim_month  m ON f.month_id  = m.month_id
JOIN dim_region r ON f.region_id = r.region_id
WHERE m.sort_order IN (12, 13)
  AND r.region_name = 'North'
GROUP BY m.period_label, m.sort_order
ORDER BY m.sort_order ASC
```

**On-time delivery % by vehicle type for a period and region**
```sql
SELECT
    vt.vehicle_type_name,
    SUM(fv.on_time_deliveries) * 1.0 / SUM(fv.total_deliveries) * 100 AS on_time_pct
FROM fact_vehicle_kpis fv
JOIN dim_month        m  ON fv.month_id        = m.month_id
JOIN dim_region       r  ON fv.region_id       = r.region_id
JOIN dim_vehicle_type vt ON fv.vehicle_type_id = vt.vehicle_type_id
WHERE m.period_label = 'Mar 2025'
  AND r.region_name = 'North'
  AND fv.total_deliveries > 0
GROUP BY vt.vehicle_type_name
ORDER BY on_time_pct DESC
```

**Cost per mile and cost breakdown for a period and region**
```sql
SELECT
    SUM(f.total_cost) * 1.0 / SUM(f.total_miles) AS cost_per_mile,
    SUM(f.fuel_cost)        AS fuel_cost,
    SUM(f.driver_cost)      AS driver_cost,
    SUM(f.maintenance_cost) AS maintenance_cost
FROM fact_monthly_kpis f
JOIN dim_month  m ON f.month_id  = m.month_id
JOIN dim_region r ON f.region_id = r.region_id
WHERE m.period_label = 'Mar 2025'
  AND r.region_name = 'North'
```

**Driver metrics for a period and region**
```sql
SELECT
    SUM(f.driver_count)      AS driver_count,
    SUM(f.drivers_departed)  AS drivers_departed,
    SUM(f.incidents)         AS incidents
FROM fact_monthly_kpis f
JOIN dim_month  m ON f.month_id  = m.month_id
JOIN dim_region r ON f.region_id = r.region_id
WHERE m.period_label = 'Mar 2025'
  AND r.region_name = 'North'
```

### 5d. Publish

Click **Publish** in the top toolbar. The agent is not active until published.

### Managed Identity Access — Manual Fallback

If the automated RBAC assignment failed (403 from the deploy script), add the managed identity to the workspace manually:

1. In the workspace, go to **Settings → Manage access**
2. Click **Add people or groups**
3. Search for `longhaul-app-identity` (the user-assigned managed identity)
4. Set role to **Contributor**
5. Save

---

## Step 6 — Verify the Deployment

```powershell
# Check Terraform outputs
cd infra
terraform output
```

Key outputs:

| Output | Description |
|---|---|
| `container_app_ui_url` | MBR UI — open in a browser to verify |
| `container_app_api_url` | API gateway — open `<url>/docs` to verify FastAPI is running |
| `ai_project_endpoint` | Foundry project endpoint |
| `storage_account_url` | Blob Storage base URL |

**Deployment Validation Checklist:**

- [ ] `terraform apply` completes with exit 0
- [ ] Lakehouse tables created and seeded (`fact_monthly_kpis`, `fact_vehicle_kpis`, `dim_month`, `dim_region`, `dim_vehicle_type`)
- [ ] `mbr_template.pptx` uploaded to the `templates` blob container
- [ ] `da_mbr_trucking` visible in the Fabric workspace with `lh_mbr_trucking` as a data source, instructions set, and example queries added
- [ ] Foundry agents `conversational-agent` and `mbr-presentation-agent` visible in the Foundry portal
- [ ] Agent IDs injected as environment variables on `ca-mbr-api` Container App (`CONVERSATIONAL_AGENT_NAME`, `MBR_PRESENTATION_AGENT_NAME`)
- [ ] KPI bar loads on the Dashboard with data for the default period/region
- [ ] Conversational agent responds to questions in the Chat panel
- [ ] Clicking **Generate Presentation** triggers a `.pptx` download

---

## GitHub Actions (Optional)

CI/CD is pre-configured in `.github/workflows/`. Each workflow uses path filters — only the component that changed is redeployed.

| Files changed | Job that runs |
|---|---|
| `apps/mbr-api/**` | `deploy-api` |
| `apps/mbr-ui/**` | `deploy-ui` |
| `apps/mbr-tools-mcp/**` | `deploy-mcp` |
| `agents/conversational_agent.py` | `deploy-agents` (conversational only) |
| `agents/mbr_presentation_agent.py` | `deploy-agents` (presentation only) |
| `agents/deploy.py` / shared | `deploy-agents` (all agents) |
| `infra/**` | `deploy-infra` |

Three repository secrets are required:

| Secret | Description |
|---|---|
| `AZURE_CLIENT_ID` | Client ID of the GitHub Actions service principal |
| `AZURE_TENANT_ID` | Entra tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Target subscription ID |

Set these automatically by running deploy with the `-SetupGitHub` flag (requires `gh` CLI and `gh auth login`):

```powershell
.\deploy.ps1 -Subscription "YOUR-SUBSCRIPTION-NAME-OR-ID" -FabricWorkspaceId "<guid>" -SetupGitHub
```

**If OIDC credential creation is blocked by Conditional Access** (`AADSTS70025: no configured federated identity credentials`), create the federated credential manually:

1. **[portal.azure.com](https://portal.azure.com)** → **Microsoft Entra ID** → **App registrations**
2. Open **`sp-mbr-github`**
3. **Certificates & secrets** → **Federated credentials** → **Add credential**
4. Fill in:

   | Field | Value |
   |---|---|
   | Scenario | GitHub Actions deploying Azure resources |
   | Repository | `Azure-Fabric-MBR-AI-Agents` |
   | Entity type | Branch |
   | Branch | `main` |
   | Name | `github-actions-main` |

5. Click **Add**, then re-run the failed workflow.

> Run `deploy.ps1` at least once locally before pushing to apply the Terraform role assignments that grant the GitHub SP access to Key Vault and Foundry. Without this, the `deploy-agents` job will fail with a 403.

---

## Teardown

After testing or when no longer needed, tear down all deployed Azure resources:

```powershell
.\deploy.ps1 -Subscription "YOUR-SUBSCRIPTION-NAME-OR-ID" -Destroy
```

This runs `terraform destroy` on all resources. The Terraform state storage account (`rg-tfstate-mbr`) is **not** destroyed and must be removed manually if no longer needed.

The Fabric workspace and Lakehouse are not managed by Terraform and must be deleted separately from the [Fabric portal](https://app.fabric.microsoft.com).
