FROM ghcr.io/cirruslabs/flutter:stable AS web-builder
WORKDIR /src
COPY frontend/pubspec.yaml frontend/pubspec.lock ./
RUN flutter pub get
COPY frontend/ ./
RUN flutter build web --release --pwa-strategy=none --dart-define=API_URL=

FROM python:3.13-slim
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app/backend \
    WEB_DIST=/app/web
WORKDIR /app
COPY backend/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt
COPY backend/ /app/backend/
COPY scripts/ /app/scripts/
COPY data/ /app/data/
COPY --from=web-builder /src/build/web /app/web
CMD ["sh", "-c", "uvicorn app.main:app --app-dir backend --host 0.0.0.0 --port ${PORT:-8000} & python scripts/bootstrap_cloud.py && wait"]
