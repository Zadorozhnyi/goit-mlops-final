# ADR: deployment strategy for the inference service

## Context

Block B3 asks for one of Canary, Blue-Green, or A/B testing. The model is a
small sklearn classifier serving a low-traffic demo endpoint - not a system
where gradually ramping traffic percentages actually buys much, since there
isn't enough real traffic to make a 90/10 split statistically meaningful
anyway.

## Decision

Blue-Green. Two full copies of the inference Deployment (`blue`, `green`)
run in the `production` namespace at all times, each pinned to an explicit
MLflow model version. One Service selects whichever slot is currently
"active" (`values-production.yaml`'s `activeSlot` field). Promoting a new
version means updating the idle slot's `modelVersion`, checking it's healthy,
then flipping `activeSlot` and committing - Argo CD does the actual traffic
switch.

## Trade-offs considered

- **Canary** would demonstrate more nuanced traffic control (gradual
  percentage ramp), but needs something to actually split traffic by weight
  - either a service mesh or Ingress-level canary annotations - which is a
  lot of moving parts for a demo project with no real production traffic to
  validate against. Also higher risk of not finishing it properly in the
  time available, and the course material itself says a simple, fully-working
  strategy beats a complex, half-finished one.
- **A/B testing** solves a different problem (compare two models against
  real users) than what this project needs (safely roll out one new
  version) - picking it would have been solving for a use case that doesn't
  exist here.
- **Blue-Green** keeps the switch atomic and the rollback trivial (flip the
  selector back, or revert the commit) - and it maps directly onto plain
  Kubernetes Service selectors, no extra infrastructure needed.

## What I'd do differently with more time

- Automate the health check between "update idle slot" and "flip
  activeSlot" instead of doing it by hand - right now a human has to decide
  the idle slot is actually ready.
- Look at replacing the two-static-Deployments approach with Argo Rollouts,
  which has blue-green and canary as first-class resources instead of
  hand-rolled Service-selector flipping - would remove a fair amount of the
  custom Helm templating in `inference/helm/templates/`.
- Add automatic rollback on error-rate spike (Block G2) instead of requiring
  someone to notice Grafana and run the rollback script by hand.
