# CoRE-Backplane Observability/Collectors Stack

This chart defines specialized [Grafana Alloy](https://grafana.com/docs/alloy/latest/)
roles reconciled by the
[Grafana Alloy Operator](https://github.com/grafana/alloy-operator), and
optional [Vector](https://vector.dev/docs/setup/installation/package-managers/helm/)
collectors. The
[`core-observability-collectors` ApplicationSet](../../Apps/Observability/Collectors.yaml)
targets `core-dc1-talos-prod`, `core-home1-talos-prod`, and `dc1-k3s-node1`,
injecting the cluster, region, and datacentre labels.
See the [Observability overview](../README.md).

The chart also installs the
[`alloy-mixin`](https://github.com/portefaix/helm-charts/tree/master/charts/alloy-mixin)
and [Prometheus Operator CRDs](https://github.com/prometheus-community/helm-charts/tree/main/charts/prometheus-operator-crds).
All dependency versions are pinned in `Chart.yaml`; generated dependency
archives remain ignored and must not be force-added.

All Alloy custom resources pin the `grafana/alloy` image to `v1.22.0` through
the Operator's Helm-compatible `spec.image.tag` field. The
[Alloy 1.22.0 release notes](https://github.com/grafana/alloy/releases/tag/v1.22.0)
list breaking changes for `loki.enrich`, `prometheus.enrich`, and
`otelcol.connector`; this stack does not configure those components.

## Current topology

Four node-local DaemonSets run on every node:

- `alloy-logs` discovers pods labeled `logs=loki-myloginspace` on its own node, reads
  their streams through
  [`loki.source.kubernetes`](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.kubernetes/),
  retains pod UID/namespace/name/container identity with
  [`discovery.relabel`](https://grafana.com/docs/alloy/latest/reference/components/discovery/discovery.relabel/),
  adds cluster and datacentre labels with
  [`loki.process`](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.process/),
  converts them to OTLP, and sends them to the node-local-preferred Alloy
  OTLP/gRPC receiver.
- `alloy-metrics` scrapes only that node's kubelet/cAdvisor endpoint and Alloy
  self-metrics, forwarding them through its node-local pipeline. cAdvisor is
  scraped every 60 seconds to match the five-minute resource recording windows
  without retaining the former 30-second cAdvisor volume.
- `alloy-host` is the sole node-exporter pipeline: a separate host-networked,
  privileged Alloy DaemonSet using the former node-exporter collector set plus
  `ethtool` NIC metrics and the `entropy`, `interrupts`, `powersupplyclass`,
  `processes`, `pressure`, `schedstat`, and `vmstat` collectors. The
  [interrupts collector](https://github.com/prometheus/node_exporter/blob/master/collector/interrupts_linux.go)
  exposes `node_interrupts_total` from `/proc/interrupts`, with series per CPU
  and interrupt identity. The [processes collector](https://github.com/prometheus/node_exporter/blob/master/collector/processes_linux.go)
  exposes `node_processes_threads` by scanning host process and thread state
  on each 30-second scrape. The [pressure collector](https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.exporter.unix/#collectors-list)
  exposes `node_pressure_cpu_waiting_seconds_total` when the host provides
  `/proc/pressure/cpu`. The [entropy collector](https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.exporter.unix/#collectors-list)
  exposes `node_entropy_available_bits` on Linux hosts.
  The [schedstat collector](https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.exporter.unix/#collectors-list)
  exposes `node_schedstat_timeslices_total` from `/proc/schedstat`.
  The [vmstat collector](https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.exporter.unix/#collectors-list)
  exposes `node_vmstat_oom_kill` from `/proc/vmstat` when the host reports it.
  It mounts the host root, proc, and sys filesystems, listens on a separate local port, and forwards
  metrics through the existing OTLP receiver. The [Alloy collector](https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.exporter.unix/#collectors-list)
  reads `/sys/class/power_supply`; `node_power_supply_online` appears only on
  hosts exposing a power supply with an `online` attribute. The five YVR hosts
  had no entries in that sysfs directory when this change was prepared.
- `alloy-otlp` accepts node-local OTLP/gRPC and OTLP/HTTP through a ClusterIP
  Service with `trafficDistribution: PreferClose`; it prefers the local
  node's receiver and fails over to another receiver when the local one is
  unavailable. It also accepts Zipkin spans on TCP/9411 through Alloy's
  [`otelcol.receiver.zipkin`](https://grafana.com/docs/alloy/latest/reference/components/otelcol/otelcol.receiver.zipkin/)
  and forwards them through the same OTLP gateway pipeline. CoreDNS uses this
  receiver only on YVR, sampled at one query in 100; the listener stays
  available on the other collector targets.

The logs, metrics, and host DaemonSets batch their signals and send them
directly to the main Alloy gateway. The OTLP DaemonSet batches incoming
external signals and also sends them to the main gateway. They use
[`otelcol.exporter.otlp`](https://grafana.com/docs/alloy/latest/reference/components/otelcol/otelcol.exporter.otlp/)
over plaintext OTLP/gRPC to the `*-collectors-alloy` Service. The root
ApplicationSet injects the exact service FQDN, cluster, and datacentre values.
The log DaemonSet sends no Loki requests and
needs no Loki URL or tenant ID; central Alloy alone owns backend tenant
selection and writes.

The `alloy-otlp` Service remains available for external OTLP clients and
forwards received signals to the three-replica central `*-collectors-alloy`
Service. Internal signal DaemonSets no longer traverse that receiver.

Mimir and Grafana also send traces to this same OTLP receiver. The receiver
forwards them to the central Alloy processing gateway, which enriches and
ships traces to Tempo. See Grafana's
[OTLP receiver](https://grafana.com/docs/alloy/latest/reference/components/otelcol/otelcol.receiver.otlp/)
and [Kubernetes service traffic distribution](https://kubernetes.io/docs/reference/networking/virtual-ips/#traffic-distribution)
documentation.

The central `Alloy` custom resource reconciles to a three-replica StatefulSet
with a PodDisruptionBudget. It owns
only cluster-wide metrics discovery, backend writers, OTLP gateway processing,
the Vector-specific infrastructure OTLP receiver, and compatibility Jaeger
receivers. All cluster-wide scrape components opt
into Alloy clustering, so a target is assigned to one healthy peer rather
than scraped by every replica.
The StatefulSet gives peers stable identities and follows Grafana's
[Kubernetes clustering guidance](https://grafana.com/docs/alloy/latest/configure/clustering/).
For Home1, the ApplicationSet injects required node affinity excluding `hpc3`
from this central StatefulSet and the clustered `alloy-services` workload. Their
replicas can run on the other Ready nodes; the node-local Alloy DaemonSets
continue collecting on `hpc3`.
The existing `*-collectors-alloy` Service identity is preserved for clients.
Pod and Service discovery remain specifically because they supply the
annotation-based Prometheus scrape targets; neither component participates in
pod-log collection.

The dedicated two-replica `alloy-rules` StatefulSet runs only on the YXL and
YVR Talos clusters, where `core-mimir` is available. Its
[`mimir.rules.kubernetes`](https://grafana.com/docs/alloy/latest/reference/components/mimir/mimir.rules.kubernetes/)
components watch `PrometheusRule` resources and synchronize them through the
Mimir configuration API every five minutes. Alloy clustering ensures only one
replica writes rules. Each rule query and result receives the source
`cluster`; cluster-specific Mimir namespace prefixes prevent the two sites from
owning or deleting one another's rule namespaces. Rules opt into a namespace
query matcher with the
`observability.core-backplane/query-namespace` metadata label. The Kubernetes
namespace containing a rule is not used automatically because cluster-wide
kube-prometheus rules are stored in `core-prod` while querying metrics for all
workload namespaces. The legacy K3s target does not deploy `alloy-rules`
because it has no `core-mimir` Service.

Kubelet/cAdvisor metrics are scraped locally by the privileged, host-networked
`alloy-host` DaemonSet through each node's secure kubelet endpoint. The target
is built from the pod's `status.hostIP`, so it does not use Kubernetes API node
discovery or the API-server proxy; failed scrapes retry on the next interval.
The kubelet still validates the service-account bearer token, so its configured
authentication/authorization webhook must remain available for authenticated
scrapes. PodMonitor targets are scraped by the clustered central Alloy
StatefulSet.
The exporter chart's kubelet ServiceMonitor is disabled because its
headless-Service path was only producing one kubelet endpoint per cluster. See Grafana's
[Prometheus scrape](https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.scrape/)
documentation covers the scrape and TLS/token configuration. The
Collectors release owns the Prometheus Operator CRDs used by Alloy; the
Exporters release leaves those CRDs disabled.

The central StatefulSet receives OTLP telemetry from all signal DaemonSets.
For pod logs, `loki.source.kubernetes` sends selected entries through
[`otelcol.receiver.loki`](https://grafana.com/docs/alloy/latest/reference/components/otelcol/otelcol.receiver.loki/)
and `otelcol.exporter.otlp` to the main Alloy OTLP/gRPC receiver. The Loki
receiver preserves the original log line as the OTLP body; the central
[`otelcol.processor.transform`](https://grafana.com/docs/alloy/latest/reference/components/otelcol/otelcol.processor.transform/)
promotes the carried pod UID, namespace, pod, container, cluster, and datacentre
values into resource attributes. The
[`otelcol.processor.k8sattributes`](https://grafana.com/docs/alloy/latest/reference/components/otelcol/otelcol.processor.k8sattributes/)
then matches
the original pod UID and inserts current Kubernetes metadata without replacing
source resource values. After batching, one
[`otelcol.exporter.otlphttp`](https://grafana.com/docs/alloy/latest/reference/components/otelcol/otelcol.exporter.otlphttp/)
path sends logs to Loki's native `/otlp/v1/logs` endpoint. The former
`otelcol.exporter.loki` encoded the whole LogRecord into a JSON body and added
`exporter="OTLP"`; neither the pod-log bridge nor central enrichment created
that wrapper. Prometheus metrics bypass
connection-based Kubernetes enrichment and retain the labels supplied by the
actual scrape target before remote-writing to Mimir. Traces and logs retain
resource- or UID-based enrichment only, without a connection fallback that
could identify them as Alloy telemetry. The pod log path is
`alloy-logs` -> central Alloy OTLP gateway/enrichment -> namespace-local
`loki-core`; Cilium's Global
Service routes the final write to the Loki backends. Metrics use the matching namespace-local `core-mimir`
DNS name, so Cilium selects the site-local Mimir endpoints while preserving
the same path for cross-site collectors. Tempo uses the matching namespace-local
`tempo-core` Cilium Global Service for the same site-selection behavior. The
[Logs stack](../Logs/README.md#global-service-ownership) uses
[Cilium Global Services](https://docs.cilium.io/en/stable/network/clustermesh/global-services/)
to serve DC1 Loki backends in both DC1 and Home1. The legacy collector retains
DC1's mutable Service IP because it has no local global Service. Mimir and
Tempo are otherwise private endpoints; both use Cilium global Services for
cross-site endpoint selection.

The Service exposes a cluster-internal Prometheus remote-write receiver on
port `9090`. Its
[`prometheus.receive_http`](https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.receive_http/)
endpoint is `/api/v1/metrics/write` and forwards into the existing Mimir writer,
so pushed samples receive the same ApplicationSet-injected `cluster`, `region`,
and `dc` external labels as scraped metrics. OpenNMS Insight is the first consumer. The
receiver is not an HTTPRoute or LoadBalancer and performs no authentication;
only trusted in-cluster producers may use it. Reads do not pass through Alloy
because it is a write gateway, not a Prometheus remote-read service.

Backend shipping is configured under `alloy.destinations`:
`lokiOtlpEndpoint` is the Loki OTLP base endpoint ending in `/otlp`,
`mimirUrl` is the Prometheus remote-write URL, and
`tempoEndpoint` is the Tempo OTLP/gRPC `host:port`. The ApplicationSet injects
these endpoints and a tenant Org ID derived from the cluster tenant label
(`core.mylogin.space` becomes `core`). The central Loki and Mimir writers send
it in `X-Scope-OrgID`. The central Alloy Service
accepts OTLP/gRPC from trusted in-cluster agents and no longer exposes a Loki
push API. Loki backend URLs and tenant selection remain only in central Alloy.

The collector data plane is site-local by default. Node-local Alloy agents send
to the local processing/OTLP tier, and that tier sends to the local Mimir, Loki,
and Tempo client Services. Those client Services may be Cilium Global Services
so an outage can move the active write path to the other site; they are a
routing and failover mechanism, not a request to duplicate telemetry at both
backend rings. The intended steady state has one active backend write site for
a tenant, with Garage's shared federated buckets providing the cross-site
durable copy. Alloy must not fan out the same logs, metrics, or traces to both
YXL and YVR merely because both endpoints are reachable.

During a site transition, drain or fence the old processing and backend
writers before enabling the remote path, preserve the same tenant and resource
labels, and verify that the new site reads the existing Garage buckets. HA
scrape deduplication remains a Mimir concern for replicas within the active
collection path; it is not a substitute for writer fencing between independent
site-local backend rings.

Central Kubernetes enrichment associates pod logs by the original source pod's
`k8s.pod.uid` resource attribute. The gateway does not use connection-based
association, which could attribute forwarded logs to an Alloy DaemonSet. A
source-safe transform fills `service.name` only when absent, using deployment,
statefulset, daemonset, job, cronjob, pod, then container identity in that
order. For Cilium DaemonSet logs only, it reads the JSON `level` field into
OTLP severity when severity is not already set; parsing errors leave the
original body untouched and do not discard the record. Loki receives cluster,
datacentre, Kubernetes, workload, service, and log attributes as OTLP fields;
Loki's native per-tenant mapping decides which resource attributes become
index labels and which remain structured metadata.

Vector is enabled on `core-dc1-talos-prod` (YXL) and
`core-home1-talos-prod` (YVR), and disabled on `dc1-k3s-node1`. The K3s
Application no longer runs the Vector syslog receiver. The
`vector.syslog.service.enabled` setting is currently false on all three
profiles, so no syslog LoadBalancer Service is created; Vector on YXL/YVR has
no external syslog listener until a site-specific Service is configured.
When Vector receives device or Talos logs, it parses and normalizes them into
OTLP resources, then sends OTLP/HTTP to the central Alloy infrastructure
receiver on port 4328. That receiver deliberately bypasses `k8sattributes`:
the emitting device remains the resource rather than being replaced by the
Vector pod identity. See Vector's
[`socket` source](https://vector.dev/docs/reference/configuration/sources/socket/),
[`remap` transform](https://vector.dev/docs/reference/configuration/transforms/remap/),
and
[`opentelemetry` sink](https://vector.dev/docs/reference/configuration/sinks/opentelemetry/)
documentation.

The Vector chart runs a stateless Deployment without Kubernetes RBAC or a
mounted service-account token. Its internal API supplies gRPC startup,
readiness, and liveness checks on pod port `8686`; neither the chart Service nor
any Service exposes that port. Site-specific PureLB annotations and listener
mappings are configured under `vector.syslogService` when a syslog Service is
enabled.

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
streams only for pods matching `logs=loki-myloginspace` on its own node via
`spec.nodeName`. This prevents every DaemonSet replica from reading the same
pod log stream. Its chart-managed
ClusterRole is narrowed to read `pods`, `pods/log`, and `namespaces`; it does
not grant access to Secrets. This creates one filtered discovery watch per
node, so keep the selector limited to workloads intended for Loki. Grafana
documents the API-server cost of discovery watches in its
[discovery performance guidance](https://grafana.com/docs/alloy/latest/reference/components/discovery/discovery.kubernetes/#performance-considerations).

The central tier still has duplicated watch traffic for HA, including the
three `otelcol.processor.k8sattributes` informers. PodMonitor scrape work is
sharded across the central peers using the component-level clustering
described by Grafana's
[PodMonitor component](https://grafana.com/docs/grafana-cloud/send-data/alloy/reference/components/prometheus/prometheus.operator.podmonitors/#clustering).
The node-local `alloy-metrics` scrape remains unclustered: its Unix exporter
and authenticated kubelet/cAdvisor scrape are limited to the local node. Its
metrics OTLP pipeline uses bounded 8,192-point batches with a five-second
flush timeout to reduce request overhead while preserving the node and cAdvisor
series required by the resource rules.

## Operations

Verify every Alloy component graph and health at port `12345`, ensure all
three central discovery peers appear in the cluster page, and confirm the
`alloy-logs` config has exactly one pod discovery selector for
`logs=loki-myloginspace`, a Loki-to-OTLP bridge, and one OTLP exporter targeting
the main Alloy service. The central batch processor has one log output to the
native OTLP/HTTP exporter. Confirm the ServiceAccount can read pods and pod logs
but not Secrets. Confirm the OTLP DaemonSet Service selects one ready pod on
the caller's node and the central Alloy OTLP/gRPC service is reachable through
only its cluster-internal Service, then inspect
`prometheus_remote_storage_*`, Kubernetes client request, and dropped sample
metrics on the central StatefulSet, plus `otelcol_exporter_queue_*`,
`otelcol_exporter_sent_log_records`, and `otelcol_exporter_send_failed_log_records`
for the central Loki OTLP/HTTP exporter. Correlate API-server requests by Alloy
service-account user agent before attributing traffic to Metrics Server or
Mimir. Also inspect `prometheus_receive_http_*` and
`prometheus_forwarded_samples_total` for internal remote-write producers, then
query their expected external labels in Mimir. A rollout can briefly duplicate
or miss scrapes while consistent-hash ownership converges; watch remote-write
and target health during
reconciliation. Check Loki for streams carrying the expected `cluster` and `dc`
labels and verify writes land in the configured Org ID; use stream metadata or
counts rather than printing production log bodies. Check that one new native
stream exists per source event and no corresponding `exporter="OTLP"` stream
is being written by the active central exporter.

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
`logs=loki-myloginspace` Kubernetes label and the local node name, then streams those pod logs
through the Kubernetes API, converts the entries to OTLP, and sends them to the
central Alloy OTLP/gRPC service for Kubernetes metadata enrichment and Loki
export. The legacy K3s profile keeps this source disabled. The chart grants the log DaemonSet only the read permissions needed
for pod discovery and `pods/log`; it mounts no host log directory. The
Kubernetes log API behavior is described in the
[Kubernetes logging architecture](https://kubernetes.io/docs/concepts/cluster-administration/logging/).

Reconcile only the collector ApplicationSet, then the `alloy-logs` ConfigMap,
Role/ClusterRole, ServiceAccount and DaemonSet on each Talos cluster. These
resources have no sync hooks. Verify only labeled pods appear as targets, the
central transform receives their original `k8s.pod.uid`, log stream and Loki
write counters increase, and Loki returns recent streams from
both source clusters. Disabling `podLogsEnabled` through Git removes discovery,
the log source and its RBAC; it stops new pod-log collection but does not delete
stored Loki data. Kubernetes API streaming begins at the current stream
position; it does not backfill historical file contents.
