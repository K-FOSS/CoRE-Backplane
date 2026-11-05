# Collector stack guidance

This file adds Collector-specific rules beneath the
[Observability guidance](../AGENTS.md) and
[repository-wide guidance](../../AGENTS.md). Follow all three together. The
fleet owner is
[`Apps/Observability/Collectors.yaml`](../../Apps/Observability/Collectors.yaml);
inspect it first and include its injected Lovely values in every render and
review.

## Role boundaries

Preserve these responsibilities unless the requested change explicitly
redesigns the topology and updates every consumer:

- `alloy-logs` selects and reads workload logs and carries original pod
  identity to the gateway.
- `alloy-metrics` collects only node-local kubelet/cAdvisor and Alloy
  self-metrics.
- `alloy-host` is the sole node-exporter-compatible host pipeline. It is a
  privileged, host-networked DaemonSet with read-only host root, proc, and sys
  mounts so host and NIC collectors can operate.
- `alloy-services` clusters ServiceMonitor, Probe, and ScrapeConfig discovery.
- the main `alloy` clusters PodMonitor discovery, receives internal telemetry,
  owns backend credentials and writers, and performs only source-safe
  enrichment.
- `alloy-otlp` accepts external OTLP traffic and forwards it to the main
  gateway. Internal Alloy signal agents send directly to the main
  `*-collectors-alloy` Service.

Do not add cluster-wide discovery to a node-local DaemonSet, deploy a second
node-exporter scrape path, or enable the same monitor type in more than one
Alloy tier. A placement exclusion for clustered workloads must not remove the
node-local agents from that node.

## Source identity and processing

- Preserve Prometheus labels supplied by each scrape target through OTLP
  conversion and Mimir remote write. The central gateway's Kubernetes metadata
  processor must not associate metrics with the receiving Alloy pod.
- Associate pod logs using the original `k8s.pod.uid` carried by the source.
  Keep infrastructure logs that already identify their device out of pod
  association. Enrich traces only from trustworthy resource identity.
- Add or rename labels only when a documented backend, recording rule, or
  dashboard contract requires it. Avoid parallel spellings, transport-derived
  labels, and transformations that erase a source label before its consumer is
  migrated.
- Keep backend addresses, tenant selection, and credentials in the main Alloy
  tier. Node-local agents should know only the local main-gateway endpoint.
  Never expose backend credentials through agent environment variables or
  rendered ConfigMaps.

## Alloy and Kubernetes resource changes

[`values.yaml`](values.yaml) contains Alloy configuration embedded in YAML,
while [`templates/AlloyInstances.yaml`](templates/AlloyInstances.yaml) renders
multiple Alloy custom resources. Validate both parser boundaries and inspect
the resulting pod controllers. Do not assume that a value accepted by Helm or
the Alloy custom resource is placed in the resulting pod spec.

Environment variables, `valueFrom` entries, mounts, security contexts,
host-network settings, RBAC, services, and clustering settings are scoped to a
specific Alloy instance. Keep them with that instance and verify their exact
rendered location. Changes to `alloy-host` privileges or host mounts require a
focused security review; keep mounts read-only and privileges no broader than
the enabled host collectors require.

## Collector verification

Build dependencies, lint, and render the chart with each materially different
ApplicationSet profile. Inspect every rendered Alloy resource, ConfigMap,
Service, RBAC object, StatefulSet or DaemonSet setting, and endpoint. Then
verify on every affected cluster:

1. expected peers and target ownership, with no duplicate scrape class;
2. one local cAdvisor and one host pipeline per schedulable node;
3. all expected PodMonitor, ServiceMonitor, Probe, and ScrapeConfig targets;
4. OTLP and remote-write queue, retry, failure, and dropped-data counters;
5. source labels in Mimir before and after recording rules; and
6. representative Kubernetes dashboards for multiple namespaces, workloads,
   pods, containers, and nodes, including cross-site cluster selection.

For metadata fixes, compare a raw source metric with the stored series and the
final dashboard query. For performance changes, measure Collector CPU, memory,
API watch volume, scrape volume, and shipped sample rate before and after; do
not trade correctness or dashboard coverage for a lower local resource number.
