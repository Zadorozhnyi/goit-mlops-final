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

## Grafana/Evidently shows data drift (Block E, not implemented yet)

Not built in this pass - see README.md "What's not done" section. Once it
exists: check which features drifted, compare against the reference
dataset, decide retrain vs investigate-data-source before doing anything
else. Don't auto-retrain on a drift alert alone.

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
