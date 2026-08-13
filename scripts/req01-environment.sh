#!/usr/bin/env bash
# CSE644 Assignment 03, Requirement 1 evidence: the Kubernetes environment
# and the repository/revision history it is built from.
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$PATH"
LOG="evidence/logs/req01-environment.txt"
mkdir -p evidence/logs

{
  echo "=== KinD cluster ==="
  kind get clusters
  echo
  kubectl get nodes -o wide
  echo
  echo "=== cse644 namespace pods ==="
  kubectl -n cse644 get pods -o wide
  echo
  echo "=== Repository remote + branch ==="
  git remote -v
  git branch --show-current
  echo
  echo "=== Commit history ==="
  git log --oneline --decorate
  echo
  echo "=== Working tree status (should be clean) ==="
  git status --short
} > "$LOG" 2>&1

BAD_PODS="$(kubectl -n cse644 get pods --no-headers 2>/dev/null | grep -cv -E 'Running|Completed')"
if kind get clusters 2>/dev/null | grep -q cse644 \
   && [ "$BAD_PODS" = "0" ] \
   && [ -n "$(git log --oneline 2>/dev/null)" ]; then
  echo "[PASS] cluster up, app namespace healthy, repo has commit history"
else
  echo "[CHECK] see $LOG for details"
fi
echo "Evidence ($(wc -l < "$LOG") lines) -> $LOG"
