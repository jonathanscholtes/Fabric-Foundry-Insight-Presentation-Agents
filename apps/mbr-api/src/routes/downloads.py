"""Downloads / exports endpoint — builds .xlsx from Fabric SQL and returns SAS URL."""

from __future__ import annotations

import io
import logging
from datetime import datetime, timezone

import openpyxl
from fastapi import APIRouter, HTTPException, Query

from ..config import settings
from ..fabric import get_fabric_connection, _parse_period_label
from ..models import ExportResponse
from ..storage import get_blob_sas_url, upload_blob

logger = logging.getLogger("mbr-api.routes.downloads")

router = APIRouter()


def _fetch_kpi_rows(
    period_label: str, region: str
) -> list[dict]:
    """
    Query Fabric Lakehouse for all KPI rows for the period and region.
    Returns a list of row dicts with all fact_monthly_kpis columns.
    """
    sql = """
        SELECT
            r.region_name,
            m.period_label,
            m.year,
            m.month_name,
            f.total_revenue,
            f.loaded_miles,
            f.empty_miles,
            f.total_miles,
            f.fuel_cost,
            f.driver_cost,
            f.maintenance_cost,
            f.overhead_cost,
            f.total_cost,
            f.on_time_deliveries,
            f.total_deliveries,
            f.load_capacity_units,
            f.loads_delivered,
            f.driver_count,
            f.drivers_departed,
            f.incidents
        FROM fact_monthly_kpis f
        JOIN dim_month  m ON f.month_id  = m.month_id
        JOIN dim_region r ON f.region_id = r.region_id
        WHERE m.period_label = ?
          AND (r.region_name = ? OR ? = 'All')
        ORDER BY r.region_name
    """
    conn = get_fabric_connection(settings.FABRIC_SQL_SERVER, settings.FABRIC_SQL_DATABASE)
    try:
        cursor = conn.cursor()
        cursor.execute(sql, period_label, region, region)
        columns = [desc[0] for desc in cursor.description]
        rows = []
        for row in cursor.fetchall():
            rows.append(dict(zip(columns, row)))
        return rows
    finally:
        conn.close()


def _fetch_vehicle_rows(period_label: str, region: str) -> list[dict]:
    """Query fact_vehicle_kpis for the given period and region."""
    sql = """
        SELECT
            r.region_name,
            m.period_label,
            vt.vehicle_type_name,
            f.total_miles,
            f.fuel_cost,
            f.on_time_deliveries,
            f.total_deliveries
        FROM fact_vehicle_kpis f
        JOIN dim_month       m  ON f.month_id        = m.month_id
        JOIN dim_region      r  ON f.region_id       = r.region_id
        JOIN dim_vehicle_type vt ON f.vehicle_type_id = vt.vehicle_type_id
        WHERE m.period_label = ?
          AND (r.region_name = ? OR ? = 'All')
        ORDER BY r.region_name, vt.vehicle_type_name
    """
    conn = get_fabric_connection(settings.FABRIC_SQL_SERVER, settings.FABRIC_SQL_DATABASE)
    try:
        cursor = conn.cursor()
        cursor.execute(sql, period_label, region, region)
        columns = [desc[0] for desc in cursor.description]
        rows = []
        for row in cursor.fetchall():
            rows.append(dict(zip(columns, row)))
        return rows
    finally:
        conn.close()


