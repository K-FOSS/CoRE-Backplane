# Observability stack guidance

This file adds rules for the entire `Observability` subtree. It inherits and
does not weaken the [repository-wide guidance](../AGENTS.md). A component-level
`AGENTS.md` may add narrower requirements, and all applicable files must be
followed together.

## Stack ownership and data flow

- Begin every implementation investigation at the matching fleet owner in
  [`Apps/Observability`](../Apps/Observability/). Identify all selected clusters
  and all injected values before editing a chart, template, Kustomize layer, or
  remote resource.
- Trace a telemetry change end to end: source or exporter, discovery and
  Collector processing, backend ingestion and storage, recording rules,
  Grafana datasource and dashboard queries, and the user-visible result.
  Component readiness at one layer does not prove the complete path works.
- Keep one active owner for each discovery or scrape class. The current split
  is node-local cAdvisor in `alloy-metrics`, host and NIC metrics in
  `alloy-host`, clustered PodMonitor discovery in the main Alloy gateway, and
  clustered ServiceMonitor, Probe, and ScrapeConfig discovery in
  `alloy-services`. Before adding a source, prove that another Alloy component,
  exporter, or operator is not already collecting it.
- Do not fan out identical telemetry to both sites or send one signal through
  multiple equivalent pipelines. Cilium global Services provide routing and
  failover; they do not authorize duplicate writers. Preserve the tenant and
  source identity when changing a route.

## Metric and metadata compatibility

- Preserve canonical Prometheus identities consumed by the installed upstream
  Kubernetes dashboards and rules. This includes `cluster`, `namespace`,
  `pod`, `container`, `node`, `instance`, `nodename`, `job`, and
  `metrics_path`, with `job='kubelet'` and
  `metrics_path='/metrics/cadvisor'` for cAdvisor and
  `job='node-exporter'` for host metrics.
- Treat metadata as source identity, not transport identity. A gateway,
  receiver, or forwarder must not overwrite the originating namespace, pod,
  container, node, workload, cluster, or service with its own pod metadata.
  Metrics should retain scrape labels; pod logs should associate by the source
  pod UID; traces should use their resource identity. Do not use connection
  association when it can identify the forwarding Alloy or Vector pod instead
  of the producer.
- Prometheus is disabled in this stack. A rendered `PrometheusRule` does not
  prove that a rule is evaluated. Rules required by upstream dashboards must
  be loaded into the active Mimir ruler and verified there, including their
  output labels and data for every expected cluster, namespace, pod, and node.
- Changes to collection frequency must account for scrape intervals, rate
  windows, rule evaluation intervals, dashboard lookback windows, and expected
  staleness together. Do not optimize one interval without checking the
  downstream queries it feeds.

## Validation and operations

For a changed signal path, validate all of the following as applicable:

1. The fully rendered resources for each distinct ApplicationSet profile.
2. Discovery targets and scrape ownership, including absence of duplicates.
3. Alloy component health, clustering ownership, queues, dropped data, retries,
   and backend shipping errors.
4. Raw source series or records before aggregation, then the stored backend
   labels and tenant.
5. Active Mimir ruler groups and recording-series output when dashboards depend
   on recording rules.
6. Grafana variables and representative upstream dashboard queries across all
   sites, clusters, namespaces, workloads, and nodes in scope.

Do not validate only with `up`, a single cluster aggregate, one Alloy pod, or
one namespace. Those checks can pass while discovery, label provenance,
cross-site visibility, or workload filtering is broken. Use metadata and
counts for production logs and traces; never print telemetry bodies that may
contain sensitive application data.

Update the nearest component README whenever a change alters topology, signal
ownership, scrape frequency, metadata mapping, failover, tenant routing,
dashboard compatibility, or the operational verification procedure.
