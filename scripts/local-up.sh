#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
context="${KAGENT_CONTEXT:-kind-kagent}"
if [[ "$context" != kind-kagent ]]; then
  echo 'This local baseline targets kind-kagent only.' >&2
  exit 1
fi
for executable in kubectl helm ruby shasum; do command -v "$executable" >/dev/null; done
[[ -x ./kagent-darwin-arm64 ]]
./kagent-darwin-arm64 version | ruby -rjson -e 'abort "Use the pinned alpha13 CLI" unless JSON.parse(STDIN.read)["kagent_version"]=="1.0.0-alpha13"'
while read -r digest artifact; do
  [[ ! -f "$artifact" ]] || printf '%s  %s\n' "$digest" "$artifact" | shasum -a 256 -c -
done < kagent-config/artifacts.sha256
./kagent-darwin-arm64 --config kagent-install-config.yaml config validate
# Resume only this project's existing kind node; never start/stop Docker Desktop's node.
if command -v docker >/dev/null && docker inspect kagent-control-plane >/dev/null 2>&1; then
  cluster_label="$(docker inspect kagent-control-plane --format '{{ index .Config.Labels "io.x-k8s.kind.cluster" }}')"
  [[ "$cluster_label" == kagent ]] || { echo 'Unexpected kind node ownership.' >&2; exit 1; }
  if [[ "$(docker inspect kagent-control-plane --format '{{.State.Running}}')" != true ]]; then
    docker start kagent-control-plane
  fi
  for ((attempt=0; attempt<60; attempt++)); do
    if kubectl --context "$context" --request-timeout=3s get namespace kube-system >/dev/null 2>&1; then break; fi
    sleep 2
  done
  kubectl --context "$context" wait --for=condition=Ready node/kagent-control-plane --timeout=120s
fi
kubectl --context "$context" get namespace kube-system >/dev/null
architecture="$(kubectl --context "$context" get nodes -o jsonpath='{.items[*].status.nodeInfo.architecture}')"
case " $architecture " in
  *" arm64 "*|*" amd64 "*) ;;
  *) echo "Unsupported node architecture: $architecture (need arm64 or amd64)." >&2; exit 1 ;;
esac
# CLI has no --context flag: use a temporary single-context kubeconfig.
# This does not change ~/.kube/config or its current-context.
umask 077
task_kubeconfig="$(mktemp)"
trap 'rm -f "$task_kubeconfig"' EXIT
kubectl --context "$context" config view --raw --minify > "$task_kubeconfig"
export KUBECONFIG="$task_kubeconfig"
kubectl --context "$context" create namespace kagent --dry-run=client -o yaml | kubectl --context "$context" apply -f -
if ! kubectl --context "$context" get secret kagent-deepseek-runtime -n kagent >/dev/null 2>&1; then
  # Input comes from the environment or the already ignored local Secret file.
  # Output is piped directly to Kubernetes; it is never a Helm value.
  ruby -ryaml -rjson -rbase64 <<'RUBY' | kubectl --context "$context" apply -f -
key = ENV['DEEPSEEK_API_KEY']
if key.to_s.empty? && File.file?('deepseek-secret.yaml')
  source = YAML.load_file('deepseek-secret.yaml')
  key = source.dig('stringData', 'DEEPSEEK_API_KEY') || Base64.strict_decode64(source.fetch('data').fetch('DEEPSEEK_API_KEY'))
end
abort 'Provide DEEPSEEK_API_KEY or an ignored deepseek-secret.yaml' if key.to_s.empty? || key.match?(/YOUR_|REPLACE|placeholder|dummy|test-key|sk-xxx/i)
puts JSON.generate({apiVersion:'v1',kind:'Secret',metadata:{name:'kagent-deepseek-runtime',namespace:'kagent'},type:'Opaque',stringData:{DEEPSEEK_API_KEY:key}})
RUBY
fi
if ! helm status kagent -n kagent >/dev/null 2>&1; then
  # Bootstrap only: never give the installer a real key to persist in Helm.
  OPENAI_API_KEY=bootstrap-placeholder ./kagent-darwin-arm64 --config kagent-install-config.yaml install
fi
kubectl --context "$context" scale deployment ate-api-server ate-controller atenet-egress atenet-router k8s-credential-provider rustfs -n ate-system --replicas=1
kubectl --context "$context" scale deployment kagent-postgresql -n kagent --replicas=1
# Local registry mirror drops HTTP/2 layer streams; atelet downloads OCI layers itself.
kubectl --context "$context" set env daemonset/atelet -n ate-system GODEBUG=http2client=0
kubectl --context "$context" rollout status daemonset/atelet -n ate-system --timeout=180s
kubectl --context "$context" rollout status deployment/ate-api-server -n ate-system --timeout=180s
kubectl --context "$context" rollout status deployment/kagent-postgresql -n kagent --timeout=180s
# Use the checked-in alpha13 archives when available, otherwise the pinned OCI charts.
chart=oci://ghcr.io/kagent-dev/kagent/helm/kagent
crd_chart=oci://ghcr.io/kagent-dev/kagent/helm/kagent-crds
[[ ! -f kagent-1.0.0-alpha13.tgz ]] || chart=./kagent-1.0.0-alpha13.tgz
[[ ! -f kagent-crds-1.0.0-alpha13.tgz ]] || crd_chart=./kagent-crds-1.0.0-alpha13.tgz
helm upgrade --install kagent-crds "$crd_chart" -n kagent --version 1.0.0-alpha13 --server-side=false
# Runtime credentials are external to Helm. Do not pass a real key as a value.
kubectl --context "$context" get secret kagent-deepseek-runtime -n kagent >/dev/null
helm upgrade kagent "$chart" -n kagent --version 1.0.0-alpha13 --reset-values \
  -f kagent-config/helm/values.yaml --server-side=false --wait --timeout 180s
kubectl --context "$context" apply --dry-run=server -f kagent-config/crds/
kubectl --context "$context" apply -f kagent-config/crds/
./scripts/verify-readonly.sh
kubectl --context "$context" wait --for=condition=Ready agent/sre-readonly -n kagent --timeout=600s
kubectl --context "$context" get pods,agents.api.kagent.dev,harnesses.api.kagent.dev -n kagent
