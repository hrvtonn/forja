output "cluster_name" {
  description = "Nome do cluster criado"
  value       = kind_cluster.this.name
}

output "kubeconfig_path" {
  description = "Arquivo kubeconfig do cluster (use: export KUBECONFIG=...)"
  value       = abspath(kind_cluster.this.kubeconfig_path)
}

output "ingress_url" {
  description = "URL pública das APIs no cluster"
  value       = "http://localhost:${var.ingress_http_port}"
}
