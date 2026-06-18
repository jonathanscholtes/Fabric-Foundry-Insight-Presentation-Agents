"""Application configuration loaded from environment variables."""

from __future__ import annotations

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # Fabric SQL endpoint
    FABRIC_SQL_SERVER: str = ""
    FABRIC_SQL_DATABASE: str = "lh_mbr_trucking"

    # Azure Storage
    STORAGE_ACCOUNT_URL: str = ""

    # Azure AI Foundry
    FOUNDRY_PROJECT_ENDPOINT: str = ""
    CONVERSATIONAL_AGENT_ID: str = ""
    MBR_PRESENTATION_AGENT_ID: str = ""

    # Managed Identity client ID (injected by ACA)
    AZURE_CLIENT_ID: str = ""

    # Observability
    APPLICATIONINSIGHTS_CONNECTION_STRING: str = ""

    # CORS
    CORS_ALLOW_ORIGIN: str = "*"

    class Config:
        env_file = ".env"


settings = Settings()
