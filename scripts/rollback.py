#!/usr/bin/env python3
"""Roll back Production to the previously Archived version - the one command
Block B4 asks for.

It only looks at Archived versions, so by default it picks the highest
version number currently sitting in Archived, which (since promote_model.py
always archives whatever it just replaced) is the one that was running in
Production right before the last promotion.

Usage:
    python rollback.py --model iris-classifier
"""

import argparse
import os
import sys

from mlflow.tracking import MlflowClient

sys.path.insert(0, os.path.dirname(__file__))
from registry_audit import log_audit_event  # noqa: E402


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", required=True, help="Registered model name")
    parser.add_argument(
        "--to-version",
        help="Roll back to this exact version instead of auto-picking the last Archived one",
    )
    args = parser.parse_args()

    mlflow_tracking_uri = os.environ.get("MLFLOW_TRACKING_URI", "http://localhost:5000")
    client = MlflowClient(tracking_uri=mlflow_tracking_uri)

    current_prod = client.get_latest_versions(args.model, stages=["Production"])
    current_version = current_prod[0].version if current_prod else None

    if args.to_version:
        rollback_version = args.to_version
    else:
        archived = client.get_latest_versions(args.model, stages=["Archived"])
        if not archived:
            raise SystemExit(
                f"No Archived version of '{args.model}' to roll back to. "
                "Pass --to-version to pick one explicitly."
            )
        rollback_version = archived[0].version

    client.transition_model_version_stage(
        name=args.model,
        version=rollback_version,
        stage="Production",
        archive_existing_versions=True,
    )

    log_audit_event(
        "rollback",
        model=args.model,
        rolled_back_to_version=rollback_version,
        rolled_back_from_version=current_version,
        triggered_by=os.environ.get("GITLAB_USER_LOGIN", os.environ.get("USER", "unknown")),
    )
    print(f"{args.model} rolled back to v{rollback_version} (was: v{current_version})")
    print(
        "Inference pods still need a rollout restart to pick up the change - "
        "see RUNBOOK.md."
    )


if __name__ == "__main__":
    main()
