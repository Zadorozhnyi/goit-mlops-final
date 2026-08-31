"""Small helper so every Model Registry action logs the same shape of event.

Pushed straight to Loki's HTTP push API rather than relying on Promtail to
pick up stdout - these scripts are meant to be run wherever someone has
network access to MLflow (a laptop via port-forward, a CI job, an in-cluster
runner), and Promtail only ever sees stdout of pods actually scheduled on a
cluster node. A local `python promote_model.py` run never becomes a pod, so
that stdout would simply never reach Loki. Pushing directly works the same
way regardless of where the script runs, mirroring how
`training/train_and_push.py` pushes training metrics straight to
Pushgateway instead of hoping something scrapes them.
"""

import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone

LOKI_PUSH_URL = os.environ.get("LOKI_PUSH_URL", "http://localhost:3100/loki/api/v1/push")


def log_audit_event(action: str, **fields) -> None:
    timestamp = datetime.now(timezone.utc)
    event = {
        "timestamp": timestamp.isoformat(),
        "component": "model-registry-audit",
        "action": action,
        **fields,
    }
    line = json.dumps(event)
    print(line, file=sys.stdout, flush=True)

    body = json.dumps(
        {
            "streams": [
                {
                    "stream": {"app": "model-registry-audit", "action": action},
                    "values": [[str(int(timestamp.timestamp() * 1e9)), line]],
                }
            ]
        }
    ).encode("utf-8")
    request = urllib.request.Request(
        LOKI_PUSH_URL, data=body, headers={"Content-Type": "application/json"}
    )
    try:
        urllib.request.urlopen(request, timeout=5)
    except (urllib.error.URLError, OSError) as exc:
        # Same non-fatal pattern as push_metrics() in train_and_push.py - a
        # Loki hiccup shouldn't block a promotion/rollback that already
        # succeeded against MLflow.
        print(f"warning: could not push audit event to Loki: {exc}", file=sys.stderr)
