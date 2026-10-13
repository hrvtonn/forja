#!/usr/bin/env bash
# Cadastra o estoque de ingressos de um evento no Redis (chave event:<id>:tickets).
# A API de Flash Sales não possui endpoint administrativo de estoque; este script
# automatiza a operação nos dois ambientes.
#
# Uso: scripts/seed-tickets.sh <compose|k8s> [EVENT_ID] [QUANTIDADE] [--force]
#   --force  sobrescreve o estoque existente (padrão: só cria se não existir)
set -euo pipefail

MODE="${1:-compose}"
EVENT_ID="${2:-show-2026}"
QUANTITY="${3:-1000}"
FORCE="${4:-}"
NAMESPACE="${NAMESPACE:-devops-api}"

KEY="event:${EVENT_ID}:tickets"
NX="NX"
[[ "$FORCE" == "--force" ]] && NX=""

REDIS_CMD="redis-cli -a \"\$REDIS_PASSWORD\" --no-auth-warning SET ${KEY} ${QUANTITY} ${NX} && redis-cli -a \"\$REDIS_PASSWORD\" --no-auth-warning GET ${KEY}"

case "$MODE" in
  compose)
    cd "$(dirname "$0")/.."
    docker compose exec -T redis sh -c "$REDIS_CMD"
    ;;
  k8s)
    kubectl -n "$NAMESPACE" exec redis-0 -c redis -- sh -c "$REDIS_CMD"
    ;;
  *)
    echo "Modo inválido: $MODE (use compose ou k8s)" >&2
    exit 1
    ;;
esac

echo "Estoque do evento '${EVENT_ID}' configurado (chave ${KEY})."
