// Teste de isolamento (bulkhead): dispara exportações pesadas (CPU/memória)
// enquanto mede a latência do checkout. Como o export roda em um pool dedicado
// (flash-sales-export), o checkout deve manter latência baixa.
//
// Variáveis: EXPORT_URL, CHECKOUT_URL, EVENT_ID, EXPORT_RECORDS
import http from "k6/http";
import { check } from "k6";

const EXPORT_URL = __ENV.EXPORT_URL || "http://localhost:8080/flash-sales/tickets/export";
const CHECKOUT_URL = __ENV.CHECKOUT_URL || "http://localhost:8080/flash-sales/checkout";
const EVENT_ID = __ENV.EVENT_ID || "show-2026";
const EXPORT_RECORDS = parseInt(__ENV.EXPORT_RECORDS || "500000");

http.setResponseCallback(http.expectedStatuses(200, 201, 409, 429));

export const options = {
  scenarios: {
    heavy_exports: {
      executor: "constant-vus",
      exec: "exportReport",
      vus: 3,
      duration: "60s",
    },
    checkout: {
      executor: "constant-arrival-rate",
      exec: "checkout",
      rate: 20,
      timeUnit: "1s",
      duration: "60s",
      preAllocatedVUs: 20,
      maxVUs: 100,
    },
  },
  thresholds: {
    "http_req_duration{scenario:checkout}": ["p(95)<300"],
    "http_req_failed{scenario:checkout}": ["rate<0.01"],
  },
};

export function exportReport() {
  const res = http.post(EXPORT_URL, JSON.stringify({ records: EXPORT_RECORDS }), {
    headers: { "Content-Type": "application/json" },
    timeout: "120s",
  });
  check(res, { "export 200 ou 429": (r) => r.status === 200 || r.status === 429 });
}

export function checkout() {
  const payload = JSON.stringify({ eventId: EVENT_ID, userId: `bulkhead-${__VU}-${__ITER}`, quantity: 1 });
  const res = http.post(CHECKOUT_URL, payload, { headers: { "Content-Type": "application/json" } });
  check(res, { "checkout 201 ou 409": (r) => r.status === 201 || r.status === 409 });
}
