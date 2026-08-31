# Same convention as mlflow/main.tf: these are Argo CD Application CRs, not
# live Helm releases - Argo CD's own controller does the actual `helm
# template` + apply, so Block A3 ("no manual kubectl/helm, only through Git")
# holds even though the manifests live in Terraform instead of goit-argo.
#
# Bootstrap order: vpc -> eks -> argocd (2-phase) -> mlflow -> this module.
# (mlflow first only because Prometheus's Grafana wires a Loki datasource
# in the same apply; there is no hard resource dependency between the two.)

resource "kubernetes_manifest" "prometheus_operator" {
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
                # scraped without extra RBAC or label wiring.
                serviceMonitorSelector                  = {}
                serviceMonitorSelectorNilUsesHelmValues = false
                retention                               = "2d"
              }
            }
            kubelet = {
              enabled = true
              serviceMonitor = {
                enabled = true
              }
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
