"""KPI endpoint — queries Fabric Lakehouse and returns KPI payload."""

from __future__ import annotations

import logging

from fastapi import APIRouter, HTTPException, Query

from ..fabric import get_kpis
from ..models import KpiPayload

logger = logging.getLogger("mbr-api.routes.kpis")

router = APIRouter()


@router.get("/kpis", response_model=KpiPayload)
async def get_kpi_summary(
    period: str = Query(..., description="Period key, e.g. May2025"),
    region: str = Query(..., description="Region name or 'All'"),
) -> KpiPayload:
    """
    Fetch current-period KPI values and MoM deltas for the KPI Summary Bar.
    Queries the Fabric Lakehouse SQL endpoint via Managed Identity.
    """
    try:
        data = get_kpis(period, region)
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except Exception as exc:
        logger.exception("Fabric SQL connection failed: %s", exc)
        raise HTTPException(status_code=500, detail="Fabric SQL connection failed") from exc

    return KpiPayload(**data)
