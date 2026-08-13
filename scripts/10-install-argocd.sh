#!/usr/bin/env bash
# CSE644 Assignment 03 - install Argo CD v3.5.1 (pinned, vendored manifest)
# into its own namespace. This step is applied directly with kubectl, not
# through Argo CD itself, because Argo CD has to exist before it can manage
# anything - the controller's own installation is the one thing in this
# platform that is bootstrapped rather than GitOps-managed.
set -euo pipefail
cd "$(dirname "$0")/.."

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# Server-side apply: the vendored install.yaml's CRDs (notably
# applicationsets.argoproj.io) exceed the 256KiB last-applied-configuration
# annotation limit that client-side `kubectl apply` enforces. Server-side
# apply tracks field ownership instead of that annotation, so it has no such
# size ceiling.
kubectl apply -n argocd --server-side --force-conflicts -f argocd/vendor/argocd-install-v3.5.1.yaml

echo "Waiting for Argo CD server to be available..."
kubectl -n argocd wait --for=condition=available --timeout=300s deployment/argocd-server
kubectl -n argocd wait --for=condition=available --timeout=300s deployment/argocd-repo-server
kubectl -n argocd wait --for=condition=available --timeout=300s deployment/argocd-applicationset-controller

kubectl -n argocd get pods
