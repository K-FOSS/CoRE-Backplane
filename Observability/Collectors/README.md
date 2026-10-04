# CoRE-Backplane Observability/Collectors Stack

This chart deploys four [Grafana Alloy](https://grafana.com/docs/alloy/latest/)
roles and
optional [Vector](https://vector.dev/docs/setup/installation/package-managers/helm/)
collectors. The
[`core-observability-collectors` ApplicationSet](../../Apps/Observability/Collectors.yaml)
targets `core-dc1-talos-prod`, `core-home1-talos-prod`, and `dc1-k3s-node1`,
injecting the cluster and datacentre labels.
See the [Observability overview](../README.md).

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

`alloy` is a three-replica StatefulSet with a PodDisruptionBudget. It owns
only cluster-wide metrics discovery, backend writers, OTLP gateway processing,
the Vector-specific infrastructure OTLP receiver, and compatibility Jaeger
receivers. All cluster-wide scrape components opt into Alloy clustering, so a
target is assigned to one healthy peer rather than scraped by every replica.
The StatefulSet gives peers stable identities and follows Grafana's
[Kubernetes clustering guidance](https://grafana.com/docs/alloy/latest/configure/clustering/).
The existing `*-collectors-alloy` Service identity is preserved for clients.
Pod and Service discovery remain specifically because they supply the
annotation-based Prometheus scrape targets; neither component participates in
pod-log collection.

The central StatefulSet converts received OTLP metrics for remote-write to
Mimir, received OTLP logs for Loki, and exports traces to Tempo. Pod logs
therefore follow `alloy-logs` -> the cluster-local central Alloy StatefulSet ->
the Cilium global backend Services; they do not write directly from a node
agent to Loki. Infrastructure clusters send logs through the namespace-local
`loki-core` DNS name. Metrics use the matching namespace-local `core-mimir`
DNS name, so Cilium selects the site-local Mimir endpoints while preserving
the same path for cross-site collectors. The
[Logs stack](../Logs/README.md#global-service-ownership) uses
[Cilium Global Services](https://docs.cilium.io/en/stable/network/clustermesh/global-services/)
to serve DC1 Loki backends in both DC1 and Home1. The legacy collector retains
DC1's mutable Service IP because it has no local global Service. Mimir and
Tempo are otherwise private endpoints; Mimir uses the Cilium global Service
while Tempo retains its existing direct endpoint.

The same Service exposes a cluster-internal Prometheus remote-write receiver on
port `9090`. Its
[`prometheus.receive_http`](https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.receive_http/)
endpoint is `/api/v1/metrics/write` and forwards into the existing Mimir writer,
so pushed samples receive the same ApplicationSet-injected `cluster` and `dc`
external labels as scraped metrics. OpenNMS Insight is the first consumer. The
receiver is not an HTTPRoute or LoadBalancer and performs no authentication;
only trusted in-cluster producers may use it. Reads do not pass through Alloy
because it is a write gateway, not a Prometheus remote-read service.

Backend shipping is configured under `alloy.destinations`: `lokiUrl` is the
Loki push URL, `mimirUrl` is the Prometheus remote-write URL, and
`tempoEndpoint` is the Tempo OTLP/gRPC `host:port`. The ApplicationSet
explicitly injects all three endpoints into every target
cluster. Only the central Alloy uses these values; `alloy-logs`,
`alloy-metrics`, and `alloy-otlp` continue to export exclusively through OTLP.

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

The Vector chart runs a stateless Deployment without Kubernetes RBAC or a
mounted service-account token. Its internal API supplies gRPC startup,
readiness, and liveness checks on pod port `8686`; neither the chart Service nor
the syslog LoadBalancer exposes that port. Site-specific PureLB annotations and
listener mappings are configured under `vector.syslogService`.

Vector 0.57 disables configuration-file environment interpolation by default.
This deployment explicitly opts back in because the ApplicationSet injects the
non-secret `VECTOR_OTLP_LOGS_ENDPOINT` into the sink URI. Do not use that opt-in
for credentials or other untrusted values; see the upstream
[Vector 0.57 upgrade guide](https://vector.dev/highlights/2026-07-14-0-57-0-upgrade-guide/).

The main StatefulSet no longer opens syslog port 1514 or the legacy Vector Loki
API port 9999. Vector owns device/Talos ingestion and uses OTLP exclusively.
Gateway self-metrics are collected through the chart ServiceMonitor rather
than a second in-config self-scrape.

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
sharded for `ScrapeConfig`, `PodMonitor`, `ServiceMonitor`, `Probe`, and
annotation-discovered targets using the component-level clustering described by the
[ServiceMonitor component](https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.operator.servicemonitors/#clustering).
The node-local `alloy-metrics` scrape deliberately remains unclustered: each
DaemonSet pod exposes a different node and must scrape its own local exporters.

## Operations

Verify all four Alloy component graphs and health at port `12345`, ensure all
three discovery peers appear in the cluster page, and confirm the DaemonSet
configs have no `discovery.kubernetes`, `prometheus.operator`, direct
`prometheus.remote_write`, or direct `loki.write` component. Confirm the OTLP
DaemonSet Service selects one ready pod on the caller's node, then inspect
`prometheus_remote_storage_*`, Kubernetes client request, dropped sample, and
Loki write metrics on the central StatefulSet, plus exporter queue and send
failure metrics on every DaemonSet. Correlate API-server requests by Alloy
service-account user agent before attributing traffic to Metrics Server or
Mimir. Also inspect `prometheus_receive_http_*` and
`prometheus_forwarded_samples_total` for internal remote-write producers, then
query their expected external labels in Mimir. A rollout can briefly duplicate
or miss scrapes while consistent-hash ownership converges; watch remote-write
and target health during
reconciliation. The filelog receiver is public preview and may require config
changes during a future Alloy upgrade.

Changing the central controller from the former Deployment to the StatefulSet
replaces its workload identity. During the first reconciliation, watch peer
membership and remote-write health while Argo CD creates the StatefulSet and
prunes the Deployment; do not force a separate fleet-wide resync.

Render with `helm dependency build Observability/Collectors`, `helm lint`, and
representative ApplicationSet values. Roll back through Git/Argo CD. Removing
the ApplicationSet preserves resources, so deletion requires an explicit
cleanup decision.

### Talos pod-log collection and recovery

The [collector ApplicationSet](../../Apps/Observability/Collectors.yaml) enables
`alloy-logs.alloy.mounts.varlog` on YXL and YVR through `podLogsEnabled`. This
both restores the pinned Alloy chart's read-only host `/var/log` mount and
enables the filelog receiver in [values.yaml](values.yaml). The legacy K3s
profile keeps its existing disabled setting. The mount is supplied by the
[Alloy chart README](https://github.com/grafana/alloy/blob/v1.17.0/operations/helm/charts/alloy/README.md)
and [chart source](https://github.com/grafana/alloy/tree/v1.17.0/operations/helm/charts/alloy),
without privileged mode, Kubernetes log-stream watches or API credentials.
The Talos clusters use the standard `/var/log/pods` layout described in
[Kubernetes logging architecture](https://kubernetes.io/docs/concepts/cluster-administration/logging/).

The receiver uses the OpenTelemetry
[container parser](https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/pkg/stanza/operator/parser/container/README.md)
to parse CRI timestamps, stream and partial records and derive Kubernetes
resource metadata from the file path. It sends records to the existing batch
processor and OTLP gateway. Cluster and datacentre are resource attributes;
[`otelcol.exporter.loki` label hints](https://grafana.com/docs/alloy/latest/reference/components/otelcol/otelcol.exporter.loki/)
promote them and Kubernetes namespace, pod and container metadata to Loki
labels `cluster`, `dc`, `k8s_namespace_name`, `k8s_pod_name` and
`k8s_container_name`.

This restores the file-reading path removed by commit `377e66e32` on
2026-08-24. The Talos profiles set `startAt: 'beginning'`, so the first
reconciled receiver reads the existing contents of discovered files instead of
only following new writes from a chatty canary. Subsequent positions are kept
by `otelcol.storage.file`; the chart's default storage path is pod-local, so a
replacement Pod can reread files from the configured starting position.
Exporter queues are not a durable outage buffer, and the initial replay should
be monitored for Loki ingestion pressure.

Reconcile only the collector ApplicationSet, then the `alloy-logs` ConfigMap
and DaemonSet on each Talos cluster. These resources have no sync hooks. Verify
the host mount is read-only, receiver accepted-record and exporter sent-record
counters increase, and Loki returns recent streams from both source clusters.
Use a count query or stream metadata to verify without printing production log
bodies. Disabling `podLogsEnabled` through Git removes the receiver and host
mount; it stops new pod-log collection but does not delete stored Loki data.
