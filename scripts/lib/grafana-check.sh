#!/usr/bin/env bash
# Confirms Grafana file-provisioning actually took effect (datasource +
# dashboard exist), via Grafana's own HTTP API. Kept in its own file rather
# than inlined - command substitution assigned to a variable behaves
# unreliably when inlined directly into a `wsl ... bash -lc '...'` string.
set -euo pipefail
GRAFANA_PW="$(kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d)"
curl -s -u "admin:$GRAFANA_PW" http://127.0.0.1:13000/api/datasources -o /tmp/ds.json
curl -s -u "admin:$GRAFANA_PW" "http://127.0.0.1:13000/api/search?query=" -o /tmp/dash.json
unset GRAFANA_PW
python3 -c "
import json
ds=json.load(open('/tmp/ds.json'))
print(' datasources:', [{'name':x['name'],'type':x['type'],'isDefault':x['isDefault']} for x in ds] if isinstance(ds, list) else ds)
dash=json.load(open('/tmp/dash.json'))
print(' dashboards:', [{'title':x['title'],'uid':x['uid']} for x in dash if x.get('type')=='dash-db'] if isinstance(dash, list) else dash)
"
