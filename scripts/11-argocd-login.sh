#!/usr/bin/env bash
# CSE644 Assignment 03 - authenticate the argocd CLI against the in-cluster
# server via a background port-forward. The initial admin password is read
# straight out of the argocd-initial-admin-secret Secret into a shell
# variable and used immediately - it is never echoed or written to a log,
# per the assignment's rule against submitting real credentials.
set -euo pipefail

# 8080 is already claimed by another local service on this machine (checked
# via `ss -tlnp`), so the Argo CD UI/API is forwarded to 18080 instead.
#
# nohup + disown: each Claude Code tool call is a separate `wsl -d ... bash
# -lc '...'` invocation, so a plain `&` background job dies with that shell
# when the tool call returns. nohup blocks the resulting SIGHUP and disown
# drops it from the job table, so it keeps running in the WSL2 VM across
# tool calls - the same pattern scripts/02-run-cloud-provider-kind.sh uses.
if pgrep -f "port-forward svc/argocd-server" >/dev/null 2>&1; then
  echo "port-forward already running (pid $(pgrep -f "port-forward svc/argocd-server"))"
else
  nohup kubectl -n argocd port-forward svc/argocd-server 18080:443 > /tmp/argocd-port-forward.log 2>&1 &
  disown
  sleep 3
fi
PF_PID="$(pgrep -f "port-forward svc/argocd-server" | head -n1)"
echo "$PF_PID" > /tmp/argocd-port-forward.pid

ARGOCD_PW="$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
argocd login localhost:18080 --username admin --password "$ARGOCD_PW" --insecure --grpc-web
unset ARGOCD_PW

echo "Logged in. Port-forward running in background as PID $PF_PID (localhost:18080 -> argocd-server:443)."
echo "Stop it later with: kill \$(cat /tmp/argocd-port-forward.pid)"
