#!/usr/bin/env bash
# CSE644 Assignment 03, Requirement 6, Part B: remove the assignment's
# resources and verify cleanup is complete.
#
# Run this only when you're done reviewing the live environment - it
# deletes both Argo CD Applications (cascading to the resources they
# manage) and then Argo CD itself.
#
# Scope note: this does NOT run `kind delete cluster`. The cse644 KinD
# cluster is shared, long-lived infrastructure reused since Assignment 02,
# not a resource this assignment owns. For a full teardown of the cluster
# itself, run separately:  kind delete cluster --name cse644
#
# Usage: bash scripts/req06b-cleanup.sh
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$PATH"
LOG="evidence/logs/req06b-cleanup.txt"
mkdir -p evidence/logs

{
  echo "=== Deleting Argo CD Applications (cascade = also delete what they manage) ==="
  argocd app delete cse644-app --cascade -y
  argocd app delete cse644-monitoring --cascade -y

  echo
  echo "Waiting for cascaded namespace deletion..."
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    sleep 5
    REMAINING="$(kubectl get ns cse644 monitoring 2>/dev/null | grep -c -E 'cse644|monitoring')"
    echo " t+$((i*5))s: matching namespaces remaining = $REMAINING"
    [ "$REMAINING" = "0" ] && break
  done

  echo
  echo "=== Removing Argo CD itself ==="
  pkill -f "port-forward svc/argocd-server" 2>/dev/null || true
  kubectl delete namespace argocd --wait=true --timeout=120s

  echo
  echo "=== Verification: cleanup is complete ==="
  echo "Namespaces remaining on the cluster:"
  kubectl get ns
  echo
  echo "cse644 namespace:    $(kubectl get ns cse644 2>&1 | tail -n1)"
  echo "monitoring namespace: $(kubectl get ns monitoring 2>&1 | tail -n1)"
  echo "argocd namespace:    $(kubectl get ns argocd 2>&1 | tail -n1)"
  echo
  echo "The cse644 KinD cluster itself is left running (shared across CSE644"
  echo "assignments). Full cluster teardown, if wanted:"
  echo "  kind delete cluster --name cse644"
} > "$LOG" 2>&1

GONE="$(kubectl get ns cse644 monitoring argocd 2>&1 | grep -c NotFound)"
if [ "$GONE" = "3" ]; then
  echo "[PASS] cleanup complete: cse644/monitoring/argocd namespaces all gone"
else
  echo "[CHECK] see $LOG (expected 3 'NotFound' namespaces, saw $GONE)"
fi
echo "Evidence ($(wc -l < "$LOG") lines) -> $LOG"
