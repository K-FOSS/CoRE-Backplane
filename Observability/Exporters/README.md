# Metrics exporters

This chart deploys selected parts of the pinned
[`kube-prometheus-stack`](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack),
plus the component-specific
[`smartctl-exporter`](https://github.com/prometheus-community/helm-charts/tree/main/charts/prometheus-smartctl-exporter)
and [`ipmi-exporter`](https://github.com/prometheus-community/helm-charts/tree/main/charts/prometheus-ipmi-exporter)
charts, plus the Intel/DRM
[`drm-exporter`](https://github.com/home-operations/drm-exporter/tree/main/charts/drm-exporter)
chart and NVIDIA's
[`dcgm-exporter`](https://github.com/NVIDIA/dcgm-exporter/tree/main/deployment)
chart. The
[`core-observability-exporters` ApplicationSet](../../Apps/Observability/Exporters.yaml)
continues to target the existing infrastructure and `dc1-k3s-node1` clusters.
Only the Intel DRM and NVIDIA DCGM exporters are enabled for the
`core-home1-talos-prod` YVR application; the base exporter stack remains
enabled wherever it was previously deployed.

## Current behavior

The stack creates Prometheus Operator CRDs/controllers, recording and alerting
rules, kube-state-metrics, node-exporter, kubelet/cAdvisor and API-server
ServiceMonitors, and hardware exporters. In YVR it also creates an Intel DRM
exporter DaemonSet for Intel `i915`/`xe` iGPUs and dGPUs, and an NVIDIA DCGM
Exporter DaemonSet for CUDA/NVIDIA GPUs. Both are restricted to amd64 GPU
nodes using Node Feature Discovery/device-plugin labels. The Prometheus
resource is configured with zero replicas; Grafana Alloy in
[Collectors](../Collectors/) consumes the generated monitor CRs and
remote-writes their samples to Mimir. Kustomize moves smartctl resources and
its monitor selection to `kube-system`.

The GPU exporters require host GPU enablement: NFD must publish the Intel PCI
label `feature.node.kubernetes.io/pci-0300_8086.present: 'true'`, and the
NVIDIA driver, container runtime integration, and device plugin must publish
`nvidia.com/gpu.present: 'true'`. The DRM exporter needs `/dev/dri` and
read-only `/sys`; its image is amd64-only. Intel `xe` engine utilization
requires Linux kernel 6.16 or newer. On Talos, the Intel iGPU MSR fallback is
not enabled, so package temperature/power may be absent; see the exporter
[host-access requirements](https://github.com/home-operations/drm-exporter/blob/main/charts/drm-exporter/README.md#host-access-and-privileges).

This stack contributes monitored endpoints and cardinality, but the repeated
Kubernetes API watches are created by every Alloy DaemonSet pod. The most
expensive metric sources are kubelet/cAdvisor on every node, kube-state-metrics,
and API-server histograms. Existing relabel rules drop several noisy histogram
buckets and container series, but monitor sample and target limits are zero
(unbounded).

The committed IPMI module contains upstream example credentials. They are
deployable placeholders and must be replaced with a Secret-backed mechanism
before relying on IPMI collection; do not put real credentials in this file.

## Verification and lifecycle

Render both Helm and Kustomize output, then confirm ServiceMonitor selectors,
namespaces, scrape intervals, GPU-node selectors, and the absence of a
Prometheus pod. In-cluster, check Intel `/metrics` for `drm_info` and NVIDIA
`/metrics` for `DCGM_` families, then verify exporter targets in Alloy and Mimir
accepted/rejected sample metrics. Roll back via Git/Argo CD. Removing the
stack also removes monitor definitions and can invalidate rules and dashboards
even when exporters remain running.
