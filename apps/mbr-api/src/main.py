"""FastAPI entry point for mbr-api."""

from __future__ import annotations

import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .config import settings
from .routes.health import router as health_router
from .routes.kpis import router as kpis_router
from .routes.templates import router as templates_router
from .routes.analytics import router as analytics_router
from .routes.conversations import router as conversations_router
from .routes.presentations import router as presentations_router
from .routes.downloads import router as downloads_router

logging.basicConfig(level=logging.INFO, format="[%(levelname)s] %(name)s: %(message)s")
logger = logging.getLogger("mbr-api")

app = FastAPI(title="mbr-api", description="LONGHAUL MBR AI Agents REST API")

# ── CORS — must be added before any routes ────────────────────────────────────
app.add_middleware(
    CORSMiddleware,
    allow_origins=[settings.CORS_ALLOW_ORIGIN],
    allow_methods=["GET", "POST"],
    allow_headers=["Content-Type"],
    max_age=3600,
)

# ── Routers ───────────────────────────────────────────────────────────────────
app.include_router(health_router)
app.include_router(kpis_router)
app.include_router(analytics_router)
app.include_router(templates_router)
app.include_router(conversations_router)
app.include_router(presentations_router)
app.include_router(downloads_router)


# ── Startup: initialise Foundry client ───────────────────────────────────────
@app.on_event("startup")
async def startup() -> None:
    """Initialise the Azure AI Projects client and store it on app.state."""
    if not settings.FOUNDRY_PROJECT_ENDPOINT:
        logger.warning(
            "FOUNDRY_PROJECT_ENDPOINT is not set — Foundry client will not be initialised. "
            "Conversation and presentation endpoints will fail."
        )
        app.state.foundry_client = None
        return

    try:
        from azure.ai.projects import AIProjectClient
        from azure.identity import ManagedIdentityCredential

        credential = ManagedIdentityCredential(
            client_id=settings.AZURE_CLIENT_ID if settings.AZURE_CLIENT_ID else None
        )
        app.state.foundry_client = AIProjectClient(
            endpoint=settings.FOUNDRY_PROJECT_ENDPOINT,
            credential=credential,
        )
        logger.info(
            "Foundry client initialised for endpoint: %s", settings.FOUNDRY_PROJECT_ENDPOINT
        )
    except Exception as exc:
        logger.exception("Failed to initialise Foundry client: %s", exc)
        app.state.foundry_client = None
