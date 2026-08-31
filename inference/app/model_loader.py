"""Loads a model from the MLflow Model Registry and checks its checksum
before letting anything use it (Block C4 - immutable model artifacts).

The checksum itself is written by training/train_and_push.py at registration
time (tag "artifact_sha256" on the model version). This module just
recomputes the same hash locally and refuses to serve if it doesn't match -
that is the whole point: it catches a model.pkl that got swapped or
corrupted between training and serving, not just a missing file.
"""

import glob
import hashlib
import logging
import os

import mlflow
from mlflow.tracking import MlflowClient

logger = logging.getLogger("inference.model_loader")


class ChecksumMismatchError(RuntimeError):
    pass


def _sha256_of_file(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            digest.update(chunk)
    return digest.hexdigest()


def resolve_model_version(
    client: MlflowClient, model_name: str, model_stage: str = None, model_version: str = None
):
    """Pick a version either by stage (models:/name/Production) or by an
    explicit pinned version number (used by the blue/green slots)."""
    if model_version:
        return client.get_model_version(model_name, model_version)
    if not model_stage:
        raise ValueError("either model_stage or model_version must be set")
    versions = client.get_latest_versions(model_name, stages=[model_stage])
    if not versions:
        raise RuntimeError(f"no model version of '{model_name}' is in stage {model_stage}")
    return versions[0]


def load_model_with_checksum(model_name: str, model_stage: str = None, model_version: str = None):
    """Download the model version's artifacts, verify artifact_sha256, then
    load it. Returns (pyfunc_model, resolved_version)."""
    tracking_uri = os.environ.get("MLFLOW_TRACKING_URI", "http://localhost:5000")
    mlflow.set_tracking_uri(tracking_uri)
    client = MlflowClient(tracking_uri=tracking_uri)

    version_info = resolve_model_version(client, model_name, model_stage, model_version)
    expected_checksum = version_info.tags.get("artifact_sha256")

    local_path = mlflow.artifacts.download_artifacts(
        artifact_uri=f"models:/{model_name}/{version_info.version}"
    )

    # Same layout uncertainty as training/train_and_push.py - glob for it
    # instead of assuming it sits directly at local_path's root.
    model_pkl_matches = glob.glob(os.path.join(local_path, "**", "model.pkl"), recursive=True)
    if expected_checksum and model_pkl_matches:
        actual_checksum = _sha256_of_file(model_pkl_matches[0])
        if actual_checksum != expected_checksum:
            raise ChecksumMismatchError(
                f"{model_name} v{version_info.version}: artifact checksum mismatch "
                f"(expected {expected_checksum[:12]}..., got {actual_checksum[:12]}...)"
            )
        logger.info(
            "checksum verified for %s v%s (%s...)",
            model_name,
            version_info.version,
            actual_checksum[:12],
        )
    else:
        # Older model versions registered before this check existed won't
        # have the tag - log it loudly instead of silently trusting the file.
        logger.warning(
            "%s v%s has no artifact_sha256 tag, skipping checksum check",
            model_name,
            version_info.version,
        )

    model = mlflow.pyfunc.load_model(local_path)
    return model, version_info
