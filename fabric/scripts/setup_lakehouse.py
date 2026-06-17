"""Ensure the OneLake staging folder exists for the LONGHAUL Lakehouse.

The Fabric Lakehouse SQL analytics endpoint is read-only. Tables are created by
the seed_data.py script via the Fabric Load Tables API. This script just verifies
OneLake connectivity and creates the staging folder used by seed_data.py.

Usage:
    python fabric/scripts/setup_lakehouse.py \\
        --workspace-id <workspace-guid> \\
        --lakehouse-id <lakehouse-guid>
"""

from __future__ import annotations

import argparse
import logging

from azure.identity import DefaultAzureCredential
from azure.storage.filedatalake import DataLakeServiceClient

logging.basicConfig(level=logging.INFO, format="[%(levelname)s] %(message)s")
log = logging.getLogger("setup_lakehouse")

STAGING_FOLDER = "Files/staging"


def main(workspace_id: str, lakehouse_id: str) -> None:
    credential = DefaultAzureCredential()
    client = DataLakeServiceClient(
        account_url="https://onelake.dfs.fabric.microsoft.com",
        credential=credential,
    )

    fs = client.get_file_system_client(workspace_id)
    dir_path = f"{lakehouse_id}/{STAGING_FOLDER}"
    dir_client = fs.get_directory_client(dir_path)

    if not dir_client.exists():
        dir_client.create_directory()
        log.info("Created staging folder: %s", dir_path)
    else:
        log.info("Staging folder exists: %s", dir_path)

    log.info("OneLake connectivity verified.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--workspace-id", required=True)
    parser.add_argument("--lakehouse-id", required=True)
    parser.add_argument("--sql-server", default="")  # retained for CLI compatibility
    args = parser.parse_args()
    main(args.workspace_id, args.lakehouse_id)
