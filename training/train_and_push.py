"""Train Iris LogisticRegression runs, track them in MLflow, register the best
one in the Model Registry, and tag it with everything the rest of the platform
needs to trust it (git commit, dataset version, artifact checksum).

This builds on goit-mlops-hw-09/experiments/train_and_push.py - same sweep,
same PushGateway push - plus the Model Registry piece the final project asks
for (Block B1).
"""

import glob
import hashlib
import os
import shutil
import subprocess

import mlflow
import mlflow.sklearn
from mlflow.tracking import MlflowClient
from prometheus_client import CollectorRegistry, Gauge, push_to_gateway
from sklearn.datasets import load_iris
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, log_loss
from sklearn.model_selection import train_test_split

MLFLOW_TRACKING_URI = os.environ.get("MLFLOW_TRACKING_URI", "http://localhost:5000")
PUSHGATEWAY_ADDRESS = os.environ.get("PUSHGATEWAY_ADDRESS", "localhost:9091")
EXPERIMENT_NAME = "iris-logistic-regression"
REGISTERED_MODEL_NAME = os.environ.get("MODEL_NAME", "iris-classifier")
BEST_MODEL_DIR = os.path.join(os.path.dirname(__file__), "..", "best_model")

# (C, max_iter) combinations to sweep over.
RUN_PARAMS = [
    {"C": 0.01, "max_iter": 100},
    {"C": 0.1, "max_iter": 100},
    {"C": 1.0, "max_iter": 200},
    {"C": 10.0, "max_iter": 200},
    {"C": 100.0, "max_iter": 300},
]


def push_metrics(run_id: str, accuracy: float, loss: float) -> None:
    registry = CollectorRegistry()
    accuracy_gauge = Gauge(
        "mlflow_accuracy", "Accuracy of the MLflow run", ["run_id"], registry=registry
    )
    loss_gauge = Gauge(
        "mlflow_loss", "Log loss of the MLflow run", ["run_id"], registry=registry
    )
    accuracy_gauge.labels(run_id=run_id).set(accuracy)
    loss_gauge.labels(run_id=run_id).set(loss)
    push_to_gateway(PUSHGATEWAY_ADDRESS, job="train_and_push", registry=registry)


def get_git_commit_sha() -> str:
    # GitLab CI sets this for us; fall back to asking git directly for local runs.
    env_sha = os.environ.get("CI_COMMIT_SHORT_SHA")
    if env_sha:
        return env_sha
    try:
        return (
            subprocess.check_output(["git", "rev-parse", "--short", "HEAD"])
            .decode()
            .strip()
        )
    except Exception:
        return "unknown"


def get_dataset_version(X, y) -> str:
    # Iris ships as an array, not a file, so there is no natural file hash.
    # Hashing the raw bytes gives the same kind of guarantee: if the dataset
    # ever changes, this value changes with it.
    digest = hashlib.sha256()
    digest.update(X.tobytes())
    digest.update(y.tobytes())
    return digest.hexdigest()[:12]


def sha256_of_file(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    mlflow.set_tracking_uri(MLFLOW_TRACKING_URI)
    mlflow.set_experiment(EXPERIMENT_NAME)

    X, y = load_iris(return_X_y=True)
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )

    git_sha = get_git_commit_sha()
    dataset_version = get_dataset_version(X, y)

    best_run_id = None
    best_accuracy = -1.0

    for params in RUN_PARAMS:
        with mlflow.start_run() as run:
            model = LogisticRegression(C=params["C"], max_iter=params["max_iter"])
            model.fit(X_train, y_train)

            y_pred = model.predict(X_test)
            y_proba = model.predict_proba(X_test)
            accuracy = accuracy_score(y_test, y_pred)
            loss = log_loss(y_test, y_proba)

            mlflow.log_params(params)
            mlflow.set_tag("git_commit_sha", git_sha)
            mlflow.set_tag("dataset_version", dataset_version)
            mlflow.log_metric("accuracy", accuracy)
            mlflow.log_metric("loss", loss)
            mlflow.sklearn.log_model(model, name="model")

            push_metrics(run.info.run_id, accuracy, loss)

            print(
                f"run_id={run.info.run_id} C={params['C']} max_iter={params['max_iter']} "
                f"accuracy={accuracy:.4f} loss={loss:.4f}"
            )

            if accuracy > best_accuracy:
                best_accuracy = accuracy
                best_run_id = run.info.run_id

    print(f"\nBest run: {best_run_id} (accuracy={best_accuracy:.4f})")

    best_model_uri = f"runs:/{best_run_id}/model"
    if os.path.exists(BEST_MODEL_DIR):
        shutil.rmtree(BEST_MODEL_DIR)
    mlflow.artifacts.download_artifacts(artifact_uri=best_model_uri, dst_path=BEST_MODEL_DIR)
    print(f"Best model copied to {BEST_MODEL_DIR}")

    # Register the best run as a new model version. Every run already carries
    # git_commit_sha/dataset_version as tags (see above); this just makes the
    # winning one addressable by name/version instead of by run_id.
    client = MlflowClient()
    model_version = mlflow.register_model(model_uri=best_model_uri, name=REGISTERED_MODEL_NAME)
    print(f"Registered {REGISTERED_MODEL_NAME} version {model_version.version}")

    # download_artifacts nests the file under a "model/" subfolder when a
    # dst_path is given (it keeps the artifact_path's own name) - glob
    # instead of hardcoding the path so this doesn't break if that changes.
    model_pkl_matches = glob.glob(os.path.join(BEST_MODEL_DIR, "**", "model.pkl"), recursive=True)
    if not model_pkl_matches:
        raise FileNotFoundError(f"no model.pkl found under {BEST_MODEL_DIR}")
    artifact_checksum = sha256_of_file(model_pkl_matches[0])

    client.set_model_version_tag(
        REGISTERED_MODEL_NAME, model_version.version, "git_commit_sha", git_sha
    )
    client.set_model_version_tag(
        REGISTERED_MODEL_NAME, model_version.version, "dataset_version", dataset_version
    )
    client.set_model_version_tag(
        REGISTERED_MODEL_NAME, model_version.version, "artifact_sha256", artifact_checksum
    )
    client.set_model_version_tag(
        REGISTERED_MODEL_NAME, model_version.version, "accuracy", f"{best_accuracy:.4f}"
    )

    # New versions always start in Staging - promotion to Production is a
    # separate, deliberate action (see scripts/promote_model.py, Block B2).
    # transition_model_version_stage is the classic Model Registry stage API;
    # it is what the course lectures (166-168) use, so we stick with it even
    # though newer MLflow docs point toward registry aliases instead.
    client.transition_model_version_stage(
        name=REGISTERED_MODEL_NAME,
        version=model_version.version,
        stage="Staging",
        archive_existing_versions=False,
    )
    print(
        f"{REGISTERED_MODEL_NAME} v{model_version.version} -> Staging "
        f"(git={git_sha}, dataset={dataset_version}, sha256={artifact_checksum[:12]}...)"
    )


if __name__ == "__main__":
    main()
