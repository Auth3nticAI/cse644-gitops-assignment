#!/usr/bin/env bash
# CSE644 Assignment 03, Requirement 3 evidence:
#   Part A - a Git-driven change (already committed: nginx-web 3->2 replicas,
#            python-web greeting/environment) reconciled by Argo CD.
#   Part B - an unmanaged, direct-to-cluster change (kubectl scale, bypassing
#            Git) gets detected as drift and reverted by Argo CD's selfHeal,
#            because Git - not the live cluster - is the source of truth.
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$PATH"
LOG="evidence/logs/req03-change-and-reconciliation.txt"
mkdir -p evidence/logs

{
  echo "=== Part A: state after the Git-driven change (commit af4e1e2) ==="
  argocd app get cse644-app | grep -E "Sync Status|Health Status"
  kubectl -n cse644 get deployment nginx-web -o jsonpath='nginx-web replicas: desired={.spec.replicas} ready={.status.readyReplicas}{"\n"}'
  echo "python-web live config (via API, proves the ConfigMap edit reached the running Pod):"
  kubectl -n cse644 port-forward svc/python-web-svc 18889:8888 > /tmp/pf-req03.log 2>&1 &
  PF1=$!
  sleep 3
  curl -s http://127.0.0.1:18889/api/info | python3 -c 'import json,sys; d=json.load(sys.stdin); print(" greeting:", d["greeting"]); print(" environment:", d["environment"])'
  kill "$PF1" 2>/dev/null

  echo
  echo "=== Part B: introducing live drift directly against the cluster ==="
  echo "Before drift: nginx-web replicas = $(kubectl -n cse644 get deployment nginx-web -o jsonpath='{.spec.replicas}')"
  echo "Running: kubectl -n cse644 scale deployment/nginx-web --replicas=5  (bypasses Git entirely)"
  kubectl -n cse644 scale deployment/nginx-web --replicas=5
  sleep 2
  echo "Immediately after: nginx-web replicas = $(kubectl -n cse644 get deployment nginx-web -o jsonpath='{.spec.replicas}')"

  echo
  echo "Forcing Argo CD to notice (hard-refresh; normal polling interval is ~3 min):"
  argocd app get cse644-app --hard-refresh | grep -E "Sync Status|Health Status"

  echo
  echo "Waiting for automated selfHeal to revert the drift..."
  for i in 1 2 3 4 5 6 7 8 9 10; do
    sleep 3
    REPLICAS="$(kubectl -n cse644 get deployment nginx-web -o jsonpath='{.spec.replicas}')"
    echo " t+$((i*3))s: nginx-web replicas = $REPLICAS"
    if [ "$REPLICAS" = "2" ]; then
      echo " -> back to the Git-declared value (2). Argo CD selfHeal reverted the drift."
      break
    fi
  done

  echo
  echo "=== Final state ==="
  argocd app get cse644-app | grep -E "Sync Status|Health Status"
  kubectl -n cse644 get deployment nginx-web -o jsonpath='nginx-web replicas: desired={.spec.replicas} ready={.status.readyReplicas}{"\n"}'
  echo
  echo "=== Argo CD's own record of the revert (application controller events) ==="
  kubectl -n argocd get events --field-selector involvedObject.name=cse644-app --sort-by=.lastTimestamp | tail -n 8
} > "$LOG" 2>&1

FINAL_REPLICAS="$(kubectl -n cse644 get deployment nginx-web -o jsonpath='{.spec.replicas}' 2>/dev/null)"
if [ "$FINAL_REPLICAS" = "2" ]; then
  echo "[PASS] Git-driven change reconciled; live drift (5 replicas) self-healed back to Git's declared 2"
else
  echo "[CHECK] final replica count = $FINAL_REPLICAS, see $LOG"
fi
echo "Evidence ($(wc -l < "$LOG") lines) -> $LOG"
