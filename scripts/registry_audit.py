"""Small helper so every Model Registry action logs the same shape of event.

Printed as one JSON object per line to stdout - Promtail (deployed by the
monitoring/ module) ships container stdout to Loki automatically, so nothing
here talks to Loki directly. That satisfies Block C5 (audit logging) without
adding a logging backend dependency to a one-off script.
"""

import json
import sys
from datetime import datetime, timezone


def log_audit_event(action: str, **fields) -> None:
    event = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "component": "model-registry-audit",
        "action": action,
        **fields,
    }
    print(json.dumps(event), file=sys.stdout, flush=True)
