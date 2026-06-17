# Template Thumbnails

Static PNG thumbnail images for the template preview in the UI.

## Naming convention

```
thumbnails/templates/<template-name>/slide-01.png
thumbnails/templates/<template-name>/slide-02.png
...
```

These are uploaded to Azure Blob Storage at the same path under the
`thumbnails` container.

## How to generate

LibreOffice headless is only available in the `mbr-tools-mcp` container at
runtime.  For local generation:

```bash
libreoffice --headless --convert-to png --outdir ./out data/templates/longhaul-mbr-template.pptx
```

Rename the output files to `slide-01.png`, `slide-02.png`, etc., then upload:

```bash
az storage blob upload-batch \
    --account-name <storage-account> \
    --source ./out \
    --destination thumbnails/templates/longhaul-mbr-template \
    --auth-mode login
```

The UI's `PresentationPanel` renders these thumbnails to give users a visual
preview of the template before they trigger generation.

If no thumbnails are uploaded, the panel shows empty placeholder boxes — the
Generate button still works.
