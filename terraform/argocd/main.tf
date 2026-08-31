resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = var.argocd_namespace

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      purpose                        = "mlops-system"
    }
  }

  lifecycle {
    # The GitOps repo also carries a matching ns.yaml, so Argo CD stamps its
    # own tracking labels on this namespace. Without this, every plan would
    # show a diff and try to strip them back off.
    ignore_changes = [metadata[0].labels, metadata[0].annotations]
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name

  values = [file("${path.module}/values/argocd-values.yaml")]

  # The chart pulls in CRDs and several controllers; the default 5 minutes is
  # not always enough on small nodes.
  timeout = 900
  wait    = true
}

# Watches namespace/* in the GitOps repository and turns every directory it
# finds into an Argo CD Application named after that directory.
#
# Bootstrap note: kubernetes_manifest validates the ApplicationSet CRD during
# plan, and that CRD only exists after the Helm release above is installed.
# depends_on does not help, because the check happens before apply. On a fresh
# cluster run the two-step sequence from the README:
#   terraform apply -target=helm_release.argocd
#   terraform apply
resource "kubernetes_manifest" "namespaces_appset" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "ApplicationSet"

    metadata = {
      name      = "namespaces-appset"
      namespace = var.argocd_namespace
    }

    spec = {
      generators = [{
        git = {
          repoURL  = var.gitops_repo_url
          revision = var.gitops_repo_branch
          directories = [{
            path = var.gitops_directory_pattern
          }]
        }
      }]

      template = {
        metadata = {
          name      = "ns-{{path.basename}}"
          namespace = var.argocd_namespace
        }

        spec = {
          project = "default"

          source = {
            repoURL        = var.gitops_repo_url
            targetRevision = var.gitops_repo_branch
            path           = "{{path}}"
            directory = {
              recurse = true
            }
          }

          destination = {
            server = "https://kubernetes.default.svc"
            # Directory name doubles as the target namespace: namespace/staging
            # deploys into the staging namespace, namespace/monitoring into
            # monitoring, etc.
            namespace = "{{path.basename}}"
          }

          syncPolicy = {
            automated = {
              prune    = true
              selfHeal = true
            }
            syncOptions = ["CreateNamespace=true"]
          }

          revisionHistoryLimit = 2
        }
      }
    }
  }

  depends_on = [helm_release.argocd]
}
