#!/usr/bin/env bash
# Assert the Multus paths in a fully rendered Network/Base manifest.
set -euo pipefail
(( $# > 0 )) || { printf 'Pass at least one rendered manifest\n' >&2; exit 2; }

for manifest in "$@"; do
  yq -s -e '
    [.[] | select(.kind == "DaemonSet" and .metadata.namespace == "kube-system" and .metadata.name == "kube-multus-ds")] as $daemonsets |
    ($daemonsets | length) == 1 and
    ($daemonsets[0].spec.template.spec.volumes | map(select(.name == "host-run-k8s-cni-cncf-io")) | length) == 1 and
    ($daemonsets[0].spec.template.spec.volumes | map(select(.name == "host-run-k8s-cni-cncf-io"))[0].hostPath == {"path": "/run/k8s.cni.cncf.io", "type": "DirectoryOrCreate"}) and
    ($daemonsets[0].spec.template.spec.volumes | map(select(.name == "host-run-netns")) | length) == 1 and
    ($daemonsets[0].spec.template.spec.volumes | map(select(.name == "host-run-netns"))[0].hostPath.path == "/run/netns/") and
    ($daemonsets[0].spec.template.spec.containers | map(select(.name == "kube-multus"))[0].volumeMounts | any(.name == "host-run-k8s-cni-cncf-io" and .mountPath == "/run/k8s.cni.cncf.io")) and
    ($daemonsets[0].spec.template.spec.containers | map(select(.name == "kube-multus"))[0].volumeMounts | any(.name == "host-run-netns" and .mountPath == "/run/netns" and .mountPropagation == "HostToContainer"))
  ' "$manifest" > /dev/null
done
