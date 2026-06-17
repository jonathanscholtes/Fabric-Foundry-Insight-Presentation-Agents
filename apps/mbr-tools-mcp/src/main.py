"""FastMCP tool server for LONGHAUL MBR — PowerPoint generation and deck library.

Runs on ACA internal ingress (port 8080). Accessible only by Foundry agents.

Tools:
  - get_template_slides   (read)   — pre-rendered template slide thumbnails
  - fill_mbr_template     (write)  — fill pptx template + upload deck + generate thumbnails
  - get_mbr_deck_url      (read)   — SAS URL for a completed deck
  - list_mbr_decks        (read)   — list generated decks from metadata blobs
"""

from __future__ import annotations

import logging
import os

from fastmcp import FastMCP

from .tools.powerpoint_tools import register_powerpoint_tools
from .tools.library_tools import register_library_tools

logging.basicConfig(level=logging.INFO, format="[%(levelname)s] %(name)s: %(message)s")
logger = logging.getLogger("mbr-tools-mcp")

mcp = FastMCP("mbr-tools")

register_powerpoint_tools(mcp)
register_library_tools(mcp)


def main() -> None:
    host = os.environ.get("HOST", "0.0.0.0")
    port = int(os.environ.get("PORT", "8080"))
    logger.info("Starting FastMCP server on %s:%s", host, port)
    mcp.run(transport="streamable-http", host=host, port=port)


if __name__ == "__main__":
    main()
