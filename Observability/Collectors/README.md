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

- `alloy-logs` discovers only pods labeled `logs=loki-myloginspace`, reads
  their streams through
  [`loki.source.kubernetes`](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.kubernetes/),
  and sends them to the central Alloy Loki push endpoint.
- `alloy-metrics` uses
  [`prometheus.exporter.unix`](https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.exporter.unix/)
  against read-only host root, proc, and sys mounts and also scrapes its own
  Alloy metrics.
- `alloy-otlp` accepts node-local OTLP/gRPC and OTLP/HTTP through a ClusterIP
  Service with `internalTrafficPolicy: Local`.

The metrics and OTLP DaemonSets batch their signals and use
[`otelcol.exporter.otlp`](https://grafana.com/docs/alloy/latest/reference/components/otelcol/otelcol.exporter.otlp/)
over plaintext OTLP/gRPC to the existing `*-collectors-alloy` Service. The root
ApplicationSet injects the exact central service FQDN, cluster, and datacentre
values. The log DaemonSet receives the central Alloy service endpoint and
tenant Org ID from the same ApplicationSet; selected log streams never write
directly to Loki.

`alloy` is a three-replica StatefulSet with a PodDisruptionBudget. It owns
only cluster-wide metrics discovery, backend writers, OTLP gateway processing,
the Vector-specific infrastructure OTLP receiver, the internal Loki push API,
and compatibility Jaeger receivers. All cluster-wide scrape components opt
into Alloy clustering, so a target is assigned to one healthy peer rather
than scraped by every replica.
The StatefulSet gives peers stable identities and follows Grafana's
[Kubernetes clustering guidance](https://grafana.com/docs/alloy/latest/configure/clustering/).
The existing `*-collectors-alloy` Service identity is preserved for clients.
Pod and Service discovery remain specifically because they supply the
annotation-based Prometheus scrape targets; neither component participates in
pod-log collection.

The central StatefulSet receives OTLP telemetry and a Loki push API stream from
`alloy-logs`. It sends received OTLP metrics by remote-write to Mimir, received
logs to Loki, and traces to Tempo. The pod log path is
`alloy-logs` -> central Alloy -> namespace-local `loki-core`; Cilium's Global
Service routes the final write to the Loki backends. Metrics use the matching namespace-local `core-mimir`
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

The Alloy Service also exposes the cluster-internal Loki push API on port
`3100`, implemented by
[`loki.source.api`](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.api/).
The log DaemonSet pushes into this receiver; only the central Alloy StatefulSet
connects to the Loki backend.

Backend shipping is configured under `alloy.destinations`: `lokiUrl` is the
Loki push URL, `mimirUrl` is the Prometheus remote-write URL, and
`tempoEndpoint` is the Tempo OTLP/gRPC `host:port`. The ApplicationSet injects
these endpoints and a tenant Org ID derived from the cluster tenant label
(`core.mylogin.space` becomes `core`). The central Loki and Mimir writers send
it as `X-Scope-OrgID`. `alloy-logs` sends to the central Alloy Loki push API on
port `3100`, exposed only through the cluster-internal Service.
The central receiver uses Alloy's
[`loki.source.api`](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.api/)
component, which accepts the Loki push API and forwards records to the central
writer. It is unauthenticated and intended for trusted in-cluster senders; it
is not exposed through an HTTPRoute or LoadBalancer.

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

The metrics and OTLP DaemonSets create no cluster-wide discovery or Operator
watches. Each enabled `alloy-logs` DaemonSet watches pod metadata and opens log
streams only for pods matching `logs=loki-myloginspace`. Its chart-managed
ClusterRole is narrowed to read `pods`, `pods/log`, and `namespaces`; it does
not grant access to Secrets. This creates one filtered discovery watch per
node, so keep the selector limited to workloads intended for Loki. Grafana
documents the API-server cost of discovery watches in its
[discovery performance guidance](https://grafana.com/docs/alloy/latest/reference/components/discovery/discovery.kubernetes/#performance-considerations).

The central tier still has duplicated watch traffic for HA, including the
three `otelcol.processor.k8sattributes` informers. Scrape work is
sharded for `ScrapeConfig`, `PodMonitor`, `ServiceMonitor`, `Probe`, and
annotation-discovered targets using the component-level clustering described by the
[ServiceMonitor component](https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.operator.servicemonitors/#clustering).
The node-local `alloy-metrics` scrape deliberately remains unclustered: each
DaemonSet pod exposes a different node and must scrape its own local exporters.

## Operations

Verify all four Alloy component graphs and health at port `12345`, ensure all
three central discovery peers appear in the cluster page, and confirm the
`alloy-logs` config has exactly one pod discovery selector for
`logs=loki-myloginspace`. Confirm its ServiceAccount can read pods and pod logs
but not Secrets. Confirm the OTLP DaemonSet Service selects one ready pod on
the caller's node and the central Alloy Loki API is reachable through only its
cluster-internal Service, then inspect
`prometheus_remote_storage_*`, Kubernetes client request, dropped sample, and
Loki write metrics on the central StatefulSet, plus exporter queue and send
failure metrics on every DaemonSet. Correlate API-server requests by Alloy
service-account user agent before attributing traffic to Metrics Server or
Mimir. Also inspect `prometheus_receive_http_*` and
`prometheus_forwarded_samples_total` for internal remote-write producers, then
query their expected external labels in Mimir. A rollout can briefly duplicate
or miss scrapes while consistent-hash ownership converges; watch remote-write
and target health during
reconciliation. Check Loki for streams carrying the expected `cluster` and `dc`
labels and verify writes land in the configured Org ID; use stream metadata or
counts rather than printing production log bodies.

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
`podLogsEnabled` on YXL and YVR. The log DaemonSet selects pods by the
`logs=loki-myloginspace` Kubernetes label and streams only those pod logs
through the Kubernetes API to the central Alloy service. The legacy K3s profile
keeps this source disabled. The chart grants the log DaemonSet only the read permissions needed
for pod discovery and `pods/log`; it mounts no host log directory. The
Kubernetes log API behavior is described in the
[Kubernetes logging architecture](https://kubernetes.io/docs/concepts/cluster-administration/logging/).

Reconcile only the collector ApplicationSet, then the `alloy-logs` ConfigMap,
Role/ClusterRole, ServiceAccount and DaemonSet on each Talos cluster. These
resources have no sync hooks. Verify only labeled pods appear as targets, log
stream and Loki write counters increase, and Loki returns recent streams from
both source clusters. Disabling `podLogsEnabled` through Git removes discovery,
the log source and its RBAC; it stops new pod-log collection but does not delete
stored Loki data. Kubernetes API streaming begins at the current stream
position; it does not backfill historical file contents.
