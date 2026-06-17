"""Templates endpoint — returns slide thumbnail SAS URLs for a named template."""

from __future__ import annotations

import logging
import re

from fastapi import APIRouter, HTTPException

from ..models import SlideThumb
from ..storage import get_blob_sas_url, list_blobs

logger = logging.getLogger("mbr-api.routes.templates")

router = APIRouter()

# Human-readable slide titles keyed by zero-padded slide number string
_SLIDE_TITLES: dict[str, str] = {
    "01": "Title",
    "02": "Executive Summary",
    "03": "Regional Performance",
    "04": "Fleet Efficiency",
    "05": "Driver Performance",
    "06": "Bottom Line",
}


@router.get("/templates/{template_name}/slides", response_model=list[SlideThumb])
async def get_template_slides(template_name: str) -> list[SlideThumb]:
    """
    Return pre-rendered slide thumbnails for the named template.
    Reads from the thumbnails Storage container.
    """
    prefix = f"templates/{template_name}/"
    try:
        blob_names = list_blobs("thumbnails", prefix)
    except Exception as exc:
        logger.exception("Storage list_blobs failed: %s", exc)
        raise HTTPException(status_code=500, detail="Storage access failed") from exc

    if not blob_names:
        raise HTTPException(
            status_code=404,
            detail=f"No thumbnails found for template '{template_name}'",
        )

    slides: list[SlideThumb] = []
    for blob_name in blob_names:
        # blob_name format: templates/<template_name>/slide-NN.png
        filename = blob_name.rsplit("/", 1)[-1]  # e.g. slide-01.png
        match = re.search(r"slide-(\d+)", filename)
        if not match:
            continue

        num_str = match.group(1).zfill(2)
        slide_number = int(num_str)
        title = _SLIDE_TITLES.get(num_str, f"Slide {slide_number}")

        try:
            sas_url = get_blob_sas_url("thumbnails", blob_name, expiry_hours=1)
        except Exception as exc:
            logger.warning("Failed to generate SAS URL for %s: %s", blob_name, exc)
            continue

        slides.append(
            SlideThumb(slide_number=slide_number, title=title, thumbnail_url=sas_url)
        )

    # Sort by slide number ascending
    slides.sort(key=lambda s: s.slide_number)
    return slides
