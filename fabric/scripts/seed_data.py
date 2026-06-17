"""Seed the LONGHAUL Lakehouse with 13 months of synthetic data (May 2024 – May 2025).

Usage:
    python fabric/scripts/seed_data.py \\
        --sql-server <workspace-id>-<lakehouse-id>.datawarehouse.fabric.microsoft.com \\
        [--truncate]   # wipe existing rows before inserting
"""

from __future__ import annotations

import argparse
import logging
import struct
from datetime import date

import pyodbc
from azure.identity import DefaultAzureCredential

logging.basicConfig(level=logging.INFO, format="[%(levelname)s] %(message)s")
log = logging.getLogger("seed_data")

DATABASE = "lh-mbr-trucking"


def get_connection(server: str) -> pyodbc.Connection:
    credential = DefaultAzureCredential()
    token = credential.get_token("https://analysis.windows.net/powerbi/api/.default")
    token_bytes = token.token.encode("utf-16-le")
    token_struct = struct.pack(f"<I{len(token_bytes)}s", len(token_bytes), token_bytes)

    conn = pyodbc.connect(
        f"Driver={{ODBC Driver 18 for SQL Server}};"
        f"Server={server},1433;"
        f"Database={DATABASE};"
        "Encrypt=yes;TrustServerCertificate=no;",
        attrs_before={1256: token_struct},
    )
    conn.autocommit = False
    return conn


# ── Dimension data ──────────────────────────────────────────────────────────

DIM_MONTHS = [
    # (month_id, period_date, period_label, year, month_num, month_name, sort_order)
    (1,  date(2024, 5,  1), "May 2024",  2024,  5, "May",      1),
    (2,  date(2024, 6,  1), "Jun 2024",  2024,  6, "June",     2),
    (3,  date(2024, 7,  1), "Jul 2024",  2024,  7, "July",     3),
    (4,  date(2024, 8,  1), "Aug 2024",  2024,  8, "August",   4),
    (5,  date(2024, 9,  1), "Sep 2024",  2024,  9, "September",5),
    (6,  date(2024, 10, 1), "Oct 2024",  2024, 10, "October",  6),
    (7,  date(2024, 11, 1), "Nov 2024",  2024, 11, "November", 7),
    (8,  date(2024, 12, 1), "Dec 2024",  2024, 12, "December", 8),
    (9,  date(2025, 1,  1), "Jan 2025",  2025,  1, "January",  9),
    (10, date(2025, 2,  1), "Feb 2025",  2025,  2, "February", 10),
    (11, date(2025, 3,  1), "Mar 2025",  2025,  3, "March",    11),
    (12, date(2025, 4,  1), "Apr 2025",  2025,  4, "April",    12),
    (13, date(2025, 5,  1), "May 2025",  2025,  5, "May",      13),
]

DIM_REGIONS = [
    # (region_id, region_name, region_code)
    (1, "North",   "N"),
    (2, "South",   "S"),
    (3, "East",    "E"),
    (4, "West",    "W"),
    (5, "Central", "C"),
]

DIM_VEHICLE_TYPES = [
    # (vehicle_type_id, vehicle_type_name)
    (1, "Flatbed"),
    (2, "Refrigerated"),
    (3, "Dry Van"),
    (4, "Tanker"),
    (5, "Intermodal"),
    (6, "Oversized"),
    (7, "Auto-Carrier"),
    (8, "Livestock"),
    (9, "Pneumatic"),
    (10, "Lowboy"),
    (11, "Step-Deck"),
    (12, "Box Truck"),
    (13, "Sprinter"),
    (14, "Hotshot"),
    (15, "Dump"),
    (16, "Curtainside"),
    (17, "Liquid Bulk"),
    (18, "Logging"),
    (19, "Car Hauler"),
    (20, "Side-Lifter"),
]


def _kpis_for(region_id: int, month_id: int) -> tuple:
    """Produce deterministic synthetic KPIs using simple arithmetic.

    Values vary gently by region_id and month_id to simulate realistic drift
    without requiring random numbers (ensures repeatable seeding).
    """
    base = 1_200_000 + region_id * 80_000 + month_id * 15_000
    revenue = round(base * 1.0, 2)
    loaded  = 350_000 + region_id * 12_000 + month_id * 800
    empty   = 50_000  + region_id * 2_000  + month_id * 100
    total_m = loaded + empty
    fuel    = round(revenue * 0.28, 2)
    driver  = round(revenue * 0.35, 2)
    maint   = round(revenue * 0.06, 2)
    overhead = round(revenue * 0.08, 2)
    total_c = round(fuel + driver + maint + overhead, 2)
    on_time = 820 + region_id * 10 + month_id * 3
    total_d = 900 + region_id * 10 + month_id * 3
    lcu     = 1200 + region_id * 20 + month_id * 5
    ld      = 1150 + region_id * 20 + month_id * 4
    drv     = 80   + region_id * 2  + (month_id % 3)
    depart  = 2    + (month_id % 4)
    inc     = max(0, 3 - month_id % 3)
    return (
        region_id, month_id,
        revenue, loaded, empty, total_m,
        fuel, driver, maint, overhead, total_c,
        on_time, total_d, lcu, ld, drv, depart, inc,
    )


