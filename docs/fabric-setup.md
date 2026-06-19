# Fabric Setup Guide

Microsoft Fabric Lakehouse, Semantic Model, and Data Agent resources cannot be
created via Terraform — they require manual setup through the Fabric portal.

## 1. Create the Workspace

1. Go to [app.fabric.microsoft.com](https://app.fabric.microsoft.com)
2. Create (or open) a workspace — e.g. **longhaul-mbr**
3. Note the **Workspace ID** from the URL:
   `https://app.fabric.microsoft.com/groups/<workspace-id>/...`

## 2. Create the Lakehouse

1. In the workspace, click **New → Lakehouse**
2. Name it: `lh-mbr-trucking`
3. Once created, open the Lakehouse and note the **Lakehouse ID** from the URL
4. Go to **Lakehouse settings → SQL analytics endpoint**
5. Copy the **Server** hostname — it looks like:
   `<workspace-id>-<lakehouse-id>.datawarehouse.fabric.microsoft.com`

This hostname is your `FABRIC_SQL_SERVER`.

## 3. Create Tables and Seed Data

```bash
# Create tables
python fabric/scripts/setup_lakehouse.py \
    --sql-server <FABRIC_SQL_SERVER>

# Seed 13 months of data
python fabric/scripts/seed_data.py \
    --sql-server <FABRIC_SQL_SERVER>
```

Both scripts use `DefaultAzureCredential` — ensure you are logged in via
`az login` (local dev) or Managed Identity (deployed).

## 4. Create the Semantic Model

1. In the workspace, click **New → Semantic model**
2. Name it: `sm-mbr-trucking`
3. Connect it to the `lh-mbr-trucking` Lakehouse
4. Import these tables: `dim_month`, `dim_region`, `dim_vehicle_type`,
   `fact_monthly_kpis`, `fact_vehicle_kpis`
5. Define relationships:
   - `fact_monthly_kpis[month_id]` → `dim_month[month_id]` (Many-to-One)
   - `fact_monthly_kpis[region_id]` → `dim_region[region_id]` (Many-to-One)
   - `fact_vehicle_kpis[month_id]` → `dim_month[month_id]` (Many-to-One)
   - `fact_vehicle_kpis[region_id]` → `dim_region[region_id]` (Many-to-One)
   - `fact_vehicle_kpis[vehicle_type_id]` → `dim_vehicle_type[vehicle_type_id]` (Many-to-One)

### Date Table

Mark `dim_month` as the **Date Table** using column `period_date` (type: Date).
This is required for all DAX time-intelligence functions.

### Key DAX Measures

Add these measures to `fact_monthly_kpis`:

```dax
Total Revenue = SUM(fact_monthly_kpis[total_revenue])

Total Cost = SUM(fact_monthly_kpis[total_cost])

Operating Ratio =
    DIVIDE([Total Cost], [Total Revenue]) * 100

On-Time % =
    DIVIDE(
        SUM(fact_monthly_kpis[on_time_deliveries]),
        SUM(fact_monthly_kpis[total_deliveries])
    ) * 100

Fleet Utilization % =
    DIVIDE(
        SUM(fact_monthly_kpis[loads_delivered]),
        SUM(fact_monthly_kpis[load_capacity_units])
    ) * 100

Loaded Mile % =
    DIVIDE(
        SUM(fact_monthly_kpis[loaded_miles]),
        SUM(fact_monthly_kpis[total_miles])
    ) * 100

Revenue PY =
    CALCULATE([Total Revenue], PREVIOUSMONTH(dim_month[period_date]))

Revenue Delta % =
    DIVIDE([Total Revenue] - [Revenue PY], [Revenue PY]) * 100

Cost PY =
    CALCULATE([Total Cost], PREVIOUSMONTH(dim_month[period_date]))

Cost Delta % =
    DIVIDE([Total Cost] - [Cost PY], [Cost PY]) * 100

Driver Retention % =
    DIVIDE(
        SUM(fact_monthly_kpis[driver_count]) - SUM(fact_monthly_kpis[drivers_departed]),
        SUM(fact_monthly_kpis[driver_count])
    ) * 100
```

> **Important**: Use `PREVIOUSMONTH(dim_month[period_date])` — NOT
> `PREVIOUSMONTH(dim_month[period_label])`. The `period_label` column is text
> and will cause a DAX error.

## 5. Create and Configure the Data Agent

### 5a. Create the agent (automated)

Running `deploy.ps1 -FabricWorkspaceId <guid>` calls `Deploy-FabricDataAgent.ps1`,
which creates `da_mbr_trucking` via the Fabric REST API.  The creation step
(name + description) works reliably.  The `updateDefinition` step that follows
attempts to set the data source and instructions via API but **may not apply** —
the portal will show "No data added" if it fails.

### 5b. Add the data source (manual — required)

The Fabric portal is the only reliable way to wire up the Lakehouse:

1. Go to [app.fabric.microsoft.com](https://app.fabric.microsoft.com) and open
   the **longhaul-mbr** workspace
2. Open **da_mbr_trucking**
3. Click **Add data** → **Lakehouse**
4. Select **lh_mbr_trucking** from the workspace
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
- period_label: 'May 2025' (full month name, space, 4-digit year)
- region_name: 'North', 'South', 'East', 'West', 'Central'
- For all-region queries, omit the region filter

## Query guidelines
- Use SUM() for all fact columns
- Always GROUP BY when aggregating across multiple dimensions
- For MoM comparisons, prior month = sort_order - 1
- Express financial values in dollars. Express miles as whole numbers.
```

### 5c. Add agent instructions (manual — required)

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
- period_label format: 3-letter month abbreviation + space + 4-digit year — e.g. 'Mar 2025', 'Feb 2025', 'Nov 2024'. Never use the full month name ('March 2025' returns no data).
- region_name values: 'North', 'South', 'East', 'West', 'Central'
- For all-region queries, omit the region filter

## Query guidelines
- Use SUM() for all fact columns
- Always GROUP BY when aggregating across multiple dimensions
- For MoM comparisons, use sort_order: prior month is sort_order - 1
- Express financial values in dollars. Express miles as whole numbers.
- Filter for the most recent record when no explicit period is given.
```

### 5d. Add example queries (manual — required for performance)

Example queries feed the vector similarity search that runs on every user question. Without them the agent cold-generates SQL every time, adding 10–20 seconds of latency. Add at least the six queries below under **Example queries** in the data source configuration.

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
    SUM(f.driver_count)     AS driver_count,
    SUM(f.drivers_departed) AS drivers_departed,
    SUM(f.incidents)        AS incidents
FROM fact_monthly_kpis f
JOIN dim_month  m ON f.month_id  = m.month_id
JOIN dim_region r ON f.region_id = r.region_id
WHERE m.period_label = 'Mar 2025'
  AND r.region_name = 'North'
```

### 5e. Publish

Click **Publish** in the top toolbar. The agent is not active until published.

### 5f. Fabric connection name

After publishing, the connection name used by Microsoft Foundry is `da_mbr_trucking`.
This must match the value in `agents/deploy.py`:
```python
FABRIC_CONNECTION_NAME = "da_mbr_trucking"
```

## 6. Managed Identity Access

The app's managed identity (`longhaul-app-identity`) needs **Contributor** access
to the Fabric workspace so it can query the Lakehouse SQL analytics endpoint.

### Automated (recommended)

`deploy.ps1` calls `Deploy-FabricDataAgent.ps1 -AppIdentityPrincipalId <id>`,
which calls the Fabric REST API to add the managed identity as Contributor.

**Prerequisite — Fabric Admin setting (one-time, cannot be scripted):**

1. Go to [app.fabric.microsoft.com/admin](https://app.fabric.microsoft.com/admin)
2. Navigate to **Tenant settings → Developer settings**
3. Enable **"Allow service principals and managed identities to use Fabric APIs"**
4. Save

Without this setting, the automated RBAC call returns 403 and the deploy script
prints a warning. Re-run the deploy after enabling it, or add the identity manually:

### Manual fallback

1. Go to the workspace **Settings → Manage access**
2. Click **Add people or groups**
3. Search for `longhaul-app-identity` (the user-assigned managed identity)
4. Set role to **Contributor**
5. Save

For local development, ensure your user account has Contributor (or Viewer) access
and run `az login` to authenticate.

## Troubleshooting

| Problem | Likely cause |
|---|---|
| `ODBC Error: Token-based authentication not supported` | Driver version < 18; install ODBC Driver 18 for SQL Server |
| `Invalid object name 'dim_month'` | Tables not yet created — run `setup_lakehouse.py` first |
| `PREVIOUSMONTH error` | Using text column — ensure `period_date DATE` column exists and `dim_month` is marked as date table |
| Data Agent returns no results | Semantic model not connected, or wrong connection name in `deploy.py` |
