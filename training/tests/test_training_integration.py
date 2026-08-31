"""Integration test: a real training run against a real (but local, throwaway)
MLflow instance - a sqlite-backed tracking store, which supports the Model
Registry the same way a full server does, just without needing a running
server process or network access. No cluster, no MinIO, no GitLab needed to
run this.

This is deliberately a small run (RUN_PARAMS trimmed to 2 combos instead of 5)
- the point is exercising the full path (train -> register -> tag -> Staging),
not reproducing the whole sweep.
"""

import importlib
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))


def test_full_training_run_registers_a_staging_version(tmp_path, monkeypatch):
    db_path = tmp_path / "mlflow.db"
    best_model_dir = tmp_path / "best_model"

    monkeypatch.setenv("MLFLOW_TRACKING_URI", f"sqlite:///{db_path}")
    monkeypatch.setenv("BEST_MODEL_DIR", str(best_model_dir))
    monkeypatch.setenv("MODEL_NAME", "test-iris-classifier")
    monkeypatch.setenv("CI_COMMIT_SHORT_SHA", "testsha1")
    monkeypatch.setenv("PUSHGATEWAY_ADDRESS", "localhost:1")  # deliberately unreachable

    import train_and_push

    importlib.reload(train_and_push)  # pick up the monkeypatched env vars
    # Small run instead of the full 5-combo sweep - this test is about
    # exercising register -> tag -> Staging, not the sweep itself.
    train_and_push.RUN_PARAMS = [
        {"C": 0.1, "max_iter": 100},
        {"C": 1.0, "max_iter": 100},
    ]

    train_and_push.main()

    from mlflow.tracking import MlflowClient

    client = MlflowClient(tracking_uri=f"sqlite:///{db_path}")
    versions = client.get_latest_versions("test-iris-classifier", stages=["Staging"])
    assert len(versions) == 1

    version = versions[0]
    assert version.tags["git_commit_sha"] == "testsha1"
    assert "dataset_version" in version.tags
    assert "artifact_sha256" in version.tags
    assert float(version.tags["accuracy"]) > 0.5  # sanity check, not a quality gate
