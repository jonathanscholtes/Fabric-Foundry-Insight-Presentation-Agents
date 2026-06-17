"""Seed the LONGHAUL Lakehouse with 13 months of synthetic data (May 2024 – May 2025).

Approach:
  1. Upload Parquet files to OneLake Files/staging/ via ADLS Gen2 SDK.
  2. Call the Fabric Load Tables API to create proper Delta tables from the Parquet.

The Fabric Lakehouse SQL analytics endpoint is read-only. Direct DML/DDL via
pyodbc and delta-rs direct writes use Delta protocol versions Fabric doesn't support.

Usage:
    python fabric/scripts/seed_data.py \\
        --workspace-id <workspace-guid> \\
        --lakehouse-id <lakehouse-guid> \\
        [--overwrite]
"""

from __future__ import annotations

import argparse
import io
import logging
import time
from datetime import date

import pandas as pd
import requests
from azure.identity import DefaultAzureCredential
from azure.storage.filedatalake import DataLakeServiceClient

logging.basicConfig(level=logging.INFO, format="[%(levelname)s] %(message)s")
log = logging.getLogger("seed_data")

FABRIC_API    = "https://api.fabric.microsoft.com/v1"
STAGING_FOLDER = "Files/staging"


# ── Dimension data ──────────────────────────────────────────────────────────

DIM_MONTHS = [
    (1,  date(2024, 5,  1), "May 2024",  2024,  5, "May",       1),
    (2,  date(2024, 6,  1), "Jun 2024",  2024,  6, "June",      2),
    (3,  date(2024, 7,  1), "Jul 2024",  2024,  7, "July",      3),
    (4,  date(2024, 8,  1), "Aug 2024",  2024,  8, "August",    4),
    (5,  date(2024, 9,  1), "Sep 2024",  2024,  9, "September", 5),
    (6,  date(2024, 10, 1), "Oct 2024",  2024, 10, "October",   6),
    (7,  date(2024, 11, 1), "Nov 2024",  2024, 11, "November",  7),
    (8,  date(2024, 12, 1), "Dec 2024",  2024, 12, "December",  8),
    (9,  date(2025, 1,  1), "Jan 2025",  2025,  1, "January",   9),
    (10, date(2025, 2,  1), "Feb 2025",  2025,  2, "February", 10),
    (11, date(2025, 3,  1), "Mar 2025",  2025,  3, "March",    11),
    (12, date(2025, 4,  1), "Apr 2025",  2025,  4, "April",    12),
    (13, date(2025, 5,  1), "May 2025",  2025,  5, "May",      13),
]

DIM_REGIONS = [
    (1, "North",   "N"),
    (2, "South",   "S"),
    (3, "East",    "E"),
    (4, "West",    "W"),
    (5, "Central", "C"),
]

DIM_VEHICLE_TYPES = [
    (1,  "Flatbed"),      (2,  "Refrigerated"), (3,  "Dry Van"),
    (4,  "Tanker"),       (5,  "Intermodal"),   (6,  "Oversized"),
    (7,  "Auto-Carrier"), (8,  "Livestock"),    (9,  "Pneumatic"),
    (10, "Lowboy"),       (11, "Step-Deck"),    (12, "Box Truck"),
    (13, "Sprinter"),     (14, "Hotshot"),      (15, "Dump"),
    (16, "Curtainside"),  (17, "Liquid Bulk"),  (18, "Logging"),
    (19, "Car Hauler"),   (20, "Side-Lifter"),
]


def _kpis_for(region_id: int, month_id: int) -> dict:
    base     = 1_200_000 + region_id * 80_000 + month_id * 15_000
    revenue  = round(base * 1.0, 2)
    loaded   = 350_000 + region_id * 12_000 + month_id * 800
    empty    = 50_000  + region_id * 2_000  + month_id * 100
    total_m  = loaded + empty
    fuel     = round(revenue * 0.28, 2)
    driver   = round(revenue * 0.35, 2)
    maint    = round(revenue * 0.06, 2)
    overhead = round(revenue * 0.08, 2)
    total_c  = round(fuel + driver + maint + overhead, 2)
    on_time  = 820 + region_id * 10 + month_id * 3
    total_d  = 900 + region_id * 10 + month_id * 3
    lcu      = 1200 + region_id * 20 + month_id * 5
    ld       = 1150 + region_id * 20 + month_id * 4
    drv      = 80   + region_id * 2  + (month_id % 3)
    depart   = 2    + (month_id % 4)
    inc      = max(0, 3 - month_id % 3)
    return dict(
        region_id=region_id, month_id=month_id,
        total_revenue=revenue, loaded_miles=loaded, empty_miles=empty, total_miles=total_m,
        fuel_cost=fuel, driver_cost=driver, maintenance_cost=maint, overhead_cost=overhead,
        total_cost=total_c, on_time_deliveries=on_time, total_deliveries=total_d,
        load_capacity_units=lcu, loads_delivered=ld,
        driver_count=drv, drivers_departed=depart, incidents=inc,
    )


def _vehicle_kpis_for(region_id: int, month_id: int, vehicle_type_id: int) -> dict:
    total_m = 25_000 + vehicle_type_id * 500 + month_id * 200
    fuel    = round(total_m * 0.18, 2)
    on_time = 55 + vehicle_type_id % 10
    total_d = 60 + vehicle_type_id % 10
    return dict(
        region_id=region_id, month_id=month_id, vehicle_type_id=vehicle_type_id,
        total_miles=total_m, fuel_cost=fuel,
        on_time_deliveries=on_time, total_deliveries=total_d,
    )


