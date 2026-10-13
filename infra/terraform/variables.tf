variable "cluster_name" {
  description = "Nome do cluster kind"
  type        = string
  default     = "devops-api"
}

variable "node_image" {
  description = "Imagem dos nós do kind (versão do Kubernetes). Deve ser compatível com a versão do kind embutida no provider tehcyx/kind 0.11 (kind v0.31)."
  type        = string
  default     = "kindest/node:v1.35.0@sha256:452d707d4862f52530247495d180205e029056831160e22870e37e3f6c1ac31f"
}

variable "worker_count" {
  description = "Quantidade de nós worker. Para usar workers, aumente os limites de inotify do host (ver README)."
  type        = number
  default     = 0

  validation {
    condition     = var.worker_count >= 0 && var.worker_count <= 5
    error_message = "worker_count deve estar entre 0 e 5."
  }
}

variable "ingress_http_port" {
  description = "Porta do host (localhost) mapeada para o ingress controller"
  type        = number
  default     = 8081
}

variable "traefik_chart_version" {
  description = "Versão do Helm chart do Traefik"
  type        = string
  default     = "41.6.1"
}

variable "metrics_server_chart_version" {
  description = "Versão do Helm chart do metrics-server (necessário para o HPA)"
  type        = string
  default     = "3.14.0"
}
