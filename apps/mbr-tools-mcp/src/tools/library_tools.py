"""MCP tool: list_mbr_decks — enumerate generated deck metadata blobs."""

from __future__ import annotations

import json
import logging

from azure.identity import ManagedIdentityCredential, DefaultAzureCredential
from azure.storage.blob import BlobServiceClient

from ..config import settings

logger = logging.getLogger("mbr-tools-mcp.library")


def _get_blob_client() -> BlobServiceClient:
    credential = (
        ManagedIdentityCredential(client_id=settings.AZURE_CLIENT_ID)
        if settings.AZURE_CLIENT_ID
        else DefaultAzureCredential()
    )
    return BlobServiceClient(account_url=settings.STORAGE_ACCOUNT_URL, credential=credential)


def register_library_tools(mcp) -> None:

    @mcp.tool()
    def list_mbr_decks(region: str | None = None, period: str | None = None) -> list[dict]:
        """List previously generated MBR decks from deck metadata blobs.

        Args:
            region: Optional region filter (e.g. "Southwest").
            period: Optional period filter (e.g. "May 2025").

        Returns:
            List of deck summary dicts: {deck_id, period, region, generated_at}.
        """
        client = _get_blob_client()
        container = client.get_container_client("decks-metadata")

        decks: list[dict] = []
        for blob in container.list_blobs():
            try:
                data = container.download_blob(blob.name).readall()
                meta = json.loads(data)
                if region and meta.get("region") != region:
                    continue
                if period and meta.get("period") != period:
                    continue
                decks.append({
                    "deck_id":      meta.get("deck_id", ""),
                    "period":       meta.get("period", ""),
                    "region":       meta.get("region", ""),
                    "generated_at": meta.get("generated_at", ""),
                })
            except Exception as exc:
                logger.warning("Skipping blob %s: %s", blob.name, exc)

        decks.sort(key=lambda d: d.get("generated_at", ""), reverse=True)
        return decks
