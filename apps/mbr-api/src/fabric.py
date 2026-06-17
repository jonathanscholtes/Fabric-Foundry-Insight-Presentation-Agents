"""Fabric Lakehouse SQL connection and KPI query helpers."""

from __future__ import annotations

import struct
import logging

import pyodbc
from azure.identity import ManagedIdentityCredential

from .config import settings

logger = logging.getLogger("mbr-api.fabric")


def get_fabric_connection(server: str, database: str) -> pyodbc.Connection:
    """Establish a pyodbc connection to the Fabric Lakehouse SQL endpoint using Managed Identity."""
    credential = ManagedIdentityCredential(
        client_id=settings.AZURE_CLIENT_ID if settings.AZURE_CLIENT_ID else None
    )
    token = credential.get_token("https://analysis.windows.net/powerbi/api/.default")

    # Pack the token as a SQL Server token struct (required by ODBC Driver 18)
    token_bytes = token.token.encode("utf-16-le")
    token_struct = struct.pack(f"<I{len(token_bytes)}s", len(token_bytes), token_bytes)

    conn = pyodbc.connect(
        f"Driver={{ODBC Driver 18 for SQL Server}};"
        f"Server={server},1433;"
        f"Database={database};"
        f"Encrypt=yes;TrustServerCertificate=no;",
        attrs_before={1256: token_struct},  # SQL_COPT_SS_ACCESS_TOKEN = 1256
    )
    return conn


def _parse_period_label(period: str) -> str:
    """Convert API period param (e.g. 'May2025') to display label (e.g. 'May 2025')."""
    # If the period already contains a space it's already formatted
    if " " in period:
        return period
    # Insert space before the 4-digit year
    for i, ch in enumerate(period):
        if ch.isdigit() and i > 0:
            return period[:i] + " " + period[i:]
    return period


def _run_kpi_query(conn: pyodbc.Connection, period_label: str, region: str) -> dict | None:
    """Run the KPI aggregate query for the given period and region."""
    sql = """
        SELECT
            SUM(f.total_revenue)        AS total_revenue,
            SUM(f.total_miles)          AS total_miles,
            SUM(f.empty_miles)          AS empty_miles,
            SUM(f.total_cost)           AS total_cost,
            SUM(f.on_time_deliveries)   AS on_time_deliveries,
            SUM(f.total_deliveries)     AS total_deliveries
        FROM fact_monthly_kpis f
        JOIN dim_month  m ON f.month_id  = m.month_id
        JOIN dim_region r ON f.region_id = r.region_id
        WHERE m.period_label = ?
          AND (r.region_name = ? OR ? = 'All')
    """
    cursor = conn.cursor()
    cursor.execute(sql, period_label, region, region)
    row = cursor.fetchone()
    if row is None or row[0] is None:
        return None

    total_revenue = float(row[0])
    total_miles = int(row[1])
    empty_miles = int(row[2])
    total_cost = float(row[3])
    on_time_deliveries = int(row[4])
    total_deliveries = int(row[5])

    return {
        "total_revenue": total_revenue,
        "total_miles": total_miles,
        "empty_miles": empty_miles,
        "total_cost": total_cost,
        "on_time_deliveries": on_time_deliveries,
        "total_deliveries": total_deliveries,
    }


def _get_prior_period_label(conn: pyodbc.Connection, period_label: str) -> str | None:
    """Retrieve the period_label for the month immediately prior to the given period."""
    sql = """
        SELECT m2.period_label
        FROM dim_month m1
        JOIN dim_month m2 ON m2.month_id = m1.month_id - 1
        WHERE m1.period_label = ?
    """
    cursor = conn.cursor()
    cursor.execute(sql, period_label)
    row = cursor.fetchone()
    return row[0] if row else None


