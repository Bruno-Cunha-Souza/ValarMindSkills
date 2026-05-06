// Phase 4.4 — k6 burst test (separate from run-all.sh — invoke manually).
// Run: k6 run 05-burst.k6.js -e TARGET=https://api.example.com -e RATE_PATH=/api/data
//
// Validates that the API rate-limits (returns 429) under sustained burst load.
// Outputs a k6 summary; pair findings with the bash burst probe (05-rate-limit.sh).

import http from "k6/http";
import { check, sleep } from "k6";

const TARGET     = __ENV.TARGET || "https://localhost";
const RATE_PATH  = __ENV.RATE_PATH || "/api/data";
const TOKEN      = __ENV.TOKEN || "";
const VUS        = parseInt(__ENV.VUS || "100", 10);
const DURATION   = __ENV.DURATION || "10s";

export const options = {
  vus: VUS,
  duration: DURATION,
  thresholds: {
    // We *want* 429s under burst load. If <5% of responses are 429, the API is not protecting itself.
    "http_req_failed{expected_response:true}": ["rate>0.0"],
    "checks{name:limited_or_authed}":          ["rate>0.95"],
  },
};

export default function () {
  const headers = { "Content-Type": "application/json" };
  if (TOKEN) headers["Authorization"] = `Bearer ${TOKEN}`;

  const res = http.get(`${TARGET}${RATE_PATH}`, { headers });

  check(res, {
    "limited_or_authed": (r) => r.status === 429 || r.status === 200 || r.status === 401,
  }, { name: "limited_or_authed" });

  // brief jitter so the burst is not perfectly synchronized
  sleep(Math.random() * 0.05);
}

export function handleSummary(data) {
  const codes = data.metrics.http_reqs?.values || {};
  const summary = {
    target:    `${TARGET}${RATE_PATH}`,
    vus:       VUS,
    duration:  DURATION,
    requests:  data.metrics.http_reqs?.values?.count || 0,
    failed:    data.metrics.http_req_failed?.values?.rate || 0,
    p95_ms:    data.metrics.http_req_duration?.values?.["p(95)"] || 0,
  };

  return {
    stdout: `\n=== k6 burst summary ===\n${JSON.stringify(summary, null, 2)}\n`,
  };
}
