provider "helm" {
  kubernetes = {
    config_path = "~/.kube/config"
  }
}


resource "helm_release" "arc" {
  name             = "arc"
  repository       = "oci://ghcr.io/actions/actions-runner-controller-charts"
  chart            = "gha-runner-scale-set-controller"
  version          = "0.14.2"
  namespace        = "arc-systems"
  create_namespace = true
}

resource "helm_release" "arc_runner_set" {
  name             = "arc-runner-set"
  repository       = "oci://ghcr.io/actions/actions-runner-controller-charts"
  chart            = "gha-runner-scale-set"
  version          = "0.14.2"
  namespace        = "arc-runners"
  create_namespace = true

  set = [
    {
      name  = "githubConfigUrl"
      value = var.github_url
    }
  ]

  set_sensitive = [
    {
      name  = "githubConfigSecret.github_token"
      value = var.github_token
    }
  ]

  depends_on = [helm_release.arc]
}
