FROM python:3.12-slim

WORKDIR /app

# Pull in patched OS packages (openssl, etc.) - the base image is only
# rebuilt occasionally, so without this Trivy flags Debian CVEs that
# already have a fix published upstream.
RUN apt-get update && apt-get upgrade -y && rm -rf /var/lib/apt/lists/*

COPY app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app/*.py .

# Startup downloads the model from MLflow before the readiness probe can
# pass, which is why there is no HEALTHCHECK here - Kubernetes' own
# readiness/liveness probes (helm/templates/deployment.yaml) do that job and
# know to wait for it.
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
