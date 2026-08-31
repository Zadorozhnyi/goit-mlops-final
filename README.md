# MLOps Final Project

Work in progress. Structure and full write-up (architecture diagram, deploy
instructions, RUNBOOK.md, ADR.md) land here as blocks A-D get built.

## Repository layout (so far)

- `terraform/vpc/` — network (reused from goit-mlops-hw-05)
- `terraform/eks/` — EKS cluster, single cpu-nodes group (reused from goit-mlops-hw-05)
- `terraform/argocd/` — Argo CD + ApplicationSet watching `goit-argo` (reused from goit-mlops-hw-07), namespace renamed to `mlops-system`
- `terraform/mlflow/` — not started yet
- `terraform/monitoring/` — not started yet
