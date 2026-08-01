# Telemetry collectors

This chart deploys four [Grafana Alloy](https://grafana.com/docs/alloy/latest/)
roles and
optional [Vector](https://vector.dev/docs/setup/installation/package-managers/helm/)
collectors. The
[`core-observability-collectors` ApplicationSet](../../Apps/Observability/Collectors.yaml)
targets `core-dc1-talos-prod`, `core-home1-talos-prod`, and `dc1-k3s-node1`,
injecting the cluster and datacentre labels.

The chart also installs the
[`alloy-mixin`](https://github.com/portefaix/helm-charts/tree/master/charts/alloy-mixin)
and [Prometheus Operator CRDs](https://github.com/prometheus-community/helm-charts/tree/main/charts/prometheus-operator-crds).
All dependency versions are pinned in `Chart.yaml`; generated dependency
archives remain ignored and must not be force-added.

## Current topology

Three signal-specific DaemonSets run on every node:

- `alloy-logs` reads and parses CRI logs directly from `/var/log/pods` with the
  public-preview
  [`otelcol.receiver.filelog`](https://grafana.com/docs/alloy/latest/reference/components/otelcol/otelcol.receiver.filelog/),
  retaining its offsets in Alloy's pod-local storage.
- `alloy-metrics` uses
  [`prometheus.exporter.unix`](https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.exporter.unix/)
  against read-only host root, proc, and sys mounts and also scrapes its own
  Alloy metrics.
- `alloy-otlp` accepts node-local OTLP/gRPC and OTLP/HTTP through a ClusterIP
  Service with `internalTrafficPolicy: Local`.

Each DaemonSet batches its signal and uses
[`otelcol.exporter.otlp`](https://grafana.com/docs/alloy/latest/reference/components/otelcol/otelcol.exporter.otlp/)
over plaintext OTLP/gRPC to the existing `*-collectors-alloy` Service. The root
ApplicationSet injects the exact central service FQDN, cluster, and datacentre
values. The DaemonSets do not hold or use direct Loki, Mimir, or Tempo
destinations.

`alloy` remains a three-replica Deployment with a PodDisruptionBudget. It owns the
cluster-wide pod and Service discovery, `ScrapeConfig`, `PodMonitor`,
`ServiceMonitor`, and `Probe` components, and the OTLP, Jaeger, syslog, and Loki
receivers. All cluster-wide scrape components opt into Alloy clustering, so a
target is assigned to one healthy peer rather than scraped by every replica.
The existing `*-collectors-alloy` Service identity is preserved for clients.
Pod and Service discovery remain specifically because they supply the
annotation-based Prometheus scrape targets; neither component participates in
pod-log collection.

The central Deployment converts received OTLP metrics for remote-write to
Mimir, received OTLP logs for Loki, and exports traces to Tempo. Those three
existing backends currently use literal private addresses in
[`values.yaml`](values.yaml); the addresses are mutable operational
dependencies, not service discovery.

Central Kubernetes enrichment first associates telemetry by the
`k8s.pod.uid` resource attribute emitted by the container parser or workload,
then falls back to the incoming connection. This prevents forwarded telemetry
from being attributed to an Alloy DaemonSet merely because that pod opened the
gateway connection.

Vector ingestion runs only on `dc1-k3s-node1`, which owns the static syslog
LoadBalancer address. It accepts Cisco and iDRAC syslog over TCP or UDP on port
514 and Talos kernel/service JSON over UDP ports 6050/6051. Vector parses and
normalizes those records into OTLP resources, then sends OTLP/HTTP to the
central Alloy infrastructure receiver on port 4328. That receiver deliberately
bypasses `k8sattributes`: the emitting device remains the resource rather than
being replaced by the Vector pod identity. See Vector's
[`socket` source](https://vector.dev/docs/reference/configuration/sources/socket/),
[`remap` transform](https://vector.dev/docs/reference/configuration/transforms/remap/),
and
[`opentelemetry` sink](https://vector.dev/docs/reference/configuration/sinks/opentelemetry/)
documentation.

The chart also creates External Secrets that synchronize Loki and Mimir client
credentials. Secret values are controller-managed and must not be placed in
Git.

## Kubernetes API traffic finding

The signal DaemonSets create no cluster-wide discovery or Operator watches and
do not use API-proxied log streams. Grafana explicitly warns
that this pattern repeats watches in every pod and can significantly load the
API server; see the
[discovery performance guidance](https://grafana.com/docs/alloy/latest/reference/components/discovery/discovery.kubernetes/#performance-considerations).

The split bounds those watches to the three HA discovery replicas and removes
API log streaming. Some duplicated watch traffic remains intentionally for HA,
including the three `otelcol.processor.k8sattributes` informers. Scrape work is
sharded using the component-level clustering described by the
[ServiceMonitor component](https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.operator.servicemonitors/#clustering).

## Operations

Verify all four Alloy component graphs and health at port `12345`, ensure all
three discovery peers appear in the cluster page, and confirm the DaemonSet
configs have no `discovery.kubernetes`, `prometheus.operator`, direct
`prometheus.remote_write`, or direct `loki.write` component. Confirm the OTLP
DaemonSet Service selects one ready pod on the caller's node, then inspect
`prometheus_remote_storage_*`, Kubernetes client request, dropped sample, and
Loki write metrics on the central Deployment, plus exporter queue and send
failure metrics on every DaemonSet. Correlate API-server requests by Alloy
service-account user agent before attributing traffic to Metrics Server or
Mimir. A rollout can briefly duplicate or miss scrapes while consistent-hash
ownership converges; watch remote-write and target health during
reconciliation. The filelog receiver is public preview and may require config
changes during a future Alloy upgrade.

Render with `helm dependency build Observability/Collectors`, `helm lint`, and
representative ApplicationSet values. Roll back through Git/Argo CD. Removing
the ApplicationSet preserves resources, so deletion requires an explicit
cleanup decision.
