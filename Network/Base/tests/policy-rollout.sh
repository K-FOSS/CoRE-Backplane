#!/usr/bin/env bash
# Requires Helm and jq-backed (kislyuk) yq; pass representative injected values.
set -euo pipefail
umask 077
chart_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
dc1_values=${1:?Pass DC1 ApplicationSet-injected values file}
home1_values=${2:?Pass Home1 ApplicationSet-injected values file}
test_dir=$(mktemp -d /tmp/network-policy-tests.XXXXXX)

helm lint "$chart_dir" -f "$dc1_values"
helm lint "$chart_dir" -f "$home1_values"
helm template test-dc1 "$chart_dir" -n kube-system -f "$dc1_values" > "$test_dir/dc1.yaml"
helm template test-home1 "$chart_dir" -n kube-system -f "$home1_values" > "$test_dir/home1.yaml"
candidate_count() {
  yq -s '[.[] | select(.kind == "CiliumClusterwideNetworkPolicy" and (.metadata.name | startswith("core-audit-")))] | length' "$1"
}
[[ $(candidate_count "$test_dir/dc1.yaml") == 3 ]]
[[ $(candidate_count "$test_dir/home1.yaml") == 0 ]]
yq -s -e '[.[] | select(.kind == "CiliumClusterwideNetworkPolicy" and (.metadata.name | startswith("core-audit-")))] | all(.spec.endpointSelector.matchLabels["k8s:io.kubernetes.pod.namespace"] != null and (.spec.endpointSelector.matchLabels | length) > 1 and (.spec | has("ingressDeny") | not) and (.spec | has("egressDeny") | not))' "$test_dir/dc1.yaml"

expect_guard_failure() {
  if helm template guard "$chart_dir" -f "$dc1_values" --set "$1" > "$test_dir/guard.yaml" 2> "$test_dir/guard.err"; then
    printf 'Expected render guard failure for %s\n' "$1" >&2
    exit 1
  fi
  rg -q 'candidates require' "$test_dir/guard.err"
}
expect_guard_failure 'cilium.policyAuditMode=false'
expect_guard_failure 'cilium.policyEnforcementMode=always'
expect_guard_failure 'cilium.policyEnforcementMode=never'
helm template disabled "$chart_dir" -f "$dc1_values" --set policyRollout.enabled=false > "$test_dir/disabled.yaml"
[[ $(candidate_count "$test_dir/disabled.yaml") == 0 ]]
printf 'Policy rollout tests passed. Restricted generated outputs: %s\n' "$test_dir"
