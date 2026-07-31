# Telemetry collectors

This chart deploys two [Grafana Alloy](https://grafana.com/docs/alloy/latest/)
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

`alloy-agent` is a DaemonSet. Each pod reads CRI logs directly from its node's
`/var/log/pods`, derives namespace/pod/container labels from the path, scrapes
only its own Alloy metrics, and ships directly to Loki and Mimir. It has no
Kubernetes discovery or Operator components and does not use the Kubernetes API
to proxy log streams.

`alloy` is a three-replica Deployment with a PodDisruptionBudget. It owns the
cluster-wide pod and Service discovery, `ScrapeConfig`, `PodMonitor`,
`ServiceMonitor`, and `Probe` components, and the OTLP, Jaeger, syslog, and Loki
receivers. All cluster-wide scrape components opt into Alloy clustering, so a
target is assigned to one healthy peer rather than scraped by every replica.
The existing `*-collectors-alloy` Service identity is preserved for clients.

Metrics are remote-written to Mimir; logs and traces currently use literal
private addresses in [`values.yaml`](values.yaml). Those addresses are mutable
operational dependencies, not service discovery.

The chart also creates External Secrets that synchronize Loki and Mimir client
credentials. Secret values are controller-managed and must not be placed in
Git.

## Kubernetes API traffic finding

Previously, every Alloy DaemonSet pod created cluster-wide discovery and
Operator watches and used API-proxied log streams. Grafana explicitly warns
that this pattern repeats watches in every pod and can significantly load the
API server; see the
[discovery performance guidance](https://grafana.com/docs/alloy/latest/reference/components/discovery/discovery.kubernetes/#performance-considerations).

The split bounds those watches to the three HA discovery replicas and removes
API log streaming. Some duplicated watch traffic remains intentionally for HA,
including the three `otelcol.processor.k8sattributes` informers. Scrape work is
sharded using the component-level clustering described by the
[ServiceMonitor component](https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.operator.servicemonitors/#clustering).

## Operations

Verify both Alloy component graphs and health at port `12345`, ensure all three
discovery peers appear in the cluster page, and confirm the DaemonSet config has
no `discovery.kubernetes`, `prometheus.operator`, or
`otelcol.processor.k8sattributes` component. Then inspect
`prometheus_remote_storage_*`, Kubernetes client request, dropped sample, and
Loki write metrics. Correlate API-server requests by Alloy service-account user
agent before attributing traffic to Metrics Server or Mimir. A rollout can
briefly duplicate or miss scrapes while consistent-hash ownership converges;
watch remote-write and target health during reconciliation.

Render with `helm dependency build Observability/Collectors`, `helm lint`, and
representative ApplicationSet values. Roll back through Git/Argo CD. Removing
the ApplicationSet preserves resources, so deletion requires an explicit
cleanup decision.
