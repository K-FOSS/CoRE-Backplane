#!/usr/bin/env bash
# Requires Helm, rg, and jq-backed yq. Pass both rendered injected values files.
set -euo pipefail
umask 077
chart_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
dc1_values=${1:?Pass DC1 injected values}
home1_values=${2:?Pass Home1 injected values}
test_dir=$(mktemp -d /tmp/core-dns-tests.XXXXXX)
index=0
for site_values in "$dc1_values" "$home1_values"; do
  index=$((index + 1))
  helm lint "$chart_dir" -f "$site_values"
  helm template dns-test "$chart_dir" -n kube-system -f "$site_values" > "$test_dir/$index.yaml"
  yq -s -e '[.[] | select(.metadata.name == "coredns" or .metadata.name == "system:coredns")] | length == 5' "$test_dir/$index.yaml"
  yq -s -e '[.[] | select(.kind == "Deployment" and .metadata.name == "coredns")][0] | .spec.replicas == 4 and .spec.selector.matchLabels["k8s-app"] == "kube-dns" and .spec.template.spec.serviceAccountName == "coredns" and .spec.template.spec.dnsPolicy == "Default"' "$test_dir/$index.yaml"
  domain=$(yq -r '.kubeDNS.clusterDomain' "$site_values")
  yq -s -e '[.[] | select(.kind == "Deployment" and .metadata.name == "coredns")][0].spec.template.spec.containers[0] | any(.env[]; .name == "NS_ID" and .valueFrom.fieldRef.fieldPath == "status.podIP") and .livenessProbe.httpGet.path == "/health" and .livenessProbe.httpGet.port == 8080 and .livenessProbe.initialDelaySeconds == 60 and .readinessProbe.httpGet.path == "/ready" and .readinessProbe.httpGet.port == 8181' "$test_dir/$index.yaml"
  yq -s -e '[.[] | select(.kind == "Deployment" and .metadata.name == "coredns")][0].spec.template.spec.containers[0].image == "registry.k8s.io/coredns/coredns:v1.13.2"' "$test_dir/$index.yaml"
  yq -s '[.[] | select(.kind == "Deployment" and .metadata.name == "coredns")][0].spec.template.spec.containers[0] | {image,env,livenessProbe,readinessProbe}' "$test_dir/$index.yaml" > "$test_dir/$index.health.json"
  yq -s -r --arg domain "$domain" '[.[] | select(.kind == "ConfigMap" and .metadata.name == "coredns")][0].data.Corefile | split($domain) | join("CLUSTER_DOMAIN")' "$test_dir/$index.yaml" > "$test_dir/$index.Corefile"
  rg -q 'forward \. 1\.1\.1\.1 8\.8\.8\.8 \{' "$test_dir/$index.Corefile"
  rg -q 'kubernetes cluster.local CLUSTER_DOMAIN in-addr.arpa ip6.arpa' "$test_dir/$index.Corefile"
done
diff -u "$test_dir/1.Corefile" "$test_dir/2.Corefile"
diff -u "$test_dir/1.health.json" "$test_dir/2.health.json"
for missing in 'kubeDNS.clusterDomain=' 'kubeDNS.image='; do
  if helm template missing "$chart_dir" -f "$dc1_values" --set "$missing" > "$test_dir/missing.yaml" 2> "$test_dir/missing.err"; then
    printf 'Expected failure for %s\n' "$missing" >&2
    exit 1
  fi
  rg -q 'kubeDNS\.' "$test_dir/missing.err"
done
helm template disabled "$chart_dir" -f "$dc1_values" --set kubeDNS.enabled=false > "$test_dir/disabled.yaml"
yq -s -e '[.[] | select(.metadata.name == "coredns" or .metadata.name == "system:coredns")] | length == 0' "$test_dir/disabled.yaml"
printf 'CoreDNS tests passed. Restricted generated outputs: %s\n' "$test_dir"
