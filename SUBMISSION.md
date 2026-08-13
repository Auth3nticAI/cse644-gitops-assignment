# CSE644 Cloud Computing — Assignment 03 · GitOps and Application Observability · Submission

## Required submission items

| Item | Value |
|---|---|
| **Name** | Tray Branch |
| **GitHub username and repository link** | [Auth3nticAI](https://github.com/Auth3nticAI) / https://github.com/Auth3nticAI/cse644-gitops-assignment |
| **Kubernetes environment used** | KinD (Kubernetes in Docker), cluster `cse644` — 1 control-plane + 1 worker node, `kindest/node:v1.34.0`. Same cluster carried over from Assignment 02 (see README "Technical decisions" for why it isn't rebuilt or torn down by this assignment's cleanup). |
| **GitOps tool selected** | Argo CD v3.5.1 (pinned, vendored install manifest — [`argocd/vendor/argocd-install-v3.5.1.yaml`](argocd/vendor/argocd-install-v3.5.1.yaml)) |
| **Container image and version** | `auth3nticai/cse644-gitops-python:v2` (rebuilt from Assignment 02's `python-web`, adds a Prometheus `/metrics` endpoint). `nginx-web` and `haproxy-edge` are unchanged from Assignment 02: `auth3nticai/cse644-k8s-nginx:v1`, `auth3nticai/cse644-k8s-haproxy:v1`. |
| **Link to the repository README** | [`README.md`](README.md) |

---

## Required evidence checklist

| # | Outcome | Evidence |
|---|---|---|
| 1 | Kubernetes environment | [`req01-environment.txt`](evidence/logs/req01-environment.txt) |
| 1 | Repository and revision history | [`req01-environment.txt`](evidence/logs/req01-environment.txt) (remote, branch, `git log`) |
| 2 | GitOps deployment status | [`req02-gitops-deployment.txt`](evidence/logs/req02-gitops-deployment.txt) |
| 2 | Application access, identifiable as this student's work | [`req02-gitops-deployment.txt`](evidence/logs/req02-gitops-deployment.txt) |
| 3 | A Git-driven change | [`req03-change-and-reconciliation.txt`](evidence/logs/req03-change-and-reconciliation.txt) Part A |
| 3 | Reconciliation of a live-state difference | [`req03-change-and-reconciliation.txt`](evidence/logs/req03-change-and-reconciliation.txt) Part B |
| 4 | Controlled failure and Git-based recovery | [`req04-failure-and-recovery.txt`](evidence/logs/req04-failure-and-recovery.txt) |
| 5 | Prometheus collection | [`req05-observability.txt`](evidence/logs/req05-observability.txt) |
| 5 | Grafana visualization | [`req05-observability.txt`](evidence/logs/req05-observability.txt) |
| 6 | Validation (app + GitOps + monitoring + dashboard together) | [`req06a-validate.txt`](evidence/logs/req06a-validate.txt) |
| 6 | Cleanup, and verification it's complete | [`req06b-cleanup.txt`](evidence/logs/req06b-cleanup.txt) — produced by `scripts/req06b-cleanup.sh`, run once the live environment is done being reviewed (script is committed and ready; see README "Cleanup") |

Every `scripts/reqNN-*.sh` logs full detail to its matching `evidence/logs/reqNN-*.txt` and prints
only a `[PASS]`/`[CHECK]` line plus the log's line count to the console.

---

## Requirement-to-artifact map

| Req | Artifact |
|---|---|
| 1 Version-controlled platform | This repository: `apps/`, `k8s/`, `argocd/`, `monitoring/`, `kind/`, `scripts/`, this README |
| 2 GitOps deployment | [`argocd/application-app.yaml`](argocd/application-app.yaml), [`argocd/application-monitoring.yaml`](argocd/application-monitoring.yaml) |
| 3 Change and reconciliation | Commit `af4e1e2` (nginx-web replicas, python-web ConfigMap) + live `kubectl scale` drift/self-heal, both in [`req03-change-and-reconciliation.txt`](evidence/logs/req03-change-and-reconciliation.txt) |
| 4 Controlled failure and recovery | Commit `b4f2845` (bad image tag) reverted by commit `7244ee8`, in [`req04-failure-and-recovery.txt`](evidence/logs/req04-failure-and-recovery.txt) |
| 5 Application observability | [`monitoring/prometheus/`](monitoring/prometheus/), [`monitoring/grafana/`](monitoring/grafana/), `/metrics` in [`apps/python-web/app.py`](apps/python-web/app.py) |
| 6 Validation and cleanup | [`scripts/req06a-validate.sh`](scripts/req06a-validate.sh), [`scripts/req06b-cleanup.sh`](scripts/req06b-cleanup.sh) |

---

## Security statement

No password, kubeconfig, API key, private key, or environment file containing real secrets
appears in this repository or in any committed log.

Two committed `Secret` manifests carry clearly-labeled **dummy** values, consistent with
Assignment 02's precedent:
- [`k8s/13-python-secret.yaml`](k8s/13-python-secret.yaml) — `dummy-api-key-DO-NOT-USE-93f7c2a1`
  (unchanged from Assignment 02; the app only ever reports whether it's *present*, never its value)
- [`monitoring/grafana/00-secret.yaml`](monitoring/grafana/00-secret.yaml) — Grafana admin
  password `cse644-demo-not-a-real-password`, used only inside a `kubectl port-forward`'d local
  instance never exposed beyond this machine

The Argo CD initial-admin password and the Grafana admin password are both retrieved into shell
variables and consumed directly by `argocd login` / API calls in the scripts that need them
(`scripts/11-argocd-login.sh`, `scripts/lib/grafana-check.sh`) — never echoed to a log file or
committed anywhere.

As required, the README states plainly that **Kubernetes Secrets are base64-encoded, not
encrypted**, in the API server's underlying etcd store by default (full explanation carried over
from Assignment 02).

[`scripts/secret-scan.sh`](scripts/secret-scan.sh) scans the whole tree for token-, key-, and
password-shaped strings (excluding the intentional dummy values above) and reported **CLEAN**
before every push.
