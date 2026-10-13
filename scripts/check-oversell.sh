#!/usr/bin/env bash
# Verifica a consistência do estoque após um teste de carga do Flash Sales:
# ingressos vendidos (Postgres) + estoque restante (Redis) deve ser igual ao estoque inicial.
# Uso: scripts/check-oversell.sh <compose|k8s> <EVENT_ID> <ESTOQUE_INICIAL>
set -euo pipefail

MODE="${1:-compose}"
EVENT_ID="${2:-load-test}"
INITIAL="${3:-500}"
NAMESPACE="${NAMESPACE:-devops-api}"

SQL="SELECT COALESCE(SUM(quantity),0) FROM orders WHERE \"eventId\" = '${EVENT_ID}';"
REDIS_GET="redis-cli -a \"\$REDIS_PASSWORD\" --no-auth-warning GET event:${EVENT_ID}:tickets"

case "$MODE" in
  compose)
    cd "$(dirname "$0")/.."
    SOLD=$(docker compose exec -T postgres psql -U postgres -d flash_sales -tAc "$SQL")
    LEFT=$(docker compose exec -T redis sh -c "$REDIS_GET")
    ;;
  k8s)
    SOLD=$(kubectl -n "$NAMESPACE" exec postgres-0 -c postgres -- psql -U postgres -d flash_sales -tAc "$SQL")
    LEFT=$(kubectl -n "$NAMESPACE" exec redis-0 -c redis -- sh -c "$REDIS_GET")
    ;;
  *)
    echo "Modo inválido: $MODE (use compose ou k8s)" >&2
    exit 1
    ;;
esac

echo "Evento ${EVENT_ID}: vendidos=${SOLD} restantes=${LEFT:-0} inicial=${INITIAL}"
if (( SOLD + ${LEFT:-0} == INITIAL && SOLD <= INITIAL )); then
  echo "OK: nenhum ingresso vendido além do estoque (sem overselling)."
else
  echo "ERRO: inconsistência de estoque detectada!" >&2
  exit 1
fi
