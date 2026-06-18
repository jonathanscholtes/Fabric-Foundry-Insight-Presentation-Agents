"""Analytics endpoint — revenue trend, fleet efficiency, cost breakdown."""

from __future__ import annotations

import logging

from fastapi import APIRouter, HTTPException, Query

from ..fabric import get_analytics

logger = logging.getLogger("mbr-api.routes.analytics")

router = APIRouter()


@router.get("/analytics")
async def analytics(
    period: str = Query(..., description="Period label, e.g. 'May 2025'"),
    region: str = Query(..., description="Region name, e.g. 'North' or 'All'"),
) -> dict:
    """
    Return analytics data for the given period and region:
    revenue trend, fleet efficiency metrics, cost breakdown,
    on-time by vehicle type, and bottom-line narrative.
    """
    try:
        return get_analytics(period, region)
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except Exception as exc:
        logger.exception("Analytics query failed: %s", exc)
        raise HTTPException(status_code=500, detail="Analytics query failed") from exc
