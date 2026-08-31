# Threat model

What could actually go wrong with this system, and what in this repo is
supposed to stop it.

## 1. Model extraction via the inference API

Anyone who can reach `/predict` can query it repeatedly and try to reverse-
engineer the decision boundary, or just scrape it as a free classifier.

Mitigation: rate limiting (`slowapi`, see `inference/app/main.py`) caps how
many requests a single client can make per minute. Not bulletproof against a
distributed attacker, but it stops the trivial case of one script hammering
the endpoint.

## 2. Malformed or adversarial input crashing the service / leaking internals

A client sending garbage (wrong types, huge numbers, extra fields) could
crash the model call or, worse, an unhandled exception could leak a stack
trace with internal paths back in the response.

Mitigation: Pydantic schema validation (`inference/app/schemas.py`) rejects
bad input before it reaches the model, with a 422 and no internal detail.
Anything that still goes wrong inside `/predict` is caught and turned into a
generic 400 - the real exception only goes to the server-side log.

## 3. A tampered or corrupted model artifact getting served

If someone (or something) replaces `model.pkl` in S3/MinIO with a different
file - by mistake or on purpose - the inference service would silently start
serving a different model than the one that was actually reviewed and
promoted.

Mitigation: every registered model version gets a `artifact_sha256` tag at
training time (`training/train_and_push.py`). The inference service
recomputes that hash before loading the model and refuses to start if it
doesn't match (`inference/app/model_loader.py`) - the pod never becomes
Ready, so Kubernetes never sends it traffic.

## 4. Unauthorized or accidental changes to what's running in production

Someone with cluster access could `kubectl edit` a production Deployment
directly, bypassing the whole registry/promotion/review process.

Mitigation: RBAC (`rbac/`) gives `mlops-engineer` only read access plus a
rollout-restart in the `production` namespace - no create/update/delete.
Argo CD's `selfHeal: true` also means any manual drift gets reverted back to
what's in Git within the next sync cycle anyway.

## 5. Untracked or unreviewed model promotions to Production

Without an audit trail, nobody can answer "who put this model version into
Production, and when" after the fact - which matters a lot if a bad model
causes an incident.

Mitigation: `scripts/promote_model.py` and `scripts/rollback.py` log a
structured JSON event (model, version, previous version, who triggered it)
to stdout on every stage transition. Promtail ships that to Loki like any
other container log, so it's queryable in Grafana alongside everything else.
