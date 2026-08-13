#!/usr/bin/env bash
# CSE644 Assignment 03 - generate enough real traffic against python-web
# for Prometheus/Grafana to show a visible change (Requirement 5).
# Usage: bash scripts/12-generate-traffic.sh [request-pairs] [target-url]
set -euo pipefail
N="${1:-40}"
BASE="${2:-http://127.0.0.1:18888}"

for i in $(seq 1 "$N"); do
  curl -s -o /dev/null "$BASE/"
  curl -s -o /dev/null "$BASE/api/info"
  curl -s -X POST -H "Content-Type: application/json" \
    -d "{\"note\": \"traffic-gen-$i\"}" \
    -o /dev/null "$BASE/api/notes"
  sleep 0.2
done
echo "Sent $((N*3)) requests to $BASE"
