"""Utility helpers for mbr-api."""

from __future__ import annotations

import json

_EMPTY_ANALYTICS = {
    "revenue_performance": {"chart_type": "line", "data": []},
    "cost_management": {"narrative": ""},
    "operational_efficiency": {"chart_type": "donut", "value": 0},
    "service_performance": {"chart_type": "bar", "data": []},
    "bottom_line": {"narrative": ""},
}


def parse_agent_json(text: str) -> dict:
    """
    Parse the agent's text response as JSON.

    Strips markdown code fences if present. Falls back to a structured
    plain-text wrapper if JSON parsing fails.
    """
    cleaned = text.strip()
    if cleaned.startswith("```"):
        # Remove opening fence line
        cleaned = cleaned.split("```")[1]
        if cleaned.startswith("json"):
            cleaned = cleaned[4:]
        cleaned = cleaned.strip()
        # Remove trailing fence if present
        if cleaned.endswith("```"):
            cleaned = cleaned[:-3].strip()

    try:
        return json.loads(cleaned)
    except json.JSONDecodeError:
        # Fallback: wrap plain text in the expected schema
        return {
            "narrative": text,
            "key_drivers": [],
            "analytics": _EMPTY_ANALYTICS,
        }
