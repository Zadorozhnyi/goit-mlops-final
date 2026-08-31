# Two Applications, both pointed at the same chart (inference/helm in this
# repo) but with different values files - one per environment. Same
# "Application CR, not a live Helm release" convention as mlflow/ and
# monitoring/: Argo CD's own controller does the real `helm template` + apply.
#
# Bootstrap order: vpc -> eks -> argocd (2-phase) -> mlflow -> monitoring ->
# this module. mlflow first because these charts read
# mlflowTrackingUri pointed at the mlflow-tracking service that module creates.

resource "kubernetes_manifest" "inference_staging" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "inference-staging"
      namespace = var.argocd_namespace
      finalizers = [
        "resources-finalizer.argocd.argoproj.io"
      ]
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.inference_repo_url
        targetRevision = var.inference_repo_branch
        path           = "inference/helm"
        helm = {
          valueFiles = ["values-staging.yaml"]
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "staging"
      }
      syncPolicy = {
        syncOptions = ["CreateNamespace=true"]
        automated = {
          prune    = true
          selfHeal = true
        }
      }
    }
  }
}

resource "kubernetes_manifest" "inference_production" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "inference-production"
      namespace = var.argocd_namespace
      finalizers = [
        "resources-finalizer.argocd.argoproj.io"
      ]
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.inference_repo_url
        targetRevision = var.inference_repo_branch
        path           = "inference/helm"
        helm = {
          valueFiles = ["values-production.yaml"]
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "production"
      }
      syncPolicy = {
        syncOptions = ["CreateNamespace=true"]
        automated = {
          prune    = true
          selfHeal = true
        }
      }
    }
  }
}
