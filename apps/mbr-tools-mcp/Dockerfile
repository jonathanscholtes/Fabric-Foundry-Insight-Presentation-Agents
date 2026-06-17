FROM python:3.12-slim

# LibreOffice for converting completed .pptx slides to PNG thumbnails.
# Installed only in mbr-tools-api — not needed in mbr-api.
RUN apt-get update && apt-get install -y \
        libreoffice-impress \
        --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY pyproject.toml ./
RUN pip install --no-cache-dir -e .

COPY src/ ./src/

ENV HOST=0.0.0.0
ENV PORT=8080

EXPOSE 8080

CMD ["python", "-m", "src.main"]
