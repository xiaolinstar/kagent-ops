#!/usr/bin/env bash
set -euo pipefail
context="${KAGENT_CONTEXT:-kind-kagent}"
identity=system:serviceaccount:kagent:kagent-tools
check() {
  local expected="$1" actual
  shift
  actual="$(kubectl --context "$context" auth can-i "$@" --as="$identity" 2>/dev/null || true)"
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: expected $expected, got $actual: $*" >&2
    exit 1
  fi
  echo "PASS: $* => $actual"
}
check yes get pods -n kagent
check yes get pods --subresource=log -n kagent
check no create pods -n kagent
check no delete pods -n kagent
check no patch deployments.apps -n kagent
check no create pods --subresource=exec -n kagent
check no get secrets -n kagent
check no list secrets -n kagent
check no get pods -n default
check no get pods -n kube-system
check no create rolebindings.rbac.authorization.k8s.io -n kagent
