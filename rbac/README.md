# Two roles, matched to what people actually need to do day-to-day:
#
# mlops-engineer
#   - staging: full control (create/update/delete on pods, deployments,
#     services, configmaps, jobs). This is the sandbox - iterate freely.
#   - production: read-only plus `kubectl rollout restart` (a patch on
#     deployments, nothing else). Everything that actually changes what's
#     running in production is meant to go through a Git commit and Argo CD,
#     not a live kubectl edit - this role is what makes that the only path
#     that works, not just a convention people are supposed to follow.
#
# viewer
#   - read-only (get/list/watch) across every namespace, including Argo CD
#     Applications and Prometheus resources. No write access anywhere.
#
# Applying this:
#   kubectl apply -f rbac/mlops-engineer-role.yaml
#   kubectl apply -f rbac/viewer-role.yaml
#
# (These aren't deployed through Argo CD like everything else in this repo -
# RBAC is cluster bootstrap, applied once by whoever sets up the cluster,
# same category as the aws-auth ConfigMap that maps IAM users to these
# group names in the first place.)
