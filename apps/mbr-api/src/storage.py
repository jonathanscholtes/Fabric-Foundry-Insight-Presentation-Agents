"""Azure Blob Storage helpers for mbr-api."""

from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone
from typing import Optional

from azure.identity import ManagedIdentityCredential
from azure.storage.blob import (
    BlobServiceClient,
    BlobSasPermissions,
    UserDelegationKey,
    generate_blob_sas,
)

from .config import settings

logger = logging.getLogger("mbr-api.storage")

_blob_client: Optional[BlobServiceClient] = None


def _get_blob_service_client() -> BlobServiceClient:
    """Return a cached BlobServiceClient using Managed Identity."""
    global _blob_client
    if _blob_client is None:
        credential = ManagedIdentityCredential(
            client_id=settings.AZURE_CLIENT_ID if settings.AZURE_CLIENT_ID else None
        )
        _blob_client = BlobServiceClient(
            account_url=settings.STORAGE_ACCOUNT_URL,
            credential=credential,
        )
    return _blob_client


def get_blob_sas_url(container: str, blob_path: str, expiry_hours: int = 1) -> str:
    """Generate a user-delegation SAS URL for the given blob."""
    client = _get_blob_service_client()

    expiry = datetime.now(timezone.utc) + timedelta(hours=expiry_hours)
    start = datetime.now(timezone.utc) - timedelta(minutes=5)

    # Request a user delegation key valid for the SAS window
    user_delegation_key: UserDelegationKey = client.get_user_delegation_key(
        key_start_time=start,
        key_expiry_time=expiry,
    )

    # Extract the storage account name from the account URL
    # e.g. https://<account>.blob.core.windows.net  →  <account>
    account_name = settings.STORAGE_ACCOUNT_URL.split("//")[1].split(".")[0]

    sas_token = generate_blob_sas(
        account_name=account_name,
        container_name=container,
        blob_name=blob_path,
        user_delegation_key=user_delegation_key,
        permission=BlobSasPermissions(read=True),
        expiry=expiry,
        start=start,
    )

    return f"{settings.STORAGE_ACCOUNT_URL}/{container}/{blob_path}?{sas_token}"


def upload_blob(
    container: str,
    blob_path: str,
    data: bytes,
    content_type: str,
) -> None:
    """Upload bytes to the specified container and blob path."""
    client = _get_blob_service_client()
    blob_client = client.get_blob_client(container=container, blob=blob_path)
    blob_client.upload_blob(data, overwrite=True, content_settings=_content_settings(content_type))
    logger.info("Uploaded blob: %s/%s (%d bytes)", container, blob_path, len(data))


def _content_settings(content_type: str):
    from azure.storage.blob import ContentSettings
    return ContentSettings(content_type=content_type)


def list_blobs(container: str, prefix: str) -> list[str]:
    """Return a list of blob names in the container matching the given prefix."""
    client = _get_blob_service_client()
    container_client = client.get_container_client(container)
    blobs = container_client.list_blobs(name_starts_with=prefix)
    return [blob.name for blob in blobs]


def read_blob(container: str, blob_path: str) -> bytes:
    """Download and return the raw bytes of the specified blob."""
    client = _get_blob_service_client()
    blob_client = client.get_blob_client(container=container, blob=blob_path)
    stream = blob_client.download_blob()
    return stream.readall()
