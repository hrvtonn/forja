# Plataforma Kubernetes local reproduzível:
#   - cluster kind (1 control-plane + N workers)
#   - Traefik como ingress controller (NodePort 30080 -> localhost:<ingress_http_port>)
#   - metrics-server (métricas de CPU/memória para o HorizontalPodAutoscaler)
# As aplicações são implantadas depois via Kustomize (infra/k8s), separando
# o ciclo de vida da plataforma do ciclo de vida das aplicações.

locals {
  ingress_node_port = 30080
  kubeconfig_path   = "${path.module}/kubeconfig"
}

resource "kind_cluster" "this" {
  name            = var.cluster_name
  node_image      = var.node_image
  kubeconfig_path = local.kubeconfig_path
  wait_for_ready  = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"

      extra_port_mappings {
        container_port = local.ingress_node_port
        host_port      = var.ingress_http_port
        listen_address = "127.0.0.1"
        protocol       = "TCP"
      }
    }

    dynamic "node" {
      for_each = range(var.worker_count)
      content {
        role = "worker"
      }
    }
  }
}

provider "helm" {
  kubernetes = {
    host                   = kind_cluster.this.endpoint
    client_certificate     = kind_cluster.this.client_certificate
    client_key             = kind_cluster.this.client_key
    cluster_ca_certificate = kind_cluster.this.cluster_ca_certificate
  }
}

resource "helm_release" "traefik" {
  name             = "traefik"
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  version          = var.traefik_chart_version
  namespace        = "traefik"
  create_namespace = true
  wait             = true
  timeout          = 600

  values = [yamlencode({
    service = {
      spec = { type = "NodePort" }
    }
    ports = {
      web = {
        nodePort = local.ingress_node_port
      }
      websecure = {
        expose = { default = false }
      }
    }
    ingressClass = {
      enabled        = true
      isDefaultClass = true
      name           = "traefik"
    }
    providers = {
      kubernetesCRD     = { enabled = true }
      kubernetesIngress = { enabled = true }
    }
    accessLog = {
      enabled = true
      format  = "json"
    }
  })]
}

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = var.metrics_server_chart_version
  namespace  = "kube-system"
  wait       = true
  timeout    = 600

  values = [yamlencode({
    # kubelets do kind usam certificados autoassinados
    args = ["--kubelet-insecure-tls"]
  })]
}