def _build_xlsx(kpi_rows: list[dict], vehicle_rows: list[dict]) -> bytes:
    """Build an .xlsx workbook from KPI data and return raw bytes."""
    wb = openpyxl.Workbook()

    # ── Sheet 1: Summary KPIs ─────────────────────────────────────────────────
    ws_summary = wb.active
    ws_summary.title = "Summary KPIs"

    summary_headers = [
        "Region", "Period", "Year", "Month",
        "Total Revenue ($)", "Loaded Miles", "Empty Miles", "Total Miles",
        "Fuel Cost ($)", "Driver Cost ($)", "Maintenance Cost ($)", "Overhead Cost ($)", "Total Cost ($)",
        "On-Time Deliveries", "Total Deliveries", "On-Time Delivery %",
        "Load Capacity Units", "Loads Delivered",
        "Driver Count", "Drivers Departed", "Driver Turnover %",
        "Incidents",
    ]
    ws_summary.append(summary_headers)

    for row in kpi_rows:
        total_deliveries = row.get("total_deliveries", 0) or 1
        driver_count = row.get("driver_count", 0) or 1
        otd_pct = round(row.get("on_time_deliveries", 0) / total_deliveries * 100, 2)
        turnover_pct = round(row.get("drivers_departed", 0) / driver_count * 100, 2)
        ws_summary.append([
            row.get("region_name"),
            row.get("period_label"),
            row.get("year"),
            row.get("month_name"),
            float(row.get("total_revenue", 0)),
            row.get("loaded_miles"),
            row.get("empty_miles"),
            row.get("total_miles"),
            float(row.get("fuel_cost", 0)),
            float(row.get("driver_cost", 0)),
            float(row.get("maintenance_cost", 0)),
            float(row.get("overhead_cost", 0)),
            float(row.get("total_cost", 0)),
            row.get("on_time_deliveries"),
            row.get("total_deliveries"),
            otd_pct,
            row.get("load_capacity_units"),
            row.get("loads_delivered"),
            row.get("driver_count"),
            row.get("drivers_departed"),
            turnover_pct,
            row.get("incidents"),
        ])

    # ── Sheet 2: Vehicle Performance ──────────────────────────────────────────
    ws_vehicle = wb.create_sheet("Vehicle Performance")
    vehicle_headers = [
        "Region", "Period", "Vehicle Type",
        "Total Miles", "Fuel Cost ($)",
        "On-Time Deliveries", "Total Deliveries", "On-Time Delivery %",
    ]
    ws_vehicle.append(vehicle_headers)

    for row in vehicle_rows:
        total_deliveries = row.get("total_deliveries", 0) or 1
        otd_pct = round(row.get("on_time_deliveries", 0) / total_deliveries * 100, 2)
        ws_vehicle.append([
            row.get("region_name"),
            row.get("period_label"),
            row.get("vehicle_type_name"),
            row.get("total_miles"),
            float(row.get("fuel_cost", 0)),
            row.get("on_time_deliveries"),
            row.get("total_deliveries"),
            otd_pct,
        ])

    # Write to bytes buffer
    buf = io.BytesIO()
    wb.save(buf)
    buf.seek(0)
    return buf.read()


@router.get("/exports", response_model=ExportResponse)
async def export_data(
    period: str = Query(..., description="Period key, e.g. May2025"),
    region: str = Query(..., description="Region name or 'All'"),
) -> ExportResponse:
    """
    Build a .xlsx data export for the given period and region.
    Uploads to Storage and returns a 1-hour SAS URL.
    """
    period_label = _parse_period_label(period)

    try:
        kpi_rows = _fetch_kpi_rows(period_label, region)
    except Exception as exc:
        logger.exception("Fabric SQL query failed: %s", exc)
        raise HTTPException(status_code=500, detail="Fabric SQL query failed") from exc

    if not kpi_rows:
        raise HTTPException(
            status_code=404,
            detail=f"No data found for period '{period_label}' and region '{region}'",
        )

    try:
        vehicle_rows = _fetch_vehicle_rows(period_label, region)
    except Exception as exc:
        logger.warning("Vehicle KPI query failed, continuing without vehicle sheet: %s", exc)
        vehicle_rows = []

    xlsx_bytes = _build_xlsx(kpi_rows, vehicle_rows)

    period_slug = period_label.replace(" ", "")
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    blob_path = f"{region}-{period_slug}-{timestamp}.xlsx"

    try:
        upload_blob("exports", blob_path, xlsx_bytes, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
        sas_url = get_blob_sas_url("exports", blob_path, expiry_hours=1)
    except Exception as exc:
        logger.exception("Storage upload or SAS generation failed: %s", exc)
        raise HTTPException(status_code=500, detail="Storage upload failed") from exc

    return ExportResponse(url=sas_url)
