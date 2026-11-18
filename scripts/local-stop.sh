#!/usr/bin/env bash
set -euo pipefail
context=kind-kagent
node=kagent-control-plane
command -v kubectl >/dev/null
command -v docker >/dev/null
cluster_label="$(docker inspect "$node" --format '{{ index .Config.Labels "io.x-k8s.kind.cluster" }}')"
[[ "$cluster_label" == kagent ]] || { echo 'Unexpected kind node ownership.' >&2; exit 1; }
if [[ "$(docker inspect "$node" --format '{{.State.Running}}')" != true ]]; then
  echo 'kind-kagent is already stopped. Data is retained.'
  exit 0
fi
kubectl --context "$context" --request-timeout=8s get namespace kagent >/dev/null
# Stop new Agent requests before draining WorkerPool capacity.
kubectl --context "$context" scale deployment kagent-controller kagent-ui kagent-tools kagent-kmcp-controller-manager -n kagent --replicas=0
kubectl --context "$context" patch workerpool kagent-default -n kagent --type=merge -p '{"spec":{"replicas":0}}'
kubectl --context "$context" rollout status deployment/kagent-default -n kagent --timeout=60s
# Stop Substrate before its database and object storage.
kubectl --context "$context" scale deployment ate-api-server ate-controller atenet-egress atenet-router k8s-credential-provider -n ate-system --replicas=0
kubectl --context "$context" scale deployment kagent-postgresql -n kagent --replicas=0
kubectl --context "$context" scale deployment rustfs -n ate-system --replicas=0
# Allow database and storage pods to exit cleanly before stopping the node.
kubectl --context "$context" wait --for=delete pod -n kagent --all --timeout=90s
kubectl --context "$context" wait --for=delete pod -n ate-system -l app.kubernetes.io/name=rustfs --timeout=90s
docker stop --timeout 45 "$node"
echo 'kind-kagent stopped; node filesystem, volumes, Secrets and conversations retained.'
echo 'Resume with ./scripts/local-up.sh'
