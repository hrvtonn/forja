#!/usr/bin/env bash
# Smoke test fim a fim das APIs através do ponto de entrada público (gateway/ingress).
# Uso: scripts/smoke-test.sh [BASE_URL]
#   BASE_URL padrão: http://localhost:8080 (Docker Compose). Kubernetes/kind: http://localhost:8081
#   EVENT_ID (env): evento com estoque já cadastrado (padrão: smoke-test)
set -uo pipefail

BASE_URL="${1:-http://localhost:8080}"
EVENT_ID="${EVENT_ID:-smoke-test}"
TIMEOUT="${WAIT_TIMEOUT:-90}"
FAILURES=0

green() { printf '\033[32m%s\033[0m\n' "$*"; }
red()   { printf '\033[31m%s\033[0m\n' "$*"; }

# check <descrição> <status esperado> <método> <caminho> [corpo JSON]
check() {
  local description="$1" expected="$2" method="$3" path="$4" body="${5:-}"
  local args=(-s -o /tmp/smoke-body.$$ -w '%{http_code}' -X "$method" "${BASE_URL}${path}")
  [[ -n "$body" ]] && args+=(-H 'Content-Type: application/json' -d "$body")

  local status
  status=$(curl "${args[@]}")
  if [[ "$status" == "$expected" ]]; then
    green "  ✔ ${description} (HTTP ${status})"
  else
    red "  ✘ ${description}: esperado ${expected}, recebido ${status}"
    red "    resposta: $(head -c 300 /tmp/smoke-body.$$ 2>/dev/null)"
    FAILURES=$((FAILURES + 1))
  fi
}

echo "Aguardando ${BASE_URL} ficar disponível (até ${TIMEOUT}s)..."
for ((i = 0; i < TIMEOUT; i += 2)); do
  if curl -sf "${BASE_URL}/contratos/health" >/dev/null && curl -sf "${BASE_URL}/flash-sales/health" >/dev/null; then
    break
  fi
  sleep 2
done

echo "Contratos"
check "health"                         200 GET  /contratos/health
check "cria contrato válido"           201 POST /contratos/contracts '{"title":"Contrato smoke","userId":"smoke-user","description":"Criado pelo smoke test","value":1500.50}'
check "rejeita contrato sem campos"    400 POST /contratos/contracts '{"description":"sem titulo"}'
check "métricas não expostas"          404 GET  /contratos/metrics

echo "Flash Sales"
check "health"                         200 GET  /flash-sales/health
check "checkout com estoque"           201 POST /flash-sales/checkout "{\"eventId\":\"${EVENT_ID}\",\"userId\":\"smoke-user\",\"quantity\":1}"
check "checkout acima do estoque"      409 POST /flash-sales/checkout "{\"eventId\":\"${EVENT_ID}\",\"userId\":\"smoke-user\",\"quantity\":1000000}"
check "checkout sem campos"            400 POST /flash-sales/checkout '{"eventId":"x"}'
check "exportação de relatório"        200 POST /flash-sales/tickets/export '{"records":10000}'
check "métricas não expostas"          404 GET  /flash-sales/metrics

rm -f /tmp/smoke-body.$$

if ((FAILURES > 0)); then
  red "Smoke test falhou: ${FAILURES} verificação(ões) com erro."
  exit 1
fi
green "Smoke test concluído com sucesso."
