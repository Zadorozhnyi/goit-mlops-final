# Same convention as mlflow/main.tf: these are Argo CD Application CRs, not
# live Helm releases - Argo CD's own controller does the actual `helm
# template` + apply, so Block A3 ("no manual kubectl/helm, only through Git")
# holds even though the manifests live in Terraform instead of goit-argo.
#
# Bootstrap order: vpc -> eks -> argocd (2-phase) -> mlflow -> this module.
# (mlflow first only because Prometheus's Grafana wires a Loki datasource
# in the same apply; there is no hard resource dependency between the two.)

# Created directly rather than left to the Applications' CreateNamespace=true:
# that only happens once Argo CD gets around to syncing them, which is too
# late for inference_dashboard below - it needs the namespace to exist right
# away, in the same apply.
resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = var.target_namespace
  }

  lifecycle {
    ignore_changes = [metadata[0].labels, metadata[0].annotations]
  }
}

resource "kubernetes_manifest" "prometheus_operator" {
  depends_on = [kubernetes_namespace_v1.monitoring]

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "prometheus-operator"
      namespace = var.argocd_namespace
      finalizers = [
        "resources-finalizer.argocd.argoproj.io"
      ]
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://prometheus-community.github.io/helm-charts"
        chart          = "kube-prometheus-stack"
        targetRevision = "75.16.1"
        helm = {
          valuesObject = {
            nameOverride = "prometheus-operator"
            defaultRules = {
              create = true
              rules = {
                cpu    = true
                memory = true
              }
            }
            prometheus = {
              ingress = {
                enabled = false
              }
              thanosService = {
                enabled = false
              }
              thanosIngress = {
                enabled = false
              }
              prometheusSpec = {
                # Nil means "use the selector below", not "match nothing" -
                # this is what lets the Pushgateway's and the inference
                # service's ServiceMonitors (different namespaces) get
                # scraped without extra RBAC or label wiring. Same story for
                # ruleSelector: without it, Prometheus only loads
                # PrometheusRule objects carrying this chart's own release
                # label, and the inference_alerts rule below (Block E2)
                # never gets picked up.
                serviceMonitorSelector                  = {}
                serviceMonitorSelectorNilUsesHelmValues = false
                ruleSelector                            = {}
                ruleSelectorNilUsesHelmValues           = false
                retention                               = "2d"
              }
            }
            kubelet = {
              enabled = true
              serviceMonitor = {
                enabled = true
              }
            }
            # Host-level metrics (disk/network/host CPU), not what Block A5
            # asks for (pod CPU/RAM comes from kubelet/cAdvisor via the
            # `kubelet` block above, no node-exporter involved). Cut as pure
            # footprint reduction: it's a DaemonSet, so it costs one pod on
            # every single node - four pods for something not on the
            # required-metrics list, on nodes that are already memory-tight.
            "prometheus-node-exporter" = {
              enabled = false
            }
            alertmanager = {
              enabled = true
              ingress = {
                enabled = false
              }
              alertmanagerSpec = {
                forceEnableClusterMode = true
                configSecret           = "alertmanager-secret"
              }
            }
            grafana = {
              ingress = {
                enabled = false
              }
              adminPassword = "prom-operator"
              sidecar = {
                datasources = {
                  enabled                  = true
                  defaultDatasourceEnabled = false
                }
                dashboards = {
                  # Watches for ConfigMaps labeled grafana_dashboard: "1" in
                  # any namespace and loads them automatically - see
                  # inference_dashboard below. No manual "import JSON" step.
                  enabled               = true
                  searchInAllNamespaces = true
                  label                 = "grafana_dashboard"
                  labelValue            = "1"
                }
              }
              # Fixed UIDs so dashboards keep working across recreations -
              # a random generated UID breaks any dashboard JSON that
              # references it. Prometheus stays the default source; Loki
              # (deployed by the loki_stack Application below) is added
              # alongside it, not instead of it.
              additionalDataSources = [
                {
                  name      = "Prometheus"
                  type      = "prometheus"
                  uid       = "prometheus"
                  url       = "http://prometheus-operator-prometheus.${var.target_namespace}:9090"
                  access    = "proxy"
                  isDefault = true
                },
                {
                  name      = "Loki"
                  type      = "loki"
                  uid       = "loki"
                  url       = "http://loki.${var.target_namespace}:3100"
                  access    = "proxy"
                  isDefault = false
                }
              ]
            }
            prometheusOperator = {
              admissionWebhooks = {
                enabled = false
                patch = {
                  enabled = false
                }
                certManager = {
                  enabled = false
                }
                autoGenerateCert = false
              }
              # Separate from admissionWebhooks above - this is the
              # operator's own internal webhook TLS (for validating
              # PrometheusRule resources), and it mounts a cert secret that
              # only exists if cert-manager or the patch job created it.
              # Neither is enabled here, so the pod got stuck forever in
              # ContainerCreating waiting on a secret nobody was going to
              # create. Turning this off too was the actual fix.
              tls = {
                enabled = false
              }
            }
          }
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = var.target_namespace
      }
      syncPolicy = {
        syncOptions = ["CreateNamespace=true", "Replace=true", "ServerSideApply=true"]
        automated = {
          prune    = true
          selfHeal = true
        }
      }
    }
  }
}

