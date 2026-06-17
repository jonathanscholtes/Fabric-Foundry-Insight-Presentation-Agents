"""Create Lakehouse tables in the LONGHAUL Fabric Lakehouse.

Connects to the Fabric SQL analytics endpoint using pyodbc + Managed Identity
and creates all 5 tables if they do not already exist.

Usage:
    python fabric/scripts/setup_lakehouse.py \\
        --sql-server <workspace-id>-<lakehouse-id>.datawarehouse.fabric.microsoft.com
"""

from __future__ import annotations

import argparse
import logging
import struct

import pyodbc
from azure.identity import DefaultAzureCredential

logging.basicConfig(level=logging.INFO, format="[%(levelname)s] %(message)s")
log = logging.getLogger("setup_lakehouse")

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
    conn.autocommit = True
    return conn


DDL_STATEMENTS = [
    # dim_month — date table for DAX time intelligence; period_date is the key column
    """
    IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'dim_month')
    CREATE TABLE dim_month (
        month_id     INT          NOT NULL,
        period_date  DATE         NOT NULL,
        period_label VARCHAR(20)  NOT NULL,
        year         INT          NOT NULL,
        month_num    INT          NOT NULL,
        month_name   VARCHAR(20)  NOT NULL,
        sort_order   INT          NOT NULL,
        PRIMARY KEY (month_id)
    )
    """,

    # dim_region
    """
    IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'dim_region')
    CREATE TABLE dim_region (
        region_id   INT         NOT NULL,
        region_name VARCHAR(50) NOT NULL,
        region_code VARCHAR(5)  NOT NULL,
        PRIMARY KEY (region_id)
    )
    """,

    # dim_vehicle_type
    """
    IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'dim_vehicle_type')
    CREATE TABLE dim_vehicle_type (
        vehicle_type_id   INT         NOT NULL,
        vehicle_type_name VARCHAR(50) NOT NULL,
        PRIMARY KEY (vehicle_type_id)
    )
    """,

    # fact_monthly_kpis — primary fact table
    """
    IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'fact_monthly_kpis')
    CREATE TABLE fact_monthly_kpis (
        region_id           INT            NOT NULL,
        month_id            INT            NOT NULL,
        total_revenue       DECIMAL(18,2)  NOT NULL,
        loaded_miles        INT            NOT NULL,
        empty_miles         INT            NOT NULL,
        total_miles         INT            NOT NULL,
        fuel_cost           DECIMAL(18,2)  NOT NULL,
        driver_cost         DECIMAL(18,2)  NOT NULL,
        maintenance_cost    DECIMAL(18,2)  NOT NULL,
        overhead_cost       DECIMAL(18,2)  NOT NULL,
        total_cost          DECIMAL(18,2)  NOT NULL,
        on_time_deliveries  INT            NOT NULL,
        total_deliveries    INT            NOT NULL,
        load_capacity_units INT            NOT NULL,
        loads_delivered     INT            NOT NULL,
        driver_count        INT            NOT NULL,
        drivers_departed    INT            NOT NULL,
        incidents           INT            NOT NULL,
        PRIMARY KEY (region_id, month_id)
    )
    """,

    # fact_vehicle_kpis — per vehicle type breakdown
    """
    IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'fact_vehicle_kpis')
    CREATE TABLE fact_vehicle_kpis (
        region_id          INT           NOT NULL,
        month_id           INT           NOT NULL,
        vehicle_type_id    INT           NOT NULL,
        total_miles        INT           NOT NULL,
        fuel_cost          DECIMAL(18,2) NOT NULL,
        on_time_deliveries INT           NOT NULL,
        total_deliveries   INT           NOT NULL,
        PRIMARY KEY (region_id, month_id, vehicle_type_id)
    )
    """,
]


def main(sql_server: str) -> None:
    log.info("Connecting to %s / %s", sql_server, DATABASE)
    conn = get_connection(sql_server)
    cursor = conn.cursor()

    for stmt in DDL_STATEMENTS:
        table_match = [line for line in stmt.split("\n") if "CREATE TABLE" in line]
        table_name = table_match[0].split("CREATE TABLE")[1].strip() if table_match else "?"
        log.info("Creating table if not exists: %s", table_name)
        cursor.execute(stmt)

    cursor.close()
    conn.close()
    log.info("Lakehouse tables ready.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--sql-server", required=True, help="Fabric SQL analytics endpoint hostname")
    # workspace-id and lakehouse-id kept for compatibility with Deploy-FabricLakehouse.ps1
    parser.add_argument("--workspace-id", default="")
    parser.add_argument("--lakehouse-id", default="")
    args = parser.parse_args()
    main(args.sql_server)
