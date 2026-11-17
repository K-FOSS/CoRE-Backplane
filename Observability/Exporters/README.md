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
rules, kube-state-metrics and hardware exporters. Host node-exporter metrics
are collected by the Alloy DaemonSets; kubelet/cAdvisor is also collected
there. API-server, controller-manager, scheduler, kube-proxy, etcd, and
kubelet ServiceMonitors are disabled; Alloy in [Collectors](../Collectors/)
owns the cluster-wide kubelet/cAdvisor scrape. API-server monitoring is
intentionally disabled because its histogram families add substantial
cardinality without being needed by the current operations workflow. In YVR
it also creates an Intel DRM
exporter DaemonSet for Intel `i915`/`xe` iGPUs and dGPUs, and an NVIDIA DCGM
Exporter DaemonSet for CUDA/NVIDIA GPUs. Both are restricted to amd64 GPU
nodes using Node Feature Discovery/device-plugin labels. The Prometheus
resource is configured with zero replicas; Grafana Alloy in
[Collectors](../Collectors/) consumes the generated monitor CRs and
remote-writes their samples to Mimir. The Exporters ApplicationSet's injected
Kustomize overlay moves smartctl resources and its monitor selection to
`kube-system`. Its ServiceMonitor replaces the scrape-target `instance` label
with the Kubernetes endpoint's node name, matching the node identity used by
the hardware dashboard's node-exporter queries. The
kube-prometheus-stack Grafana datasource ConfigMap is disabled because the
standalone Grafana deployment owns datasource configuration.

The upstream Kubernetes mixin dashboards are always rendered, even though the
stack's Prometheus and Grafana workloads are disabled; the standalone dashboard
syncer imports their ConfigMaps. The chart pins
[kube-prometheus-stack 93.3.0](https://github.com/prometheus-community/helm-charts/tree/kube-prometheus-stack-93.3.0/charts/kube-prometheus-stack),
the current upstream release. Its cluster and multi-cluster resource dashboards
are enabled in global mode. The chart renders a visible cluster selector where
the dashboard supports one, and the syncer puts these dashboards in the shared
`Global` folder with their upstream UIDs. Every active cluster can therefore
supply the same dashboard definition without creating cluster-specific copies.
The ConfigMaps carry both `grafana_dashboard: 'true'` and
`grafana_dashboard_global: 'true'`; the `grafana_folder: 'Global'` annotation
routes their data into the importer's global folder. Their `kube-state-metrics`
queries require
the Alloy ServiceMonitor path to preserve the standard
`job="kube-state-metrics"` label, while node dashboards use the Alloy host
collector's `job="node-exporter"`, `instance`, and `nodename` labels.
The generated CoreDNS dashboard is patched into the `Infrastructure` Grafana
folder by the owning [Exporters ApplicationSet](../../Apps/Observability/Exporters.yaml).

This stack also owns the `Hardware Exporters` dashboard and the pinned
[Grafana Node Exporter Full dashboard 1860, revision 45](https://grafana.com/api/dashboards/1860/revisions/45/download).
Their labeled ConfigMaps are in `core-prod` and import into the
`Infrastructure` folder. The repository-managed hardware dashboard uses the
Alloy node-exporter series; Node Exporter Full uses its `job`, `nodename`, and
`instance` selectors. The syncer applies a local 15-second minimum query
interval and refresh to Node Exporter Full, while the WAN-GW2 scrape runs every
30 seconds. The exporter chart's standalone Prometheus and Grafana workloads
remain disabled; Alloy and the dashboard syncer own collection and import.

The stack also imports Grafana's pinned
[SMARTctl Exporter dashboard 22604, revision 4](https://grafana.com/api/dashboards/22604/revisions/4/download)
through [`SmartctlExporterDashboard.yaml`](templates/SmartctlExporterDashboard.yaml).
The upstream dashboard is specific to
[`prometheus-community/smartctl_exporter`](https://github.com/prometheus-community/smartctl_exporter)
and uses `smartctl_device_smart_status`, `smartctl_device`, and the exporter
device metadata labels. Its `node` variable matches the node-name `instance`
relabeling applied by the owning ApplicationSet. The [dashboard
syncer](../Dashboards/README.md) adds a Prometheus datasource picker from the
upstream `DS_PROMETHEUS` import input when it imports this dashboard. This keeps
the upstream JSON intact while resolving its datasource references in Grafana.
The URL is revision-pinned; update it deliberately after reviewing a newer
dashboard revision and its queries against the deployed exporter.

The stack also imports [retn0's SMARTctl Exporter Dashboard 24922, revision 1](https://grafana.com/grafana/dashboards/24922-retn0-s-smartctl-exporter-dashboard/)
through [`SmartctlExtendedDashboard.yaml`](templates/SmartctlExtendedDashboard.yaml).
This community dashboard adds a 19-panel disk overview with health, capacity,
temperature, lifetime, read/write, NVMe spare, and SATA reliability views. The
existing 22604 dashboard remains available for comparison. The installed
`prometheus-smartctl-exporter` chart does not bundle a dashboard; the pinned
Grafana revision is imported through the repository dashboard syncer. Its
`DS_PROMETHEUS` input becomes the local datasource picker, and the `node`
variable uses the ApplicationSet's node-name `instance` relabeling. Queries
were checked against the metric names and device labels exposed by the YVR,
DC1 Talos, and legacy K3s exporters. NVMe and SATA panels show no data on
hosts without those device types; the error log panel uses a metric currently
present on DC1 Talos but absent on YVR.

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
expensive remaining metric sources are kubelet/cAdvisor on every node and
kube-state-metrics. Monitor sample and target limits are zero (unbounded), so
review those sources before enabling additional broad scrape jobs.

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
