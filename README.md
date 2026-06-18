# LONGHAUL MBR AI Agents

AI-powered Monthly Business Review platform for long-haul trucking, built on **Microsoft Fabric** and **Microsoft Foundry**, deployed to **Azure Container Apps**.

## Architecture

```
Browser (mbr-ui)
    │
    ▼ REST /api/*
mbr-api  (FastAPI · ACA external)
    │
    ├─► Foundry AIProjectClient
    │       ├── conversational-agent  (FabricDataAgentTool)
    │       └── mbr-presentation-agent (FabricDataAgentTool + MCPTool)
    │                                         │
    │                                         ▼ MCP streamable-http (internal)
    │                              mbr-tools-mcp  (FastMCP · ACA internal)
    │                                  ├── fill_mbr_template  (python-pptx + LibreOffice)
    │                                  ├── get_mbr_deck_url
    │                                  └── list_mbr_decks
    │
    └─► Azure Blob Storage  (templates · thumbnails · decks · conversations · decks-metadata · exports)
```

**Rule**: `UI → mbr-api → [Agents / Foundry] → MCP`.  
`mbr-api` never calls `mbr-tools-mcp` directly. The MCP server is ACA internal-only.

## Components

| Path | What |
|---|---|
| `apps/mbr-api/` | FastAPI REST gateway (external) |
| `apps/mbr-tools-mcp/` | FastMCP server — PowerPoint + deck library tools (internal) |
| `apps/mbr-ui/` | React + Vite SPA |
| `agents/` | Foundry agent system prompts + deploy script |
| `infra/` | Terraform — ACA environment, ACR, Key Vault, Storage, AI Account |
| `fabric/scripts/` | Lakehouse DDL + seed data scripts |

## Prerequisites

- Azure subscription with Contributor access
- Microsoft Fabric workspace (manual setup — see [docs/fabric-setup.md](docs/fabric-setup.md))
- Microsoft Foundry project with `gpt-4.1` deployment
- Docker Desktop
- Terraform ≥ 1.9
- Python 3.12
- Node 20
- PowerShell 7 + Azure CLI

## Quick Start

### 1. GitHub OIDC (first time only)

```powershell
.\scripts\New-GitHubOidc.ps1 `
    -SubscriptionId <sub-id> `
    -TenantId       <tenant-id> `
    -GitHubOrg      <your-org> `
    -GitHubRepo     Azure-Fabric-MBR-AI-Agents `
    -Environment    dev
```

Set the printed values as GitHub repository variables:
- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`

### 2. Fabric Setup (manual)

Follow [docs/fabric-setup.md](docs/fabric-setup.md) to:
- Create the Lakehouse `lh_mbr_trucking`
- Create the Semantic Model `sm_mbr_trucking`
- Enable the Fabric Admin tenant setting for service principals
- After deploy, open `da_mbr_trucking` in the portal → add `lh_mbr_trucking` as a data source → paste agent instructions → Publish (see [§5b–5d](docs/fabric-setup.md#5b-add-the-data-source-manual--required))

### 3. Full Deploy

```powershell
.\deploy.ps1 `
    -SubscriptionId  <sub-id> `
    -TenantId        <tenant-id> `
    -FabricSqlServer <workspace-id>-<lakehouse-id>.datawarehouse.fabric.microsoft.com
```

Or use the **Deploy** GitHub Actions workflow (manual trigger).

### 4. Upload PowerPoint Template

Upload your MBR template to the `templates` container:

```bash
az storage blob upload \
    --account-name <storage-account> \
    --container-name templates \
    --name longhaul-mbr-template.pptx \
    --file data/templates/longhaul-mbr-template.pptx \
    --auth-mode login
```

See [data/templates/README.md](data/templates/README.md) for template design conventions.

## CI/CD

| Workflow | Trigger | What it does |
|---|---|---|
| `ci.yml` | Push / PR | Python ruff, React lint + build, Terraform validate |
| `deploy.yml` | Manual | Terraform apply, build + push images, Fabric seed, Foundry agent deploy |

## Environment Variables

### mbr-api

| Variable | Required | Description |
|---|---|---|
| `FOUNDRY_PROJECT_ENDPOINT` | Yes | Foundry project endpoint URL |
| `CONVERSATIONAL_AGENT_ID` | Yes | Agent ID from `agents/deploy.py` output |
| `MBR_PRESENTATION_AGENT_ID` | Yes | Agent ID from `agents/deploy.py` output |
| `STORAGE_ACCOUNT_NAME` | Yes | Azure Storage account name |
| `FABRIC_SQL_SERVER` | Yes | Fabric SQL analytics endpoint hostname |
| `FABRIC_SQL_DATABASE` | Yes | `lh-mbr-trucking` |

### mbr-tools-mcp

| Variable | Required | Description |
|---|---|---|
| `STORAGE_ACCOUNT_NAME` | Yes | Azure Storage account name |
| `FABRIC_SQL_SERVER` | Yes | Fabric SQL analytics endpoint hostname |
| `FABRIC_SQL_DATABASE` | Yes | `lh-mbr-trucking` |
| `MBR_TEMPLATE_BLOB_NAME` | No | Default: `longhaul-mbr-template.pptx` |

## Design Tokens

| Token | Value | Usage |
|---|---|---|
| `--color-sidebar` | `#1B2A3B` | Sidebar background |
| `--color-brand-accent` | `#27AE60` | Primary brand / active states |
| `--color-bg` | `#F4F6F9` | Page background |

## License

MIT
