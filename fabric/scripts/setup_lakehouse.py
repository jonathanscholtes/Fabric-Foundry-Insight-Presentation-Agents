"""Create Lakehouse tables in the LONGHAUL Fabric Lakehouse via OneLake direct write.

The Fabric Lakehouse SQL analytics endpoint is read-only; tables must be created by
writing empty Delta files to OneLake. The SQL endpoint auto-discovers them.

Usage:
    python fabric/scripts/setup_lakehouse.py \\
        --workspace-id <workspace-guid> \\
        --lakehouse-id <lakehouse-guid>
"""

from __future__ import annotations

import argparse
import logging

import pyarrow as pa
from azure.identity import DefaultAzureCredential
from deltalake import DeltaTable, write_deltalake

logging.basicConfig(level=logging.INFO, format="[%(levelname)s] %(message)s")
log = logging.getLogger("setup_lakehouse")


TABLE_SCHEMAS: dict[str, pa.Schema] = {
    "dim_month": pa.schema([
        pa.field("month_id",     pa.int32()),
        pa.field("period_date",  pa.date32()),
        pa.field("period_label", pa.string()),
        pa.field("year",         pa.int32()),
        pa.field("month_num",    pa.int32()),
        pa.field("month_name",   pa.string()),
        pa.field("sort_order",   pa.int32()),
    ]),
    "dim_region": pa.schema([
        pa.field("region_id",   pa.int32()),
        pa.field("region_name", pa.string()),
        pa.field("region_code", pa.string()),
    ]),
    "dim_vehicle_type": pa.schema([
        pa.field("vehicle_type_id",   pa.int32()),
        pa.field("vehicle_type_name", pa.string()),
    ]),
    "fact_monthly_kpis": pa.schema([
        pa.field("region_id",           pa.int32()),
        pa.field("month_id",            pa.int32()),
        pa.field("total_revenue",       pa.float64()),
        pa.field("loaded_miles",        pa.int32()),
        pa.field("empty_miles",         pa.int32()),
        pa.field("total_miles",         pa.int32()),
        pa.field("fuel_cost",           pa.float64()),
        pa.field("driver_cost",         pa.float64()),
        pa.field("maintenance_cost",    pa.float64()),
        pa.field("overhead_cost",       pa.float64()),
        pa.field("total_cost",          pa.float64()),
        pa.field("on_time_deliveries",  pa.int32()),
        pa.field("total_deliveries",    pa.int32()),
        pa.field("load_capacity_units", pa.int32()),
        pa.field("loads_delivered",     pa.int32()),
        pa.field("driver_count",        pa.int32()),
        pa.field("drivers_departed",    pa.int32()),
        pa.field("incidents",           pa.int32()),
    ]),
    "fact_vehicle_kpis": pa.schema([
        pa.field("region_id",          pa.int32()),
        pa.field("month_id",           pa.int32()),
        pa.field("vehicle_type_id",    pa.int32()),
        pa.field("total_miles",        pa.int32()),
        pa.field("fuel_cost",          pa.float64()),
        pa.field("on_time_deliveries", pa.int32()),
        pa.field("total_deliveries",   pa.int32()),
    ]),
}


def _onelake_path(workspace_id: str, lakehouse_id: str, table_name: str) -> str:
    return (
        f"abfss://{workspace_id}@onelake.dfs.fabric.microsoft.com"
        f"/{lakehouse_id}/Tables/{table_name}"
    )


def main(workspace_id: str, lakehouse_id: str) -> None:
    credential = DefaultAzureCredential()
    token = credential.get_token("https://storage.azure.com/.default").token
    storage_options = {"bearer_token": token}

    for table_name, schema in TABLE_SCHEMAS.items():
        path = _onelake_path(workspace_id, lakehouse_id, table_name)

        if DeltaTable.is_deltatable(path, storage_options=storage_options):
            log.info("Already exists: %s", table_name)
            continue

        log.info("Creating table: %s", table_name)
        empty = pa.table({f.name: pa.array([], type=f.type) for f in schema})
        write_deltalake(path, empty, storage_options=storage_options, mode="error")
        log.info("Created: %s", table_name)

    log.info("Lakehouse tables ready.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--workspace-id", required=True)
    parser.add_argument("--lakehouse-id", required=True)
    parser.add_argument("--sql-server", default="")  # retained for CLI compatibility
    args = parser.parse_args()
    main(args.workspace_id, args.lakehouse_id)
