#!/usr/bin/env bash
# CSE644 Assignment 03, Requirement 5 evidence: Prometheus is collecting
# meaningful metrics, Grafana is provisioned to visualize them, and
# generated traffic produces a visible, explainable change in that data.
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$PATH"
LOG="evidence/logs/req05-observability.txt"
mkdir -p evidence/logs

# Long-lived port-forwards for this evidence run (nohup+disown so they
# survive this script's own subshells - see scripts/11-argocd-login.sh).
for pair in "prometheus 19090:9090" "grafana 13000:3000" "python-web-svc 18888:8888"; do
  svc="$(echo "$pair" | cut -d' ' -f1)"; port="$(echo "$pair" | cut -d' ' -f2)"
  ns="monitoring"; [ "$svc" = "python-web-svc" ] && ns="cse644"
  pgrep -f "port-forward svc/$svc $port" >/dev/null 2>&1 || {
    nohup kubectl -n "$ns" port-forward "svc/$svc" "$port" > "/tmp/pf-$svc.log" 2>&1 &
    disown
  }
done
sleep 4

{
  echo "=== Argo CD: monitoring Application status ==="
  argocd app get cse644-monitoring | grep -E "Sync Status|Health Status"

  echo
  echo "=== Prometheus scrape targets ==="
  curl -s http://127.0.0.1:19090/api/v1/targets | python3 -c "
import json,sys
d=json.load(sys.stdin)
for t in d['data']['activeTargets']:
    print(' ', t['labels'].get('job'), '->', t['health'])
"

  echo
  echo "=== Grafana: provisioned datasource + dashboard ==="
  bash scripts/lib/grafana-check.sh

  echo
  echo "=== Baseline: app_http_requests_total and app_notes_stored, before traffic ==="
  curl -s 'http://127.0.0.1:19090/api/v1/query?query=sum(app_http_requests_total)' \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print(' total requests:', d['data']['result'][0]['value'][1] if d['data']['result'] else 0)"
  curl -s 'http://127.0.0.1:19090/api/v1/query?query=app_notes_stored' \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print(' notes stored:', d['data']['result'][0]['value'][1] if d['data']['result'] else 0)"

  echo
  echo "=== Generating traffic (40 request cycles = 120 HTTP requests) ==="
  bash scripts/12-generate-traffic.sh 40 http://127.0.0.1:18888

  echo
  echo "Waiting one scrape interval (12s) for Prometheus to pick it up..."
  sleep 12

  echo
  echo "=== After traffic: same queries ==="
  curl -s 'http://127.0.0.1:19090/api/v1/query?query=sum(app_http_requests_total)' \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print(' total requests:', d['data']['result'][0]['value'][1] if d['data']['result'] else 0)"
  curl -s 'http://127.0.0.1:19090/api/v1/query?query=app_notes_stored' \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print(' notes stored:', d['data']['result'][0]['value'][1] if d['data']['result'] else 0)"
  echo
  echo "=== Request rate by endpoint over the last 2 minutes (proves the traffic shows up as rate, not just a counter bump) ==="
  # -G --data-urlencode: curl treats unescaped [ ] in a raw URL as its own
  # glob-range syntax, not PromQL - this avoids that collision entirely.
  curl -s -G 'http://127.0.0.1:19090/api/v1/query' \
    --data-urlencode 'query=sum(rate(app_http_requests_total[2m])) by (endpoint)' \
    | python3 -c "
import json,sys
d=json.load(sys.stdin)
for r in d['data']['result']:
    print(' ', r['metric'].get('endpoint'), '->', round(float(r['value'][1]), 4), 'req/s')
"
} > "$LOG" 2>&1

AFTER="$(curl -s 'http://127.0.0.1:19090/api/v1/query?query=sum(app_http_requests_total)' | python3 -c "import json,sys; d=json.load(sys.stdin); print(int(float(d['data']['result'][0]['value'][1])))" 2>/dev/null)"
if [ -n "$AFTER" ] && [ "$AFTER" -gt 0 ]; then
  echo "[PASS] Prometheus is scraping python-web; request count now $AFTER after generated traffic"
else
  echo "[CHECK] see $LOG"
fi
echo "Evidence ($(wc -l < "$LOG") lines) -> $LOG"
