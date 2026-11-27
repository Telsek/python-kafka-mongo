# ArgoCD - deploys everything in the GitOps repo
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "10.20.0"
  namespace        = "argocd"
  create_namespace = true

  values = [yamlencode({
    dex = { enabled = false } # no SSO login needed, saves RAM
  })]

  depends_on = [module.eks]
}

# root app: watches apps/ in the GitOps repo (app of apps)
resource "helm_release" "argocd_root" {
  name       = "argocd-root"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = "2.0.10"
  namespace  = "argocd"

  values = [yamlencode({
    applications = {
      root = {
        namespace = "argocd"
        project   = "default"
        source = {
          repoURL        = "https://github.com/Telsek/python-kafka-mongo-gitops.git"
          targetRevision = "main"
          path           = "apps"
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = "argocd"
        }
        # git is the truth: deploy new commits, undo manual changes, remove deleted files
        syncPolicy = { automated = { prune = true, selfHeal = true } }
      }
    }
  })]

  depends_on = [helm_release.argocd] # needs ArgoCD's Application type to exist first
}