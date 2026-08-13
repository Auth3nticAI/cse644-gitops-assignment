#!/usr/bin/env bash
# CSE644 Assignment 03, Requirement 2 evidence: Argo CD created and
# maintains the application resources, and the running application is
# reachable and identifiable as this student's work.
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$PATH"
LOG="evidence/logs/req02-gitops-deployment.txt"
mkdir -p evidence/logs

{
  echo "=== argocd namespace controller pods ==="
  kubectl -n argocd get pods

  echo
  echo "=== Argo CD Application: cse644-app ==="
  argocd app get cse644-app

  echo
  echo "=== kubectl view of the same Application object ==="
  kubectl -n argocd get application cse644-app -o wide

  echo
  echo "=== Application is reachable (via HAProxy edge -> nginx-web, port-forward) ==="
  kubectl -n cse644 port-forward svc/haproxy-edge-svc 18081:80 > /tmp/haproxy-pf.log 2>&1 &
  HPF_PID=$!
  sleep 3
  curl -s http://127.0.0.1:18081/ | grep -Eo "<title>[^<]*</title>" || true
  kill "$HPF_PID" 2>/dev/null

  echo
  echo "=== python-web app identifies student + assignment (via its own Service) ==="
  kubectl -n cse644 port-forward svc/python-web-svc 18888:8888 > /tmp/python-pf.log 2>&1 &
  PPF_PID=$!
  sleep 3
  curl -s http://127.0.0.1:18888/api/info | python3 -m json.tool 2>/dev/null | grep -E "student|assignment|greeting|environment"
  kill "$PPF_PID" 2>/dev/null
} > "$LOG" 2>&1

SYNC="$(argocd app get cse644-app -o json 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["status"]["sync"]["status"], d["status"]["health"]["status"])' 2>/dev/null)"
if [ "$SYNC" = "Synced Healthy" ]; then
  echo "[PASS] Argo CD Application cse644-app is Synced + Healthy"
else
  echo "[CHECK] Application status: '$SYNC' - see $LOG"
fi
echo "Evidence ($(wc -l < "$LOG") lines) -> $LOG"
