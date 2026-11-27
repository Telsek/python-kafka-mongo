FROM python:3.13-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
# installs the tracers for the libraries found (fastapi, kafka, urllib)
RUN opentelemetry-bootstrap -a install
# COPY app.py index.html .
COPY app.py index.html ./
# exporting off by default (local compose) - the Helm chart turns it on and points it at SigNoz
ENV OTEL_SERVICE_NAME=client \
    OTEL_TRACES_EXPORTER=none \
    OTEL_METRICS_EXPORTER=none \
    OTEL_LOGS_EXPORTER=none
# CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
CMD ["opentelemetry-instrument", "uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]