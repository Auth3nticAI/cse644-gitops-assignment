#!/usr/bin/env bash
# CSE644 Assignment 03, Requirement 6 evidence, Part A: final end-to-end
# validation that the app, GitOps workflow, monitoring, and dashboard all
# function together. Non-destructive - safe to re-run any time.
# Cleanup (Part B) is a separate script: scripts/req06b-cleanup.sh.
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$PATH"
LOG="evidence/logs/req06a-validate.txt"
mkdir -p evidence/logs

{
  echo "=== Both Argo CD Applications: Synced + Healthy ==="
  argocd app list

  echo
  echo "=== Application reachable and identifiable ==="
  nohup kubectl -n cse644 port-forward svc/python-web-svc 18888:8888 > /tmp/pf-validate.log 2>&1 &
  disown
  sleep 3
  curl -s http://127.0.0.1:18888/api/info | python3 -c "import json,sys; d=json.load(sys.stdin); print(' student:', d['student'], '| assignment:', d['assignment'], '| greeting:', d['greeting'])"
  pkill -f "port-forward svc/python-web-svc 18888" 2>/dev/null

  echo
  echo "=== Monitoring: scrape target healthy ==="
  nohup kubectl -n monitoring port-forward svc/prometheus 19090:9090 > /tmp/pf-prom-validate.log 2>&1 &
  disown
  sleep 3
  curl -s -G 'http://127.0.0.1:19090/api/v1/query' --data-urlencode 'query=up{job="python-web"}' \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print(' python-web scrape up =', d['data']['result'][0]['value'][1] if d['data']['result'] else 'NO DATA')"
  pkill -f "port-forward svc/prometheus 19090" 2>/dev/null

  echo
  echo "=== Dashboard still provisioned in Grafana ==="
  nohup kubectl -n monitoring port-forward svc/grafana 13000:3000 > /tmp/pf-grafana-validate.log 2>&1 &
  disown
  sleep 3
  bash scripts/lib/grafana-check.sh
  pkill -f "port-forward svc/grafana 13000" 2>/dev/null

  echo
  echo "=== Repository: everything is committed (no drift between disk and Git) ==="
  git status --short
  git log --oneline | head -n 10
} > "$LOG" 2>&1

SYNCED_COUNT="$(argocd app list 2>/dev/null | grep -c "Synced.*Healthy")"
if [ "$SYNCED_COUNT" = "2" ]; then
  echo "[PASS] both Applications Synced+Healthy, app + monitoring stack verified end-to-end"
else
  echo "[CHECK] $SYNCED_COUNT/2 Applications Synced+Healthy, see $LOG"
fi
echo "Evidence ($(wc -l < "$LOG") lines) -> $LOG"
