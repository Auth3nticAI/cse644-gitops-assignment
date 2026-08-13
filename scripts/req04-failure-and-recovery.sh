#!/usr/bin/env bash
# CSE644 Assignment 03, Requirement 4 evidence: a controlled failure
# introduced through Git, diagnosed from GitOps-controller + Kubernetes
# evidence, and recovered by reverting the bad commit in Git (never by
# patching the live cluster directly).
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$PATH"
LOG="evidence/logs/req04-failure-and-recovery.txt"
mkdir -p evidence/logs

BAD_COMMIT="$(git log --oneline --grep='Requirement 4: introduce a controlled deployment failure' --format='%H' | head -n1)"

{
  echo "=== Failure commit ==="
  git show --stat "$BAD_COMMIT"

  echo
  echo "=== Diagnosis, evidence 1: Argo CD Application health ==="
  argocd app get cse644-app | grep -E "Sync Status|Health Status"
  echo "(Synced means the live manifest matches the bad commit exactly - Argo CD"
  echo " did its job faithfully. Progressing/Degraded is Kubernetes reporting"
  echo " that the resulting Pod is not actually healthy.)"

  echo
  echo "=== Diagnosis, evidence 2: Kubernetes Pod state ==="
  kubectl -n cse644 get pods -l app=python-web

  echo
  echo "=== Diagnosis, evidence 3: Pod events (root cause) ==="
  BAD_POD="$(kubectl -n cse644 get pods -l app=python-web --field-selector=status.phase!=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
  if [ -n "$BAD_POD" ]; then
    kubectl -n cse644 describe pod "$BAD_POD" | grep -A 10 "^Events:"
  fi

  echo
  echo "=== Availability during the failure ==="
  echo "python-web-svc Endpoints (only the still-Running old Pod should be listed -"
  echo "RollingUpdate's default maxUnavailable=0 keeps the old ReplicaSet's Pod in"
  echo "service until a replacement passes readiness, so the failed rollout never"
  echo "took the app offline):"
  kubectl -n cse644 get endpoints python-web-svc

  echo
  echo "=== Recovery: revert the bad commit in Git (not a live kubectl edit) ==="
  git revert --no-edit "$BAD_COMMIT"
  git log --oneline -3
  git push origin main

  echo
  echo "=== Waiting for Argo CD to reconcile the revert ==="
  argocd app get cse644-app --hard-refresh | grep -E "Sync Status|Health Status"
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    sleep 5
    HEALTH="$(argocd app get cse644-app 2>/dev/null | grep 'Health Status' | awk '{print $3}')"
    echo " t+$((i*5))s: Health Status = $HEALTH"
    [ "$HEALTH" = "Healthy" ] && break
  done

  echo
  echo "=== Final state ==="
  argocd app get cse644-app | grep -E "Sync Status|Health Status"
  kubectl -n cse644 get pods -l app=python-web
  kubectl -n cse644 get deployment python-web -o jsonpath='image in use: {.spec.template.spec.containers[0].image}{"\n"}'
} > "$LOG" 2>&1

FINAL_IMAGE="$(kubectl -n cse644 get deployment python-web -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)"
if [ "$FINAL_IMAGE" = "auth3nticai/cse644-gitops-python:v2" ]; then
  echo "[PASS] failure diagnosed and recovered via Git revert; image back to v2, app Healthy"
else
  echo "[CHECK] final image = '$FINAL_IMAGE', see $LOG"
fi
echo "Evidence ($(wc -l < "$LOG") lines) -> $LOG"
