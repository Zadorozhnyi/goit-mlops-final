FROM python:3.12-slim

WORKDIR /app

COPY app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app/*.py .

# Startup downloads the model from MLflow before the readiness probe can
# pass, which is why there is no HEALTHCHECK here - Kubernetes' own
# readiness/liveness probes (helm/templates/deployment.yaml) do that job and
# know to wait for it.
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