# ── OneLake / Fabric helpers ────────────────────────────────────────────────

def _upload_parquet(fs_client, lakehouse_id: str, table_name: str, df: pd.DataFrame) -> str:
    """Upload DataFrame as Parquet to Files/staging/ and return the relative path."""
    rel_path = f"{STAGING_FOLDER}/{table_name}.parquet"
    onelake_path = f"{lakehouse_id}/{rel_path}"

    buf = io.BytesIO()
    df.to_parquet(buf, index=False, engine="pyarrow")
    data = buf.getvalue()

    fc = fs_client.get_file_client(onelake_path)
    fc.upload_data(data, overwrite=True, length=len(data))
    log.info("  Uploaded %s (%d bytes)", onelake_path, len(data))
    return rel_path


def _poll_lro(url: str, headers: dict, timeout: int = 300) -> None:
    elapsed, interval = 0, 10
    while elapsed < timeout:
        time.sleep(interval)
        elapsed += interval
        resp = requests.get(url, headers=headers, timeout=30)
        if resp.status_code == 200:
            status = resp.json().get("status", "").lower()
            if status in ("succeeded", "completed"):
                return
            if status in ("failed", "cancelled"):
                raise RuntimeError(f"Fabric LRO failed: {resp.text}")
        log.info("  LRO status check at %ds...", elapsed)
    raise TimeoutError(f"Fabric LRO timed out after {timeout}s")


def _load_table(workspace_id: str, lakehouse_id: str, table_name: str,
                rel_path: str, fabric_token: str, overwrite: bool) -> None:
    """Call Fabric Load Tables API to create/overwrite a Delta table from Parquet."""
    url = (
        f"{FABRIC_API}/workspaces/{workspace_id}"
        f"/lakehouses/{lakehouse_id}/tables/{table_name}/load"
    )
    headers = {
        "Authorization": f"Bearer {fabric_token}",
        "Content-Type":  "application/json",
    }
    payload = {
        "relativePath":  rel_path,
        "pathType":      "File",
        "mode":          "Overwrite" if overwrite else "Append",
        "formatOptions": {"format": "Parquet", "header": True},
    }

    resp = requests.post(url, json=payload, headers=headers, timeout=30)

    if resp.status_code == 202:
        op_url = resp.headers.get("Location") or resp.headers.get("x-ms-operation-id", "")
        if op_url and not op_url.startswith("http"):
            op_url = f"{FABRIC_API}/operations/{op_url}"
        if op_url:
            _poll_lro(op_url, headers)
    elif resp.status_code not in (200, 201):
        raise RuntimeError(
            f"Load table '{table_name}' failed: {resp.status_code} {resp.text}"
        )

    log.info("  Table ready: %s", table_name)


# ── Seeding logic ───────────────────────────────────────────────────────────

def seed(workspace_id: str, lakehouse_id: str, overwrite: bool) -> None:
    credential    = DefaultAzureCredential()
    storage_token = credential.get_token("https://storage.azure.com/.default").token
    fabric_token  = credential.get_token("https://api.fabric.microsoft.com").token

    fs_client = DataLakeServiceClient(
        account_url="https://onelake.dfs.fabric.microsoft.com",
        credential=credential,
    ).get_file_system_client(workspace_id)

    def write(table_name: str, df: pd.DataFrame) -> None:
        log.info("Seeding %s (%d rows)...", table_name, len(df))
        rel = _upload_parquet(fs_client, lakehouse_id, table_name, df)
        _load_table(workspace_id, lakehouse_id, table_name, rel, fabric_token, overwrite)

    write("dim_month", pd.DataFrame(
        DIM_MONTHS,
        columns=["month_id", "period_date", "period_label", "year",
                 "month_num", "month_name", "sort_order"],
    ))
    write("dim_region", pd.DataFrame(
        DIM_REGIONS, columns=["region_id", "region_name", "region_code"],
    ))
    write("dim_vehicle_type", pd.DataFrame(
        DIM_VEHICLE_TYPES, columns=["vehicle_type_id", "vehicle_type_name"],
    ))
    write("fact_monthly_kpis", pd.DataFrame([
        _kpis_for(r[0], m[0]) for r in DIM_REGIONS for m in DIM_MONTHS
    ]))
    write("fact_vehicle_kpis", pd.DataFrame([
        _vehicle_kpis_for(r[0], m[0], vt[0])
        for r in DIM_REGIONS for m in DIM_MONTHS for vt in DIM_VEHICLE_TYPES[:4]
    ]))

    log.info("Seed complete.")


def main(workspace_id: str, lakehouse_id: str, overwrite: bool) -> None:
    log.info("Seeding OneLake workspace=%s lakehouse=%s", workspace_id, lakehouse_id)
    seed(workspace_id, lakehouse_id, overwrite=overwrite)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--workspace-id", required=True)
    parser.add_argument("--lakehouse-id", required=True)
    parser.add_argument("--sql-server", default="")  # retained for CLI compatibility
    parser.add_argument("--overwrite", action="store_true",
                        help="Overwrite existing rows (default: append)")
    parser.add_argument("--truncate", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    main(args.workspace_id, args.lakehouse_id,
         overwrite=args.overwrite or args.truncate)
