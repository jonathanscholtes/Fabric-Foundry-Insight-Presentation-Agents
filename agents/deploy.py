"""Deploy LONGHAUL Foundry agents.

Creates or updates both agents in the Microsoft Foundry project.
Agent IDs are written to ``agents/agent_ids.json`` so deploy.ps1 /
GitHub Actions can inject them as environment variables on ca-mbr-api.

MCP URL resolution (in priority order)
---------------------------------------
1. --mcp-server-url        Explicit URL supplied by caller.
2. Foundry project connection named by --mcp-connection-name
   (default: "mbr-tools-mcp").  If the connection exists and has an
   endpoint, use it.
3. No MCP URL             Presentation agent is created without MCP
   tools; safe on first deploy — re-run once mbr-tools-mcp is up.

Fabric Data Agent URL resolution (in priority order)
-----------------------------------------------------
1. --fabric-data-agent-url  Explicit URL supplied by caller.
2. Key Vault secret 'fabric-data-agent-url' (--key-vault-uri).
3. Foundry connection named by --fabric-connection-name (default: da-mbr-trucking).

Usage:
    python agents/deploy.py \\
        --project-endpoint       <FOUNDRY_PROJECT_ENDPOINT> \\
        --model-deployment       gpt-4.1 \\
        [--mcp-server-url        https://<mbr-tools-mcp ACA internal FQDN>] \\
        [--mcp-connection-name   mbr-tools-mcp] \\
        [--fabric-data-agent-url https://api.fabric.microsoft.com/v1/workspaces/.../dataAgents/.../chat/completions] \\
        [--fabric-connection-name da-mbr-trucking] \\
        [--output agents/agent_ids.json]
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
from typing import Optional

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import (
    FabricDataAgentTool,
    MCPTool,
    PromptAgentDefinition,
)
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient

from agents import conversational_agent, mbr_presentation_agent

logging.basicConfig(level=logging.INFO, format="[%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)

AGENT_MODULES = [conversational_agent, mbr_presentation_agent]

DEFAULT_FABRIC_CONNECTION_NAME    = "da-mbr-trucking"
DEFAULT_MCP_CONNECTION_NAME       = "mbr-tools-mcp"
DEFAULT_MODEL_DEPLOYMENT          = "gpt-4.1"
DEFAULT_MINI_MODEL_DEPLOYMENT     = "gpt-4.1-mini"
KV_MCP_SECRET_NAME                = "mcp-server-url"
KV_FABRIC_AGENT_URL_SECRET        = "fabric-data-agent-url"
DEFAULT_OUTPUT_PATH               = os.path.join(os.path.dirname(__file__), "agent_ids.json")
KEEP_VERSIONS                     = 3


# ---------------------------------------------------------------------------
# MCP URL resolution
# ---------------------------------------------------------------------------

def _resolve_from_foundry_connection(
    project_client: AIProjectClient,
    connection_name: str,
) -> str:
    """Return the MCP endpoint stored in a Foundry project connection, or ''."""
    try:
        conn = project_client.connections.get(connection_name)
        url = (
            getattr(conn, "endpoint", None)
            or getattr(getattr(conn, "properties", None), "endpoint", None)
            or ""
        )
        if url:
            logger.info("MCP URL from Foundry connection '%s': %s", connection_name, url)
        return url.strip()
    except Exception as exc:
        logger.debug("Foundry connection '%s' not found: %s", connection_name, exc)
        return ""


def _resolve_from_key_vault(credential: DefaultAzureCredential, vault_uri: str) -> str:
    """Return the MCP endpoint stored in Key Vault secret 'mcp-server-url', or ''."""
    if not vault_uri:
        return ""
    try:
        kv = SecretClient(vault_url=vault_uri, credential=credential)
        secret = kv.get_secret(KV_MCP_SECRET_NAME)
        url = (secret.value or "").strip()
        if url:
            logger.info("MCP URL from Key Vault '%s': %s", vault_uri, url)
        return url
    except Exception as exc:
        logger.debug("Key Vault MCP secret not found (%s): %s", vault_uri, exc)
        return ""


def _resolve_fabric_url_from_key_vault(credential: DefaultAzureCredential, vault_uri: str) -> str:
    """Return the Fabric Data Agent URL stored in Key Vault secret 'fabric-data-agent-url', or ''."""
    if not vault_uri:
        return ""
    try:
        kv = SecretClient(vault_url=vault_uri, credential=credential)
        secret = kv.get_secret(KV_FABRIC_AGENT_URL_SECRET)
        url = (secret.value or "").strip()
        if url:
            logger.info("Fabric Data Agent URL from Key Vault '%s': %s", vault_uri, url)
        return url
    except Exception as exc:
        logger.debug("Key Vault Fabric Data Agent secret not found (%s): %s", vault_uri, exc)
        return ""


# ---------------------------------------------------------------------------
# Deployer
# ---------------------------------------------------------------------------

class AgentDeployer:
    """Create or update LONGHAUL agents in Microsoft Foundry."""

    def __init__(
        self,
        project_endpoint: str,
        model_deployment: str,
        mini_model_deployment: str,
        mcp_server_url: str,
        mcp_connection_name: str,
        key_vault_uri: str,
        fabric_data_agent_url: str = "",
        fabric_connection_name: str = DEFAULT_FABRIC_CONNECTION_NAME,
    ):
        self.model_deployment      = model_deployment
        self.mini_model_deployment = mini_model_deployment
        self.mcp_connection_name   = mcp_connection_name
        self.fabric_connection_name = fabric_connection_name
        self.key_vault_uri         = key_vault_uri.strip() if key_vault_uri else ""

        self.credential     = DefaultAzureCredential()
        self.project_client = AIProjectClient(
            endpoint=project_endpoint,
            credential=self.credential,
        )

        self.mcp_server_url       = self._resolve_mcp_url(mcp_server_url.strip() if mcp_server_url else "")
        self.fabric_data_agent_url = self._resolve_fabric_url(fabric_data_agent_url.strip() if fabric_data_agent_url else "")

    # ------------------------------------------------------------------
    # MCP URL resolution
    # ------------------------------------------------------------------

    def _resolve_mcp_url(self, explicit_url: str) -> str:
        if explicit_url:
            logger.info("MCP URL from --mcp-server-url: %s", explicit_url)
            return explicit_url

        url = _resolve_from_foundry_connection(self.project_client, self.mcp_connection_name)
        if url:
            return url

        url = _resolve_from_key_vault(self.credential, self.key_vault_uri)
        if url:
            return url

        logger.warning(
            "No MCP URL resolved. Presentation agent will be created WITHOUT MCP tools.\n"
            "  Re-run with --mcp-server-url once mbr-tools-mcp is deployed."
        )
        return ""

    def _resolve_fabric_url(self, explicit_url: str) -> str:
        if explicit_url:
            logger.info("Fabric Data Agent URL from --fabric-data-agent-url: %s", explicit_url)
            return explicit_url

        url = _resolve_fabric_url_from_key_vault(self.credential, self.key_vault_uri)
        if url:
            return url

        url = _resolve_from_foundry_connection(self.project_client, self.fabric_connection_name)
        if url:
            return url

        logger.warning(
            "No Fabric Data Agent URL resolved. Agents will use connection name '%s'.\n"
            "  Re-run with --fabric-data-agent-url once da_mbr_trucking is deployed.",
            self.fabric_connection_name,
        )
        return ""

    # ------------------------------------------------------------------
    # Tool builders
    # ------------------------------------------------------------------

    def _fabric_tool(self) -> Optional[FabricDataAgentTool]:
        if self.fabric_data_agent_url:
            logger.info("FabricDataAgentTool via URL: %s", self.fabric_data_agent_url)
            return FabricDataAgentTool(
                connection_name=self.fabric_connection_name,
            )
        logger.info("FabricDataAgentTool via connection name: %s", self.fabric_connection_name)
        return FabricDataAgentTool(connection_name=self.fabric_connection_name)

    def _mcp_tool(self, module) -> MCPTool:
        """Build an MCPTool for an agent module.

        require_approval="never" is required for automated pipelines —
        "always" (the default) blocks every call waiting for human approval.
        allowed_tools scopes the agent to only the tools it needs.
        """
        kwargs: dict = {
            "server_url":       self.mcp_server_url,
            "server_label":     "mbr-tools-mcp",
            "require_approval": getattr(module, "REQUIRE_APPROVAL", "never"),
        }
        allowed = getattr(module, "ALLOWED_TOOLS", None)
        if allowed:
            kwargs["allowed_tools"] = allowed
        return MCPTool(**kwargs)

    def _tools_for(self, module) -> list:
        tools: list = []
        fabric = self._fabric_tool()
        if fabric:
            tools.append(fabric)
        if getattr(module, "USES_MCP", False) and self.mcp_server_url:
            tools.append(self._mcp_tool(module))
            logger.info("MCPTool attached to %s (url=%s)", module.NAME, self.mcp_server_url)
        return tools

    # ------------------------------------------------------------------
    # Foundry CRUD
    # ------------------------------------------------------------------

    def _create_or_update(self, module) -> str:
        tier  = getattr(module, "MODEL_TIER", "full")
        model = self.mini_model_deployment if tier == "mini" else self.model_deployment

        tools      = self._tools_for(module)
        definition = PromptAgentDefinition(
            model=model,
            instructions=module.INSTRUCTIONS,
            tools=tools or None,
        )
        agent = self.project_client.agents.create_version(
            agent_name=module.NAME,
            definition=definition,
        )
        tool_names = ", ".join(type(t).__name__ for t in tools)
        logger.info("Created  %-40s id=%s  model=%s  tools=[%s]", module.NAME, agent.id, model, tool_names)

        self._prune_old_versions(module.NAME)
        return agent.id

    def _prune_old_versions(self, agent_name: str) -> None:
        try:
            versions = list(self.project_client.agents.list(agent_name=agent_name))
            versions.sort(key=lambda a: getattr(a, "version", 0), reverse=True)
            for old in versions[KEEP_VERSIONS:]:
                self.project_client.agents.delete_version(
                    agent_name=agent_name, version=old.version
                )
                logger.info("Pruned   %-40s version=%s", agent_name, old.version)
        except Exception as exc:
            logger.warning("Could not prune old versions of %s (non-fatal): %s", agent_name, exc)

    # ------------------------------------------------------------------
    # Entry point
    # ------------------------------------------------------------------

    def deploy(self) -> dict:
        ids: dict = {}
        for module in AGENT_MODULES:
            ids[module.NAME] = self._create_or_update(module)
        return ids


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Deploy LONGHAUL Foundry agents.")
    parser.add_argument("--project-endpoint",
                        default=os.environ.get("FOUNDRY_PROJECT_ENDPOINT"),
                        help="Foundry project endpoint URL")
    parser.add_argument("--model-deployment", default=DEFAULT_MODEL_DEPLOYMENT,
                        help=f"Full-tier model deployment name. Default: {DEFAULT_MODEL_DEPLOYMENT}")
    parser.add_argument("--mini-model-deployment", default=DEFAULT_MINI_MODEL_DEPLOYMENT,
                        help=f"Mini-tier model deployment name. Default: {DEFAULT_MINI_MODEL_DEPLOYMENT}")
    parser.add_argument("--key-vault-uri", default=os.environ.get("KEY_VAULT_URI", ""),
                        help="Key Vault URI for MCP URL fallback resolution.")
    parser.add_argument("--mcp-server-url", default=os.environ.get("MCP_SERVER_URL", ""),
                        help="Direct URL of the mbr-tools-mcp MCP server.")
    parser.add_argument("--mcp-connection-name", default=DEFAULT_MCP_CONNECTION_NAME,
                        help=f"Foundry connection name that stores the MCP URL. "
                             f"Default: {DEFAULT_MCP_CONNECTION_NAME}")
    parser.add_argument("--fabric-data-agent-url", default=os.environ.get("FABRIC_DATA_AGENT_URL", ""),
                        help="Direct chat/completions URL of the Fabric Data Agent (da_mbr_trucking). "
                             "Falls back to Key Vault secret 'fabric-data-agent-url', then Foundry connection.")
    parser.add_argument("--fabric-connection-name", default=DEFAULT_FABRIC_CONNECTION_NAME,
                        help=f"Foundry connection name for the Fabric Data Agent. "
                             f"Default: {DEFAULT_FABRIC_CONNECTION_NAME}")
    parser.add_argument("--output", default=DEFAULT_OUTPUT_PATH,
                        help="Path to write agent IDs as JSON.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    if not args.project_endpoint:
        raise SystemExit("--project-endpoint or FOUNDRY_PROJECT_ENDPOINT is required")

    ids = AgentDeployer(
        project_endpoint=args.project_endpoint,
        model_deployment=args.model_deployment,
        mini_model_deployment=args.mini_model_deployment,
        mcp_server_url=args.mcp_server_url,
        mcp_connection_name=args.mcp_connection_name,
        key_vault_uri=args.key_vault_uri,
        fabric_data_agent_url=args.fabric_data_agent_url,
        fabric_connection_name=args.fabric_connection_name,
    ).deploy()

    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(ids, f, indent=2)
    logger.info("Wrote %d agent IDs to %s", len(ids), args.output)

    # Print individual IDs for backward compat with deploy.ps1 stdout parsing
    for name, agent_id in ids.items():
        print(f"{name.upper().replace('-', '_')}_ID={agent_id}")


if __name__ == "__main__":
    main()