resource "kubernetes_manifest" "loki_stack" {
  depends_on = [kubernetes_namespace_v1.monitoring]

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "loki"
      namespace = var.argocd_namespace
      finalizers = [
        "resources-finalizer.argocd.argoproj.io"
      ]
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://grafana.github.io/helm-charts"
        chart          = "loki-stack"
        targetRevision = "2.9.10"
        helm = {
          valuesObject = {
            grafana = {
              enabled = false # Grafana already comes from kube-prometheus-stack
              sidecar = {
                datasources = {
                  enabled = false # datasource wiring is handled explicitly above instead
                }
              }
            }
            prometheus = {
              enabled = false # Prometheus already comes from kube-prometheus-stack
            }
            loki = {
              persistence = {
                enabled = false # logs kept in memory only - acceptable for a study project
              }
            }
            promtail = {
              enabled = true # DaemonSet agent that ships stdout/stderr from every node
            }
            test = {
              enabled = false # skip the chart's test ConfigMap, not needed here
            }
          }
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = var.target_namespace
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = ["CreateNamespace=true"]
      }
    }
  }
}

# A ConfigMap, not an Application - Grafana's dashboard sidecar (enabled
# above) just watches for the grafana_dashboard label and loads whatever it
# finds, the same way it already does for datasources. Terraform manages this
# one directly rather than through Argo CD, same exception as the Argo CD
# Helm release itself and the namespace it lives in: this is platform
# bootstrap config, not an application workload.
resource "kubernetes_config_map_v1" "inference_dashboard" {
  metadata {
    name      = "inference-dashboard"
    namespace = var.target_namespace
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "inference-dashboard.json" = file("${path.module}/dashboards/inference-dashboard.json")
  }

  depends_on = [kubernetes_namespace_v1.monitoring]
}

# Block E1: every 15 minutes, compare recent production predictions (pulled
# from Loki - see monitoring/drift/drift_check.py) against the training data
# and push a drift score to Prometheus via the same Pushgateway the training
# pipeline already uses.
resource "kubernetes_cron_job_v1" "drift_check" {
  metadata {
    name      = "drift-check"
    namespace = var.target_namespace
  }

  spec {
    schedule                      = "*/15 * * * *"
    concurrency_policy            = "Forbid" # one run at a time - a slow Loki query shouldn't stack up
    successful_jobs_history_limit = 3
    failed_jobs_history_limit     = 3

    job_template {
      metadata {}
      spec {
        backoff_limit = 1
        template {
          metadata {}
          spec {
            restart_policy = "OnFailure"
            container {
              name  = "drift-check"
              image = "${var.drift_check_image}:latest"
              env {
                name  = "LOKI_URL"
                value = "http://loki.${var.target_namespace}.svc.cluster.local:3100"
              }
              env {
                name  = "PUSHGATEWAY_ADDRESS"
                value = "prometheus-pushgateway.${var.target_namespace}.svc.cluster.local:9091"
              }
              resources {
                requests = {
                  cpu    = "100m"
                  memory = "256Mi"
                }
                limits = {
                  memory = "512Mi"
                }
              }
            }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_namespace_v1.monitoring]
}

# Block E2: Grafana's "Alerting" view reads these straight from Prometheus/
# Alertmanager - no separate Grafana-side alert rule config needed. See
# docs/ESCALATION_POLICY.md for who actually gets paged on each of these.
resource "kubernetes_manifest" "inference_alerts" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"
    metadata = {
      name      = "inference-alerts"
      namespace = var.target_namespace
      labels = {
        # Matches defaultRules' own labels so this rule group shows up next
        # to the chart's built-in ones in the Prometheus UI, not because
        # anything requires it - ruleSelector above already accepts any
        # PrometheusRule regardless of label.
        release = "prometheus-operator"
      }
    }
    spec = {
      groups = [
        {
          name = "inference.rules"
          rules = [
            {
              alert = "InferenceLatencyHigh"
              expr  = <<-EOT
                histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{job="inference"}[5m])) by (le)) > 1
              EOT
              for   = "5m"
              labels = {
                severity = "warning"
              }
              annotations = {
                summary     = "Inference p95 latency above 1s"
                description = "See RUNBOOK.md 'Grafana shows latency p95 above threshold'."
              }
            },
            {
              alert = "InferenceErrorRateHigh"
              expr  = <<-EOT
                sum(rate(http_requests_total{job="inference", status=~"5.."}[5m])) / sum(rate(http_requests_total{job="inference"}[5m])) > 0.01
              EOT
              for   = "5m"
              labels = {
                severity = "critical"
              }
              annotations = {
                summary     = "Inference 5xx error rate above 1%"
                description = "See RUNBOOK.md - consider rollback if this doesn't recover quickly."
              }
            },
            {
              alert = "InferenceDataDriftHigh"
              expr  = "inference_data_drift_share > 0.5"
              for   = "15m"
              labels = {
                severity = "warning"
              }
              annotations = {
                summary     = "Over half of input features have drifted from the training distribution"
                description = "See RUNBOOK.md 'Grafana/Evidently shows data drift'."
              }
            }
          ]
        }
      ]
    }
  }

  depends_on = [kubernetes_manifest.prometheus_operator]
}
