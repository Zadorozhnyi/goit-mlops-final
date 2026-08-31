#!/usr/bin/env python3
"""Compare recent production predictions against the training data and push a
drift score to Prometheus (Block E1).

Reference data is just the full Iris dataset sklearn ships - deterministic,
no separate reference file to keep in sync. "Current" data is whatever the
inference service actually saw, pulled from its own structured logs in Loki
(main.py logs sepal/petal values on every prediction) - no separate database
needed just for this.

Meant to run as a Kubernetes CronJob (see terraform/monitoring/main.tf) every
15 minutes. If there aren't enough recent predictions to compare, it exits
quietly instead of pushing a misleading score from 3 data points.
"""

import argparse
import json
import os
import re
import sys
import time

import pandas as pd
import requests
from evidently import ColumnMapping
from evidently.report import Report
from evidently.metric_preset import DataDriftPreset
from prometheus_client import CollectorRegistry, Gauge, push_to_gateway
from sklearn.datasets import load_iris

FEATURE_COLUMNS = ["sepal_length", "sepal_width", "petal_length", "petal_width"]
MIN_SAMPLES = 20  # below this, a drift score is more noise than signal

LOKI_URL = os.environ.get("LOKI_URL", "http://loki.monitoring.svc.cluster.local:3100")
PUSHGATEWAY_ADDRESS = os.environ.get("PUSHGATEWAY_ADDRESS", "localhost:9091")
LOOKBACK_MINUTES = int(os.environ.get("LOOKBACK_MINUTES", "15"))

# Matches the JSON object main.py logs on every prediction - see main.py's
# `predict()` logger.info call for the exact shape.
PREDICTION_LOG_RE = re.compile(r'"event":\s*"prediction".*')


def reference_dataframe() -> pd.DataFrame:
    X, _ = load_iris(return_X_y=True)
    return pd.DataFrame(X, columns=FEATURE_COLUMNS)


def fetch_recent_predictions(lookback_minutes: int) -> pd.DataFrame:
    end_ns = time.time_ns()
    start_ns = end_ns - lookback_minutes * 60 * 1_000_000_000
    resp = requests.get(
        f"{LOKI_URL}/loki/api/v1/query_range",
        params={
            "query": '{app="inference"} |= `"event": "prediction"`',
            "start": start_ns,
            "end": end_ns,
            "limit": 5000,
        },
        timeout=30,
    )
    resp.raise_for_status()
    payload = resp.json()

    rows = []
    for stream in payload.get("data", {}).get("result", []):
        for _, line in stream.get("values", []):
            match = PREDICTION_LOG_RE.search(line)
            if not match:
                continue
            # The log line is a Python %-formatted string wrapped in a JSON
            # logging format, and the logger doesn't escape the nested
            # "message" JSON string, so the whole line isn't valid JSON by
            # itself - raw_decode() parses just the first valid JSON value
            # starting at the given position and ignores whatever (broken)
            # text follows it, which json.loads() would reject outright.
            try:
                start = line.index("{", line.index('"message"'))
                event, _ = json.JSONDecoder().raw_decode(line[start:])
            except (ValueError, json.JSONDecodeError):
                continue
            if all(col in event for col in FEATURE_COLUMNS):
                rows.append({col: event[col] for col in FEATURE_COLUMNS})

    return pd.DataFrame(rows, columns=FEATURE_COLUMNS)


def push_drift_metrics(drift_share: float, dataset_drift: bool, sample_count: int) -> None:
    registry = CollectorRegistry()
    drift_share_gauge = Gauge(
        "inference_data_drift_share",
        "Share of features Evidently flagged as drifted",
        registry=registry,
    )
    dataset_drift_gauge = Gauge(
        "inference_dataset_drift",
        "1 if Evidently flagged dataset-level drift, 0 otherwise",
        registry=registry,
    )
    sample_count_gauge = Gauge(
        "inference_drift_check_samples",
        "Number of recent predictions the last drift check compared",
        registry=registry,
    )
    drift_share_gauge.set(drift_share)
    dataset_drift_gauge.set(1 if dataset_drift else 0)
    sample_count_gauge.set(sample_count)
    push_to_gateway(PUSHGATEWAY_ADDRESS, job="drift_check", registry=registry)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lookback-minutes", type=int, default=LOOKBACK_MINUTES)
    args = parser.parse_args()

    current = fetch_recent_predictions(args.lookback_minutes)
    if len(current) < MIN_SAMPLES:
        print(
            f"only {len(current)} predictions in the last {args.lookback_minutes} "
            f"minutes (need {MIN_SAMPLES}) - skipping this check"
        )
        return 0

    reference = reference_dataframe()
    report = Report(metrics=[DataDriftPreset()])
    report.run(
        reference_data=reference,
        current_data=current,
        column_mapping=ColumnMapping(numerical_features=FEATURE_COLUMNS),
    )
    result = report.as_dict()["metrics"][0]["result"]
    drift_share = result["share_of_drifted_columns"]
    dataset_drift = result["dataset_drift"]

    push_drift_metrics(drift_share, dataset_drift, len(current))
    print(
        f"compared {len(current)} recent predictions: drift_share={drift_share:.2f}, "
        f"dataset_drift={dataset_drift}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