def _vehicle_kpis_for(region_id: int, month_id: int, vehicle_type_id: int) -> tuple:
    total_m = 25_000 + vehicle_type_id * 500 + month_id * 200
    fuel    = round(total_m * 0.18, 2)
    on_time = 55 + vehicle_type_id % 10
    total_d = 60 + vehicle_type_id % 10
    return (region_id, month_id, vehicle_type_id, total_m, fuel, on_time, total_d)


# ── Seeding logic ───────────────────────────────────────────────────────────

def seed(conn: pyodbc.Connection, truncate: bool) -> None:
    cursor = conn.cursor()

    if truncate:
        log.info("Truncating tables...")
        for tbl in ("fact_vehicle_kpis", "fact_monthly_kpis", "dim_vehicle_type",
                    "dim_region", "dim_month"):
            cursor.execute(f"DELETE FROM {tbl}")

    # dim_month
    log.info("Seeding dim_month (%d rows)...", len(DIM_MONTHS))
    cursor.executemany(
        "IF NOT EXISTS (SELECT 1 FROM dim_month WHERE month_id=?) "
        "INSERT INTO dim_month (month_id,period_date,period_label,year,month_num,month_name,sort_order) "
        "VALUES (?,?,?,?,?,?,?)",
        [(r[0],) + r for r in DIM_MONTHS],
    )

    # dim_region
    log.info("Seeding dim_region (%d rows)...", len(DIM_REGIONS))
    cursor.executemany(
        "IF NOT EXISTS (SELECT 1 FROM dim_region WHERE region_id=?) "
        "INSERT INTO dim_region (region_id,region_name,region_code) VALUES (?,?,?)",
        [(r[0],) + r for r in DIM_REGIONS],
    )

    # dim_vehicle_type
    log.info("Seeding dim_vehicle_type (%d rows)...", len(DIM_VEHICLE_TYPES))
    cursor.executemany(
        "IF NOT EXISTS (SELECT 1 FROM dim_vehicle_type WHERE vehicle_type_id=?) "
        "INSERT INTO dim_vehicle_type (vehicle_type_id,vehicle_type_name) VALUES (?,?)",
        [(r[0],) + r for r in DIM_VEHICLE_TYPES],
    )

    # fact_monthly_kpis — 5 regions × 13 months = 65 rows
    fact_monthly = [_kpis_for(r[0], m[0]) for r in DIM_REGIONS for m in DIM_MONTHS]
    log.info("Seeding fact_monthly_kpis (%d rows)...", len(fact_monthly))
    cursor.executemany(
        "IF NOT EXISTS (SELECT 1 FROM fact_monthly_kpis WHERE region_id=? AND month_id=?) "
        "INSERT INTO fact_monthly_kpis "
        "(region_id,month_id,total_revenue,loaded_miles,empty_miles,total_miles,"
        "fuel_cost,driver_cost,maintenance_cost,overhead_cost,total_cost,"
        "on_time_deliveries,total_deliveries,load_capacity_units,loads_delivered,"
        "driver_count,drivers_departed,incidents) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
        [r[:2] + r for r in fact_monthly],
    )

    # fact_vehicle_kpis — 5 regions × 13 months × 4 types = 260 rows (top 4 vehicle types)
    fact_vehicle = [
        _vehicle_kpis_for(r[0], m[0], vt[0])
        for r in DIM_REGIONS
        for m in DIM_MONTHS
        for vt in DIM_VEHICLE_TYPES[:4]
    ]
    log.info("Seeding fact_vehicle_kpis (%d rows)...", len(fact_vehicle))
    cursor.executemany(
        "IF NOT EXISTS (SELECT 1 FROM fact_vehicle_kpis "
        "WHERE region_id=? AND month_id=? AND vehicle_type_id=?) "
        "INSERT INTO fact_vehicle_kpis "
        "(region_id,month_id,vehicle_type_id,total_miles,fuel_cost,on_time_deliveries,total_deliveries) "
        "VALUES (?,?,?,?,?,?,?)",
        [r[:3] + r for r in fact_vehicle],
    )

    conn.commit()
    cursor.close()
    log.info("Seed complete.")


def main(sql_server: str, truncate: bool) -> None:
    log.info("Connecting to %s / %s", sql_server, DATABASE)
    conn = get_connection(sql_server)
    seed(conn, truncate=truncate)
    conn.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--sql-server", required=True)
    parser.add_argument("--workspace-id", default="")
    parser.add_argument("--lakehouse-id", default="")
    parser.add_argument("--truncate", action="store_true",
                        help="Delete all rows before inserting seed data")
    args = parser.parse_args()
    main(args.sql_server, args.truncate)
