# Runbook

## Roll out a new model version

1. Push to this repo (or manually run the `train-model` job). This runs
   `training/train_and_push.py`, which trains, registers the new version in
   MLflow, and transitions it to **Staging**.
2. Check it in staging: `kubectl port-forward -n staging svc/inference 8000:80`
   and send it a few `/predict` requests, or just look at the Grafana
   dashboard filtered to the staging pods.
3. Happy with it? Run the `promote-to-production` job (manual, GitLab CI) -
   this calls `scripts/promote_model.py`, which transitions the version to
   **Production** and archives whatever was there before.
4. The idle production slot (check `activeSlot` in
   `inference/helm/values-production.yaml` to see which one that is) needs
   its `modelVersion` bumped to the new version number and a rollout
   restart, then flip `activeSlot` to that slot and commit. Argo CD picks up
   the commit and switches traffic - that's the blue/green cutover.

## Roll back production

1. Run the `rollback-production` job (manual, GitLab CI) - this calls
   `scripts/rollback.py`, which puts the previously Archived version back
   into Production.
2. Restart the production pods so they actually reload the model:
   `kubectl rollout restart deployment -n production -l app=inference`
   (or flip `activeSlot` back to the other slot, if that slot is still
   running the old version - that's the faster path and doesn't need a
   restart at all).

## Grafana shows latency p95 above threshold

1. Check the Grafana dashboard's request-rate panel first - a latency spike
   that lines up with a traffic spike is a capacity problem, not a model
   problem.
2. Check `kubectl top pods -n production` - if CPU is pegged, the fix is
   more replicas or more CPU request, not a rollback.
3. If latency is high with normal traffic and normal CPU, check whether the
   currently active slot just got promoted (cold model load can look like
   a latency spike for the first requests) - give it a minute before
   assuming something is actually wrong.
4. Still bad after that? Roll back (see above) while investigating.

## Grafana/Evidently shows data drift

`monitoring/drift/drift_check.py` runs as a CronJob every 15 minutes,
comparing the last 15 minutes of production predictions (pulled from Loki)
against the training data, and pushes `inference_data_drift_share` /
`inference_dataset_drift` to Prometheus. `InferenceDataDriftHigh` fires when
more than half the features drift for 15 minutes straight.

1. Don't auto-retrain on this alone. Check `inference_drift_check_samples`
   first - a drift score based on 20 requests means something different
   than one based on 2000.
2. Check which specific features drifted: `kubectl logs -n monitoring
   job/<latest drift-check job>` prints the share and sample count; for
   per-feature detail, rerun `drift_check.py` locally against a dump of
   recent predictions and read the full Evidently report instead of just
   the summary metrics pushed to Prometheus.
3. Ask whether the input data source actually changed (new client, new
   sensor, a unit conversion bug) before deciding this needs a retrain at
   all - drift by itself isn't proof the model got worse, just that the
   input distribution moved.
4. If a retrain genuinely is the right call, that's the normal "roll out a
   new model version" flow above - promote through Staging like any other
   version, don't hot-patch production directly.

## Tear down everything

Reverse of the apply order:

```
cd terraform/inference   && terraform destroy
cd terraform/monitoring  && terraform destroy
cd terraform/mlflow      && terraform destroy
cd terraform/argocd      && terraform destroy
cd terraform/eks         && terraform destroy
cd terraform/vpc         && terraform destroy
```

Applications first, then Argo CD (which stops managing them), then the
cluster, then the network - going in the other order leaves Argo CD trying
to reconcile Applications whose destination cluster no longer exists.
