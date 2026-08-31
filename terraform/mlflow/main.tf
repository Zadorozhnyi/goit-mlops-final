# Every resource here is an Argo CD Application CR, not a live Helm release -
# Terraform's only job is to hand the manifest to Argo CD; Argo CD does the
# actual `helm template` + apply. This keeps Block A3 true ("no manual
# kubectl/helm install, only through Git") even though the config lives in
# this Terraform project instead of the goit-argo repo.
#
# Bootstrap order: vpc -> eks -> argocd (2-phase) -> this module. The Argo CD
# Application CRD (installed by argocd/main.tf's helm_release) must already
# exist, otherwise `kubernetes_manifest` fails validation during plan.

resource "kubernetes_manifest" "mlflow_postgres" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "mlflow-postgres"
      namespace = var.argocd_namespace
      finalizers = [
        "resources-finalizer.argocd.argoproj.io"
      ]
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://charts.bitnami.com/bitnami"
        chart          = "postgresql"
        targetRevision = "18.8.12"
        helm = {
          valuesObject = {
            auth = {
              username = "mlflow"
              password = "mlflowpass"
              database = "mlflow"
            }
            primary = {
              persistence = {
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

resource "kubernetes_manifest" "mlflow_minio" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "mlflow-minio"
      namespace = var.argocd_namespace
      finalizers = [
        "resources-finalizer.argocd.argoproj.io"
      ]
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://charts.bitnami.com/bitnami"
        chart          = "minio"
        targetRevision = "17.0.21"
        helm = {
          valuesObject = {
            # Bitnami emptied the `bitnami/*` tags for minio images (Aug 2025
            # catalog restructuring); frozen versions live under bitnamilegacy.
            global = {
              security = {
                allowInsecureImages = true
              }
            }
            image = {
              repository = "bitnamilegacy/minio"
            }
            clientImage = {
              repository = "bitnamilegacy/minio-client"
            }
            auth = {
              rootUser     = "admin"
              rootPassword = "mlflowpass"
            }
            defaultBuckets = "mlflow-artifacts"
            persistence = {
              enabled = false
            }
            tls = {
              enabled = false
            }
            service = {
              type = "ClusterIP"
              ports = {
                api = 9000
              }
            }
            # Avoids also needing bitnamilegacy/minio-object-browser; the
            # console isn't required for this project (bucket + S3 API only).
            console = {
              enabled = false
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

resource "kubernetes_manifest" "mlflow_tracking" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "mlflow-tracking"
      namespace = var.argocd_namespace
      finalizers = [
        "resources-finalizer.argocd.argoproj.io"
      ]
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://charts.bitnami.com/bitnami"
        chart          = "mlflow"
        targetRevision = "5.1.17"
        helm = {
          valuesObject = {
            global = {
              security = {
                allowInsecureImages = true
              }
            }
            image = {
              repository = "bitnamilegacy/mlflow"
            }
            waitContainer = {
              image = {
                repository = "bitnamilegacy/os-shell"
              }
            }
            # Backend store and artifact store are their own Applications
            # (mlflow-postgres, mlflow-minio) above, pointed at as external
            # services rather than bundled subcharts.
            postgresql = {
              enabled = false
            }
            externalDatabase = {
              dialectDriver = "postgresql"
              host          = "mlflow-postgres-postgresql.${var.target_namespace}.svc.cluster.local"
              port          = 5432
              user          = "mlflow"
              password      = "mlflowpass"
              database      = "mlflow"
            }
            minio = {
              enabled = false
            }
            externalS3 = {
              host            = "mlflow-minio.${var.target_namespace}.svc.cluster.local"
              port            = 9000
              protocol        = "http"
              accessKeyID     = "admin"
              accessKeySecret = "mlflowpass"
              bucket          = "mlflow-artifacts"
              serveArtifacts  = true
            }
            tracking = {
              auth = {
                enabled = false
              }
              service = {
                type = "ClusterIP"
                ports = {
                  http = 5000
                }
              }
              persistence = {
                enabled = false
              }
            }
            # modelRegistry rides along on the same tracking server - MLflow
            # doesn't split them into a separate deployment. Registry
            # promotion (Block B2) talks to this same service.
            #
            # The chart's separate "run" deployment is for demo/example
            # training jobs, not something this project uses - and on
            # memory-constrained t3.small nodes, the 512Mi it always asks
            # for is capacity better spent elsewhere.
            run = {
              enabled = false
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

  depends_on = [kubernetes_manifest.mlflow_postgres, kubernetes_manifest.mlflow_minio]
}

resource "kubernetes_manifest" "prometheus_pushgateway" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "prometheus-pushgateway"
      namespace = var.argocd_namespace
      finalizers = [
        "resources-finalizer.argocd.argoproj.io"
      ]
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://prometheus-community.github.io/helm-charts"
        chart          = "prometheus-pushgateway"
        targetRevision = "3.8.0"
        helm = {
          valuesObject = {
            service = {
              type = "ClusterIP"
              port = 9091
            }
            # Picked up automatically: the monitoring/ module's Prometheus
            # sets serviceMonitorSelector: {} with SelectorNilUsesHelmValues:
            # false, so any ServiceMonitor in any namespace gets scraped.
            serviceMonitor = {
              enabled   = true
              namespace = var.monitoring_namespace
            }
          }
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = var.monitoring_namespace
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
