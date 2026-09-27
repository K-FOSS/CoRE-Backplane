#!/bin/sh
set -eu

chart_dir=$(cd "$(dirname "$0")/.." && pwd)
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

helm lint "$chart_dir"
helm template default "$chart_dir" > "$tmp_dir/default.yaml"
helm template one "$chart_dir" --set chrony.replicas=1 > "$tmp_dir/one.yaml"
helm template existing "$chart_dir" --set keyAuthority.canonicalKey.existingClaim=protected-ntskeys > "$tmp_dir/existing.yaml"
helm template disabled "$chart_dir" --set nts.enabled=false > "$tmp_dir/disabled.yaml"

grep -q 'kind: StatefulSet' "$tmp_dir/default.yaml"
grep -q 'kind: Deployment' "$tmp_dir/default.yaml"
grep -q 'port: 323' "$tmp_dir/default.yaml"
grep -q 'protocol: UDP' "$tmp_dir/default.yaml"
grep -q 'chrony-command' "$tmp_dir/default.yaml"
grep -q 'claimName: protected-ntskeys' "$tmp_dir/existing.yaml"
if grep -q 'containerPort: 4460' "$tmp_dir/disabled.yaml"; then
  echo 'unexpected NTS port in disabled render' >&2
  exit 1
fi

if helm template invalid "$chart_dir" --set chrony.replicas=2 --set ntsScaling.enabled=false >/dev/null 2>&1; then
  echo 'expected unsafe scaling configuration to fail' >&2
  exit 1
fi
if helm template invalid-rwo "$chart_dir" --set keyAuthority.canonicalKey.accessMode=ReadWriteOnce >/dev/null 2>&1; then
  echo 'expected RWO canonical storage configuration to fail' >&2
  exit 1
fi
if helm template invalid-rotation "$chart_dir" --set chrony.ntsrotate=3600 >/dev/null 2>&1; then
  echo 'expected independent serving-key rotation to fail' >&2
  exit 1
fi
if helm template invalid-tls "$chart_dir" --set nts.secretName='' >/dev/null 2>&1; then
  echo 'expected missing NTS TLS Secret reference to fail' >&2
  exit 1
fi

echo 'render tests passed'
