# PowerPoint Templates

Place your MBR PowerPoint template here before deploying.

## Expected file

`data/templates/longhaul-mbr-template.pptx`

The mbr-tools-mcp `fill_mbr_template` MCP tool reads this file from Azure Blob
Storage (`templates/longhaul-mbr-template.pptx`). Upload it using:

```bash
az storage blob upload \
    --account-name <storage-account> \
    --container-name templates \
    --name longhaul-mbr-template.pptx \
    --file data/templates/longhaul-mbr-template.pptx \
    --auth-mode login
```

## Slide design conventions

The template must use **python-pptx text placeholder names** that match the
keys the MBR Presentation Agent passes to `fill_mbr_template`:

| Placeholder name | Content |
|---|---|
| `title` | `LONGHAUL MBR — {Region} — {Period}` |
| `period` | Period label (e.g. "May 2025") |
| `region` | Region name (e.g. "North") |
| `total_revenue` | Formatted revenue string |
| `total_cost` | Formatted cost string |
| `operating_ratio` | Operating ratio percentage |
| `on_time_pct` | On-time delivery percentage |
| `fleet_utilization` | Fleet utilization percentage |
| `narrative` | Conversational agent narrative block |
| `key_drivers` | Bullet list of key drivers |

To add a text placeholder in PowerPoint:
1. Insert → Text Box → draw the box
2. Selection Pane (Home → Arrange → Selection Pane) → rename the shape to the
   placeholder name above

Shapes without matching names are left unchanged.
