# Escalation policy

Who gets paged for what, and how urgently. This is a study project, so
"paged" here means Alertmanager routes to a Slack channel / email, not an
actual on-call rotation - but the severity levels and response expectations
are written as if it were one, since that's the point of the exercise.

| Alert | Severity | Who | Response time | First action |
|---|---|---|---|---|
| `InferenceErrorRateHigh` (5xx > 1%) | critical | on-call MLOps engineer | 15 min | Check Grafana dashboard for a traffic/CPU spike first; if the model itself is the problem, roll back (`scripts/rollback.py` + RUNBOOK.md) |
| `InferenceLatencyHigh` (p95 > 1s) | warning | on-call MLOps engineer | 1 hour | Check CPU/replica count before assuming it's the model; see RUNBOOK.md |
| `InferenceDataDriftHigh` (drift share > 50%) | warning | ML engineer / data owner | next business day | Do not auto-retrain. Check which features drifted and whether the data source changed upstream before deciding to retrain |

Alertmanager itself isn't wired to a real Slack/email/PagerDuty target in
this project (`configSecret: alertmanager-secret` in
`terraform/monitoring/main.tf` is a placeholder) - wiring a real receiver is
a five-minute change to that secret, not a structural one, so it's left out
of the demo on purpose rather than half-configuring something with no one on
the other end of it.
