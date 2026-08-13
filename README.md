# CSE644 Assignment 03 - GitOps and Application Observability

**Student:** Tray Branch
**GitHub:** [Auth3nticAI](https://github.com/Auth3nticAI) / [cse644-gitops-assignment](https://github.com/Auth3nticAI/cse644-gitops-assignment)
**Builds on:** Assignment 02's [cse644-k8s-assignment](https://github.com/Auth3nticAI/cse644-k8s-assignment)

This repo takes the multi-service Kubernetes app from Assignment 02 and puts it under GitOps
management with Argo CD, then adds a Prometheus/Grafana observability stack for it - all declared
as code in this repository, all reconciled by controllers, none of it hand-`kubectl apply`'d.

## The application and architecture

Three components, unchanged in shape from Assignment 02, running in the `cse644` namespace:

| Component  | What it is                                       | Exposure                                              |
|------------|---------------------------------------------------|--------------------------------------------------------|
| `nginx-web`  | Static site, 2 replicas                          | ClusterIP, NodePort, LoadBalancer, Ingress (all four)  |
| `python-web` | Flask app on :8888, 1 replica                    | ClusterIP, fronted by HAProxy                          |
| `haproxy-edge` | Reverse proxy in front of `nginx-web` via Service DNS | ClusterIP                                        |

`python-web` is the interesting one for this assignment - it already had ConfigMap-driven
behavior, a Secret, a PersistentVolumeClaim, and liveness/readiness probes from Assignment 02
(`apps/python-web/app.py`). For Assignment 03 it gained a `/metrics` endpoint
(`prometheus_client`, manual `Counter`/`Histogram`/`Gauge` instrumentation - see "Observability
approach" below) and was rebuilt as `auth3nticai/cse644-gitops-python:v2`.

```
Git (this repo, branch main)
  │
  ▼
Argo CD (namespace: argocd)
  ├── Application "cse644-app"         → k8s/          → namespace cse644
  │     nginx-web, python-web, haproxy-edge, Services, Ingress, PVC, ConfigMap, Secret
  └── Application "cse644-monitoring"  → monitoring/    → namespace monitoring
        Prometheus (scrapes python-web:8888/metrics) + Grafana (dashboard provisioned as code)
```

Two independent Argo CD `Application` objects (`argocd/application-app.yaml`,
`argocd/application-monitoring.yaml`), both `automated: {prune: true, selfHeal: true}`, both
pointed at this repo's `main` branch. A change to the app can never be blocked or broken by a
change to monitoring, or vice versa - they sync on separate lifecycles.

## Prerequisites

- Docker Desktop (WSL2 backend) or any Docker daemon reachable from the shell
- [KinD](https://kind.sigs.k8s.io/) and `kubectl`
- [`argocd` CLI](https://argo-cd.readthedocs.io/en/stable/cli_installation/) (v3.5.x used here)
- `git`, `curl`, `python3` (evidence scripts parse JSON with the stdlib - no extra Python packages)
- A Docker Hub account if you want to rebuild and push `python-web` yourself; otherwise the
  vendored `auth3nticai/cse644-gitops-python:v2` image is public and pullable as-is

Developed and evidenced entirely inside WSL2 Ubuntu-24.04, not native Windows PowerShell - Docker
networking assumptions elsewhere in this README (host-reachable `LoadBalancer` IPs, etc.) depend
on that. See `apps/`, `k8s/`, and `kind/kind-config.yaml`, carried over unmodified from Assignment
02, for why.

## Deployment and validation

1. **Cluster.** This repo assumes the `cse644` KinD cluster already exists (created in Assignment
   02 via `scripts/00-bootstrap-cluster.sh`, node image `kindest/node:v1.34.0`, 1 control-plane +
   1 worker). If starting fresh: `bash scripts/00-bootstrap-cluster.sh`, then
   `bash scripts/01-build-and-load-images.sh` and `bash scripts/01b-apply-base-manifests.sh` to
   get a working non-GitOps baseline first (optional - Argo CD will create everything from `k8s/`
   regardless).

2. **Argo CD.**
   ```
   bash scripts/10-install-argocd.sh    # pinned v3.5.1, server-side apply (see below for why)
   bash scripts/11-argocd-login.sh      # port-forwards :18080, argocd CLI login
   ```

3. **Deploy the app and the monitoring stack through Argo CD** (not `kubectl apply -f k8s/`):
   ```
   kubectl apply -f argocd/application-app.yaml
   kubectl apply -f argocd/application-monitoring.yaml
   ```
   Argo CD takes it from there - within a few seconds both `Application` objects should read
   `Synced` / `Healthy`:
   ```
   argocd app list
   ```

4. **Validate end-to-end:** `bash scripts/req06a-validate.sh` - confirms both Applications are
   Synced+Healthy, the app answers with this student's identity, Prometheus's scrape target is
   `up`, and the Grafana dashboard is provisioned.

Every `scripts/reqNN-*.sh` script writes full detail to `evidence/logs/reqNN-*.txt` and prints
only a one-line PASS/CHECK verdict to the terminal - that pairing is the evidence for each
Required Outcome in the assignment.

## GitOps workflow, failure, and recovery

**Deployment (Requirement 2).** On first sync, Argo CD *adopted* the Deployments/Services that
were already running from Assignment 02 and reconciled `python-web` from its old `:v1` image to
the `:v2` declared in `k8s/04-python-deployment.yaml` - the first real proof that Git, not
whatever happened to be running, is authoritative. Evidence: `evidence/logs/req02-gitops-deployment.txt`.

**Change and reconciliation (Requirement 3).** Two things demonstrated:
- *A Git-driven change* (commit `af4e1e2`): `nginx-web` replicas 3→2, and `python-web`'s
  ConfigMap greeting/environment text updated. Both changes were pushed to `main`; Argo CD's
  automated sync applied them with no `kubectl` command run against the cluster.
- *Live drift and self-heal*: `kubectl scale deployment/nginx-web --replicas=5` was run directly
  against the cluster, bypassing Git entirely. Argo CD detected the resulting `OutOfSync` state
  and its `selfHeal` policy reverted it back to the Git-declared replica count of 2 - the
  application-controller's own events show the full `Synced → OutOfSync → Synced` cycle
  completing in about 6 seconds. This is the core GitOps guarantee: the cluster is not allowed to
  drift from Git, even when someone (or something) changes it directly.

  Evidence: `evidence/logs/req03-change-and-reconciliation.txt`.

**Controlled failure and recovery (Requirement 4).** `python-web`'s image tag was changed to a
tag that doesn't exist (`cse644-gitops-python:v2-typo-does-not-exist`) and pushed - a deliberate,
reversible failure introduced entirely through Git. Diagnosis used only GitOps-controller and
Kubernetes evidence:
- Argo CD: `Synced` (it faithfully applied the broken manifest) but `Health Status: Progressing`
- `kubectl describe pod`: exact root cause in the Events - `Failed to pull image ...: not found`,
  then `ErrImagePull` → `ImagePullBackOff`
- `kubectl get endpoints python-web-svc`: only the still-`Running` old Pod was listed the whole
  time - Kubernetes' default `RollingUpdate` (`maxUnavailable: 0` at 1 replica) held the old Pod
  in service rather than taking it down for a replacement that could never become Ready, so the
  broken rollout caused **zero downtime**, not an outage.

  Recovery was `git revert <bad-commit> && git push` - never a direct `kubectl edit` or `kubectl
  rollout undo` against the cluster. Argo CD picked up the revert and Health flipped back to
  `Healthy` in about 5 seconds.

  Evidence: `evidence/logs/req04-failure-and-recovery.txt`.

## Observability approach

**Prometheus** (`monitoring/prometheus/`) scrapes exactly two static targets - itself, and
`python-web-svc.cse644.svc.cluster.local:8888/metrics`. No `kubernetes_sd_configs` and no RBAC
for API-server discovery: with a single metrics-emitting workload, Kubernetes service discovery
would be pure overhead for what the assignment scope calls "practical for a small local cluster."

**What `/metrics` exposes** (`apps/python-web/app.py`), and why each metric was chosen:
- `app_http_requests_total{endpoint,method,status}` (Counter) - request volume and error mix per
  route. Low-cardinality by construction: this app has no path parameters, so the label set is a
  fixed handful of literal routes, never user input.
- `app_http_request_duration_seconds{endpoint}` (Histogram) - lets Grafana compute p95 latency
  per route via `histogram_quantile`, the standard way to see "is this endpoint getting slow"
  rather than just "is it being hit."
- `app_notes_stored` (Gauge) - the one *business* metric, not just HTTP plumbing: how many notes
  are persisted right now. It proves the metrics pipeline reflects real application state, not
  only traffic shape, and it visibly jumps when `POST /api/notes` is exercised.
- Everything under `process_*` (CPU seconds, RSS, start time) comes free from
  `prometheus_client`'s default collectors - no extra code, useful baseline for "is this Pod
  actually doing more work."

**Grafana** (`monitoring/grafana/`) has its Prometheus datasource and its one dashboard
(`monitoring/grafana/03-dashboard-configmap.yaml`, UID `cse644-python-web`) file-provisioned from
ConfigMaps at container start - there is no "click through the UI to wire this up" step that
would sit outside GitOps. The dashboard has five panels: request rate by endpoint, p95 latency by
endpoint, notes stored (stat), requests by HTTP status (pie), and process RSS memory.

**Generating and observing activity:** `bash scripts/12-generate-traffic.sh 40` sends 120 requests
(GET `/`, GET `/api/info`, POST `/api/notes`, repeated 40×) at the app. `evidence/logs/req05-observability.txt`
captures Prometheus query results *before* (`total requests: 316`) and *after*
(`total requests: 442`) that run, plus the resulting per-endpoint request-rate breakdown - the
metrics move because real work happened, not because they're static fixtures.

*Evidence format note:* this environment has no browser available to the automation driving this
repo, so "Prometheus collection" and "Grafana visualization" evidence is Prometheus/Grafana HTTP
API output (scrape-target health, datasource/dashboard provisioning confirmation, before/after
query results) rather than UI screenshots - explicitly allowed by the assignment ("Evidence may
use readable screenshots **or selected command output**"). Both UIs are fully usable via
`kubectl -n argocd port-forward svc/argocd-server 18080:443` /
`kubectl -n monitoring port-forward svc/grafana 13000:3000` if you want to look at them directly.

## Technical decisions and limitations

- **Argo CD over Flux:** chosen for its web UI (makes drift/sync/health trivial to show, even
  though this repo's own evidence is CLI-driven) and because it's the more widely recognized name
  to have hands-on experience with. Installed via a **pinned v3.5.1** manifest
  (`argocd/vendor/argocd-install-v3.5.1.yaml`), matching how Assignment 02 vendored a specific
  `ingress-nginx` release rather than tracking a moving tag.
- **Server-side apply for the Argo CD install:** the vendored install manifest's
  `applicationsets.argoproj.io` CRD is larger than the 256 KiB `kubectl apply`
  last-applied-configuration annotation limit. `kubectl apply --server-side --force-conflicts`
  tracks field ownership instead of that annotation and has no such ceiling
  (`scripts/10-install-argocd.sh`).
- **Single gunicorn worker for `python-web`:** `prometheus_client`'s default registry is
  per-process. Multiple workers would each keep their own counters, and gunicorn round-robins
  requests between them, so `/metrics` scraped from any one worker would silently under-report.
  The correct fix for a multi-worker deployment is `prometheus_client`'s multiprocess mode (a
  shared directory + a `child_exit` gunicorn hook); for this assignment's light demo traffic on a
  small local cluster, one worker keeps `/metrics` simple and correct instead.
- **ConfigMap changes need a paired annotation bump:** `python-web` reads its ConfigMap via
  `envFrom`, and env vars are only read once at container start - editing the ConfigMap alone
  does not restart existing Pods. Rather than adding a Kustomize `configMapGenerator` or a
  Reloader controller (more moving parts than this assignment needs), config-affecting commits
  also bump a `config-generation` annotation on the Pod template
  (`k8s/04-python-deployment.yaml`), which gives the ReplicaSet controller an actual rollout to
  perform.
- **No PersistentVolumeClaim for Prometheus or Grafana:** both use `emptyDir`. Losing TSDB
  history or Grafana's session state on a Pod restart is an acceptable, explicit trade-off for a
  short-lived local demo instance - not an oversight. `python-web`'s own data (the thing
  Requirement 5 of Assignment 02 was about) still has a real PVC.
- **Raw manifests over Helm/kube-prometheus-stack:** the Operator-based stack brings CRDs,
  Alertmanager, node-exporter, and kube-state-metrics that this one-app assignment doesn't need.
  Plain Deployments/ConfigMaps/Services stay legible and match the assignment's "must remain
  practical for a small local cluster" scope note.
- **The `cse644` KinD cluster is shared, not Assignment-03-owned:** it was created in Assignment
  02 and reused here rather than rebuilt, so this assignment's cleanup (below) intentionally does
  not delete it.
- **Windows/KinD LoadBalancer caveat (inherited from Assignment 02):** `nginx-web-loadbalancer`'s
  `EXTERNAL-IP` is only reachable via `docker exec <a kind node> curl ...`, not directly from the
  WSL2 shell - Docker Desktop's WSL2 backend doesn't route the WSL2 shell onto the `kind` Docker
  network. Not a GitOps or observability concern, just a standing local-networking limitation.

## Cleanup

`bash scripts/req06b-cleanup.sh`:
1. `argocd app delete cse644-app --cascade -y` and same for `cse644-monitoring` - cascade means
   Argo CD deletes every resource each Application manages, including the `cse644` and
   `monitoring` namespaces themselves (both are declared inside `k8s/00-namespace.yaml` and
   `monitoring/prometheus/00-namespace.yaml` respectively, so they're managed resources too).
2. `kubectl delete namespace argocd` - removes the controller itself.
3. Verifies all three namespaces return `NotFound`.

This removes everything Assignment 03 added. It **deliberately does not run
`kind delete cluster --name cse644`** - see "Technical decisions" above - so if you want the
cluster gone too, run that explicitly as a separate, final step.

Evidence: `evidence/logs/req06b-cleanup.txt` (produced when that script is run).
