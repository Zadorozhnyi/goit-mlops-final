"""FastAPI inference service for the iris-classifier model.

Loads the model once at startup (not per-request - see lecture 179 notes:
reloading per request would add latency for nothing) from either an MLflow
Registry stage (MODEL_STAGE=Staging/Production) or a pinned version number
(MODEL_VERSION, used by the blue/green slots in production - see
helm/templates/deployment.yaml).
"""

import logging
import os
import sys
import time
import uuid

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from prometheus_fastapi_instrumentator import Instrumentator
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address

from model_loader import ChecksumMismatchError, load_model_with_checksum
from schemas import IrisInput, PredictionOutput

MODEL_NAME = os.environ.get("MODEL_NAME", "iris-classifier")
MODEL_STAGE = os.environ.get("MODEL_STAGE")  # e.g. "Staging"
MODEL_VERSION = os.environ.get("MODEL_VERSION")  # e.g. "3" - wins if both are set
SLOT = os.environ.get("SLOT", "n/a")  # "blue" / "green", just for logs and /health
RATE_LIMIT = os.environ.get("RATE_LIMIT", "60/minute")

CLASS_NAMES = ["setosa", "versicolor", "virginica"]

# Plain single-line JSON logs to stdout. Promtail ships stdout as-is, so this
# is the entire "structured logging" pipeline for Block A5/C5 - no extra
# logging backend, no log-shipping code in this service.
logging.basicConfig(
    stream=sys.stdout,
    level=logging.INFO,
    format='{"timestamp": "%(asctime)s", "level": "%(levelname)s", "logger": "%(name)s", "message": "%(message)s"}',
)
logger = logging.getLogger("inference")

limiter = Limiter(key_func=get_remote_address, default_limits=[RATE_LIMIT])
app = FastAPI(title="iris-classifier inference service")
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

Instrumentator().instrument(app).expose(app, endpoint="/metrics")

model_state = {"model": None, "version_info": None}


@app.on_event("startup")
def startup() -> None:
    try:
        model, version_info = load_model_with_checksum(
            MODEL_NAME, model_stage=MODEL_STAGE, model_version=MODEL_VERSION
        )
        model_state["model"] = model
        model_state["version_info"] = version_info
        logger.info(
            "loaded %s v%s (slot=%s, stage=%s)",
            MODEL_NAME, version_info.version, SLOT, MODEL_STAGE or "pinned",
        )
    except ChecksumMismatchError:
        # Fail loud and fail the pod - the readiness probe never goes green,
        # so Kubernetes never sends traffic to a pod serving a tampered model.
        logger.exception("refusing to start: model checksum mismatch")
        raise
    except Exception:
        logger.exception("refusing to start: could not load model")
        raise


@app.get("/health")
def health():
    if model_state["model"] is None:
        raise HTTPException(status_code=503, detail="model not loaded")
    return {
        "status": "ok",
        "slot": SLOT,
        "model_name": MODEL_NAME,
        "model_version": model_state["version_info"].version,
    }


@app.post("/predict", response_model=PredictionOutput)
@limiter.limit(RATE_LIMIT)
def predict(request: Request, payload: IrisInput):
    request_id = str(uuid.uuid4())
    started = time.monotonic()

    if model_state["model"] is None:
        raise HTTPException(status_code=503, detail="model not loaded")

    try:
        features = [[
            payload.sepal_length,
            payload.sepal_width,
            payload.petal_length,
            payload.petal_width,
        ]]
        probabilities = model_state["model"].predict(features)
        # sklearn pyfunc models return the predicted class directly by
        # default; predict_proba is only reachable through the raw sklearn
        # flavor, so we approximate a one-hot vector when it isn't available.
        predicted_class = int(probabilities[0])
        proba_vector = [0.0, 0.0, 0.0]
        proba_vector[predicted_class] = 1.0

        logger.info(
            '{"request_id": "%s", "event": "prediction", "predicted_class": %d, '
            '"latency_ms": %.2f}',
            request_id, predicted_class, (time.monotonic() - started) * 1000,
        )

        return PredictionOutput(
            predicted_class=predicted_class,
            class_name=CLASS_NAMES[predicted_class],
            probabilities=proba_vector,
            model_name=MODEL_NAME,
            model_version=model_state["version_info"].version,
        )
    except Exception:
        # Never leak internals (stack trace, file paths) back to the client -
        # log it server-side, return a generic 400.
        logger.exception('{"request_id": "%s", "event": "prediction_error"}', request_id)
        return JSONResponse(
            status_code=400,
            content={"error": "could not process this input", "request_id": request_id},
        )