def _derive_kpis(raw: dict) -> dict:
    """Compute derived KPI fields from raw aggregate sums."""
    total_revenue = raw["total_revenue"]
    total_miles = raw["total_miles"]
    empty_miles = raw["empty_miles"]
    total_cost = raw["total_cost"]
    on_time_deliveries = raw["on_time_deliveries"]
    total_deliveries = raw["total_deliveries"]

    empty_miles_pct = (empty_miles / total_miles * 100) if total_miles else 0.0
    operating_margin_pct = ((total_revenue - total_cost) / total_revenue * 100) if total_revenue else 0.0
    cost_per_mile = (total_cost / total_miles) if total_miles else 0.0
    on_time_delivery_pct = (on_time_deliveries / total_deliveries * 100) if total_deliveries else 0.0

    return {
        "total_revenue": total_revenue,
        "total_miles": total_miles,
        "empty_miles_pct": empty_miles_pct,
        "operating_margin_pct": operating_margin_pct,
        "cost_per_mile": cost_per_mile,
        "on_time_delivery_pct": on_time_delivery_pct,
    }


def _direction(delta: float) -> str:
    if delta > 0:
        return "up"
    if delta < 0:
        return "down"
    return "flat"


def get_kpis(period: str, region: str) -> dict:
    """
    Query Fabric Lakehouse for KPIs for the given period and region.

    Returns a KpiPayload-shaped dict with current values and MoM deltas.
    Raises ValueError if the period is not found in the Lakehouse.
    """
    period_label = _parse_period_label(period)

    conn = get_fabric_connection(settings.FABRIC_SQL_SERVER, settings.FABRIC_SQL_DATABASE)
    try:
        current_raw = _run_kpi_query(conn, period_label, region)
        if current_raw is None:
            raise ValueError(f"Period '{period_label}' not found in Lakehouse")

        current = _derive_kpis(current_raw)

        prior_label = _get_prior_period_label(conn, period_label)
        prior = None
        if prior_label:
            prior_raw = _run_kpi_query(conn, prior_label, region)
            if prior_raw:
                prior = _derive_kpis(prior_raw)
    finally:
        conn.close()

    def pct_delta(cur: float, prev: float) -> float:
        if prev == 0:
            return 0.0
        return round((cur - prev) / abs(prev) * 100, 2)

    def pp_delta(cur: float, prev: float) -> float:
        return round(cur - prev, 2)

    # Build the KpiPayload-shaped dict
    result: dict = {
        "period": period_label,
        "region": region,
    }

    # total_revenue — delta_pct
    rev_delta = pct_delta(current["total_revenue"], prior["total_revenue"]) if prior else 0.0
    result["total_revenue"] = {
        "value": round(current["total_revenue"], 2),
        "delta_pct": rev_delta,
        "direction": _direction(rev_delta),
    }

    # total_miles — delta_pct
    miles_delta = pct_delta(current["total_miles"], prior["total_miles"]) if prior else 0.0
    result["total_miles"] = {
        "value": current["total_miles"],
        "delta_pct": miles_delta,
        "direction": _direction(miles_delta),
    }

    # empty_miles_pct — delta_pp
    emp_delta = pp_delta(current["empty_miles_pct"], prior["empty_miles_pct"]) if prior else 0.0
    result["empty_miles_pct"] = {
        "value": round(current["empty_miles_pct"], 2),
        "delta_pp": emp_delta,
        "direction": _direction(emp_delta),
    }

    # operating_margin_pct — delta_pp
    margin_delta = pp_delta(current["operating_margin_pct"], prior["operating_margin_pct"]) if prior else 0.0
    result["operating_margin_pct"] = {
        "value": round(current["operating_margin_pct"], 2),
        "delta_pp": margin_delta,
        "direction": _direction(margin_delta),
    }

    # cost_per_mile — delta_pct
    cpm_delta = pct_delta(current["cost_per_mile"], prior["cost_per_mile"]) if prior else 0.0
    result["cost_per_mile"] = {
        "value": round(current["cost_per_mile"], 4),
        "delta_pct": cpm_delta,
        "direction": _direction(cpm_delta),
    }

    # on_time_delivery_pct — delta_pp
    otd_delta = pp_delta(current["on_time_delivery_pct"], prior["on_time_delivery_pct"]) if prior else 0.0
    result["on_time_delivery_pct"] = {
        "value": round(current["on_time_delivery_pct"], 2),
        "delta_pp": otd_delta,
        "direction": _direction(otd_delta),
    }

    return result
