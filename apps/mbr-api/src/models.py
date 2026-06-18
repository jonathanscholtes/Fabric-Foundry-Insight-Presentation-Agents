"""Pydantic v2 request/response models for mbr-api."""

from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel


# ── KPI models ────────────────────────────────────────────────────────────────

class KpiMetric(BaseModel):
    value: float
    delta_pct: float | None = None
    delta_pp: float | None = None
    direction: Literal["up", "down", "flat"] = "flat"


class KpiPayload(BaseModel):
    period: str
    region: str
    total_revenue: KpiMetric
    total_miles: KpiMetric
    empty_miles_pct: KpiMetric
    operating_margin_pct: KpiMetric
    cost_per_mile: KpiMetric
    on_time_delivery_pct: KpiMetric


# ── Template slide thumbnails ─────────────────────────────────────────────────

class SlideThumb(BaseModel):
    slide_number: int
    title: str
    thumbnail_url: str


# ── Conversation models ───────────────────────────────────────────────────────

class ConversationRequest(BaseModel):
    thread_id: str
    message: str
    period: str
    region: str


class KeyDriver(BaseModel):
    label: str
    value: str
    direction: Literal["positive", "negative", "neutral"]


class RevenuePerformanceData(BaseModel):
    chart_type: str = "line"
    data: list[dict[str, Any]] = []


class CostManagementData(BaseModel):
    narrative: str = ""


class OperationalEfficiencyData(BaseModel):
    chart_type: str = "donut"
    value: float = 0.0


class ServicePerformanceData(BaseModel):
    chart_type: str = "bar"
    data: list[dict[str, Any]] = []


class BottomLineData(BaseModel):
    narrative: str = ""


class AnalyticsPayload(BaseModel):
    revenue_performance: RevenuePerformanceData = RevenuePerformanceData()
    cost_management: CostManagementData = CostManagementData()
    operational_efficiency: OperationalEfficiencyData = OperationalEfficiencyData()
    service_performance: ServicePerformanceData = ServicePerformanceData()
    bottom_line: BottomLineData = BottomLineData()


class ConversationResponse(BaseModel):
    thread_id: str
    narrative: str
    key_drivers: list[KeyDriver] = []
    analytics: AnalyticsPayload = AnalyticsPayload()


# ── Presentation models ───────────────────────────────────────────────────────

class PresentationRequest(BaseModel):
    period: str
    region: str


class PresentationResponse(BaseModel):
    deck_id: str
    period: str
    region: str
    generated_at: str
    deck_url: str = ""
    thumbnail_urls: list[str] = []


class DeckSummary(BaseModel):
    deck_id: str
    period: str
    region: str
    generated_at: str


# ── Conversation history models ───────────────────────────────────────────────

class ThreadSummary(BaseModel):
    thread_id: str
    period: str
    region: str
    first_message: str
    turn_count: int
    last_updated: str


class ConversationTurn(BaseModel):
    timestamp: str
    user_message: str
    agent_response: dict[str, Any]


# ── Export/Download models ────────────────────────────────────────────────────

class ExportResponse(BaseModel):
    url: str


class DownloadResponse(BaseModel):
    url: str
