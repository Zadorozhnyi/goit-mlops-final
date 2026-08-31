#!/usr/bin/env python3
"""Promote a Model Registry version from Staging to Production.

This is the "separate, deliberate action" Block B2 asks for - training never
calls this itself. Run it by hand, or as a manual GitLab CI job
(promote-to-production in .gitlab-ci.yml).

Usage:
    python promote_model.py --model iris-classifier --version 3
    python promote_model.py --model iris-classifier --latest-staging
"""

import argparse
import os
import sys

from mlflow.tracking import MlflowClient

sys.path.insert(0, os.path.dirname(__file__))
from registry_audit import log_audit_event  # noqa: E402


def latest_version_in_stage(client: MlflowClient, model_name: str, stage: str):
    versions = client.get_latest_versions(model_name, stages=[stage])
    if not versions:
        raise SystemExit(f"No model version of '{model_name}' is currently in {stage}")
    return versions[0]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", required=True, help="Registered model name")
    parser.add_argument("--version", help="Explicit version number to promote")
    parser.add_argument(
        "--latest-staging",
        action="store_true",
        help="Promote whatever is currently the latest Staging version",
    )
    args = parser.parse_args()

    if not args.version and not args.latest_staging:
        parser.error("pass either --version or --latest-staging")

    mlflow_tracking_uri = os.environ.get("MLFLOW_TRACKING_URI", "http://localhost:5000")
    client = MlflowClient(tracking_uri=mlflow_tracking_uri)

    if args.latest_staging:
        staging_version = latest_version_in_stage(client, args.model, "Staging")
        version = staging_version.version
    else:
        version = args.version

    # The previous Production version, if any, gets archived by
    # archive_existing_versions=True below. Grab it first so the rollback
    # story ("go back to what was running before") is logged, not just implied.
    previous_prod = client.get_latest_versions(args.model, stages=["Production"])
    previous_version = previous_prod[0].version if previous_prod else None

    client.transition_model_version_stage(
        name=args.model,
        version=version,
        stage="Production",
        archive_existing_versions=True,
    )

    log_audit_event(
        "promote_to_production",
        model=args.model,
        version=version,
        previous_production_version=previous_version,
        triggered_by=os.environ.get("GITLAB_USER_LOGIN", os.environ.get("USER", "unknown")),
    )
    print(f"{args.model} v{version} is now Production (was: v{previous_version})")


if __name__ == "__main__":
    main()
