#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
context="${1:?Usage: scripts/cloud-install.sh <ecs-context>}"
case "$context" in kind-kagent|docker-desktop) echo "Select the dedicated ECS context." >&2; exit 1;; esac
: "${KAGENT_CLI:?Set KAGENT_CLI to the absolute path of the verified Linux CLI}"
[[ "$(uname -s)" == Linux && "$KAGENT_CLI" == /* && -x "$KAGENT_CLI" ]]
case "$(uname -m)" in
  x86_64) cli_name=kagent-linux-amd64 ;;
  aarch64|arm64) cli_name=kagent-linux-arm64 ;;
  *) echo 'Unsupported Linux architecture' >&2; exit 1 ;;
esac
expected="$(awk -v file="$cli_name" '$2 == file { print $1 }' deploy/cloud/cli.sha256)"
actual="$(sha256sum "$KAGENT_CLI" | awk '{print $1}')"
[[ "$actual" == "$expected" ]] || { echo 'CLI checksum mismatch' >&2; exit 1; }
# Shared installer config at repo root (same as local-up).
"$KAGENT_CLI" --config kagent-install-config.yaml config validate

umask 077
cloud_kubeconfig="$(mktemp)"
trap 'rm -f "$cloud_kubeconfig"' EXIT
# Write minify BEFORE exporting KUBECONFIG (empty tempfile breaks kubectl → localhost:8080).
kubectl --context "$context" config view --raw --flatten --minify > "$cloud_kubeconfig"
export KUBECONFIG="$cloud_kubeconfig"
kubectl get nodes
kubectl version -o json | ruby -rjson -e '
  version = JSON.parse(STDIN.read).fetch("serverVersion")
  abort "The pilot baseline targets Kubernetes 1.37.x" unless version["major"] == "1" && version["minor"].to_i == 37
'
kubectl get secret kagent-deepseek-runtime -n kagent -o go-template='{{if index .data "DEEPSEEK_API_KEY"}}{{"present"}}{{end}}' | grep -qx present

# The installer manages PostgreSQL and Substrate. Only a placeholder goes into Helm.
if ! helm status kagent -n kagent >/dev/null 2>&1; then
  OPENAI_API_KEY=bootstrap-placeholder "$KAGENT_CLI" --config kagent-install-config.yaml install
fi
# Prefer local chart on air-gapped / slow-GHCR hosts; fall back to OCI.
helm_extra=()
if helm upgrade --help 2>/dev/null | grep -q -- '--server-side'; then
  helm_extra+=(--server-side=false)
fi
if [[ -f kagent-1.0.0-alpha13.tgz ]]; then
  helm upgrade --install kagent ./kagent-1.0.0-alpha13.tgz -n kagent \
    --reset-values "${helm_extra[@]}" -f kagent-config/helm/values.yaml --wait --timeout 15m
else
  helm upgrade --install kagent oci://ghcr.io/kagent-dev/kagent/helm/kagent -n kagent \
    --version 1.0.0-alpha13 --reset-values "${helm_extra[@]}" \
    -f kagent-config/helm/values.yaml --wait --timeout 15m
fi

# atelet pulls ADK layers itself; HTTP/2 against mirrors often breaks without this.
kubectl -n ate-system set env daemonset/atelet GODEBUG=http2client=0
kubectl -n ate-system rollout status daemonset/atelet --timeout=180s

KAGENT_CONTEXT="$context" ./scripts/verify-readonly.sh

# Shared Agent + Harness (multi-arch). Do not apply crds/agents/ extras here.
kubectl apply --dry-run=server -f kagent-config/crds/harness.yaml -f kagent-config/crds/agents.yaml
kubectl apply -f kagent-config/crds/harness.yaml -f kagent-config/crds/agents.yaml
kubectl wait -n kagent --for=condition=Ready agent/sre-readonly --timeout=600s
