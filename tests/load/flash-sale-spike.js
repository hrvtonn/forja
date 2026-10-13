// Teste de carga: pico de compras simultâneas (cenário real de flash sale).
// Valida desempenho sob carga e, junto com scripts/check-oversell.sh, que o
// script Lua atômico no Redis impede a venda de ingressos além do estoque.
//
// Variáveis: CHECKOUT_URL (padrão: gateway local), EVENT_ID, PEAK_RPS
import http from "k6/http";
import { check } from "k6";
import { Counter } from "k6/metrics";

const CHECKOUT_URL = __ENV.CHECKOUT_URL || "http://localhost:8080/flash-sales/checkout";
const EVENT_ID = __ENV.EVENT_ID || "load-test";
const PEAK_RPS = parseInt(__ENV.PEAK_RPS || "200");

const ticketsSold = new Counter("tickets_sold");
const ticketsSoldOut = new Counter("tickets_sold_out");
const rateLimited = new Counter("rate_limited");

// 409 (esgotado) e 429 (rate limit do gateway) são respostas esperadas da plataforma
http.setResponseCallback(http.expectedStatuses(201, 409, 429));

export const options = {
  scenarios: {
    flash_sale: {
      executor: "ramping-arrival-rate",
      startRate: 10,
      timeUnit: "1s",
      preAllocatedVUs: 50,
      maxVUs: 400,
      stages: [
        { target: PEAK_RPS, duration: "15s" }, // abertura das vendas
        { target: PEAK_RPS, duration: "30s" }, // pico sustentado
        { target: 0, duration: "10s" },
      ],
    },
  },
  thresholds: {
    http_req_failed: ["rate<0.01"], // menos de 1% de erros inesperados (5xx/timeouts)
    "http_req_duration{expected_response:true}": ["p(95)<500"],
    checks: ["rate>0.99"],
  },
};

export default function () {
  const payload = JSON.stringify({ eventId: EVENT_ID, userId: `user-${__VU}-${__ITER}`, quantity: 1 });
  const res = http.post(CHECKOUT_URL, payload, { headers: { "Content-Type": "application/json" } });

  check(res, { "status 201, 409 ou 429": (r) => [201, 409, 429].includes(r.status) });

  if (res.status === 201) ticketsSold.add(1);
  else if (res.status === 409) ticketsSoldOut.add(1);
  else if (res.status === 429) rateLimited.add(1);
}
