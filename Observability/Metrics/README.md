# Mimir metrics store

This chart deploys [Grafana Mimir](https://grafana.com/docs/mimir/latest/) in
horizontally scaled monolithic mode using the
[`bjw-s common library`](https://github.com/bjw-s-labs/helm-charts/tree/main/charts/library/common).
The pinned
[`mimir-distributed` chart](https://github.com/grafana/helm-charts/tree/main/charts/mimir-distributed)
is retained as an optional dependency but is disabled for every currently
selected cluster.

The [`core-observability-metrics` ApplicationSet](../../Apps/Observability/Metrics.yaml)
targets `core-dc1-talos-prod` (YXL) and `core-home1-talos-prod` (YVR), injects
site identity, and enables the monolithic implementation. Three Mimir replicas
receive Prometheus remote write, keep WAL/head working data in memory-backed
`emptyDir`, and ship blocks to site-local S3. The chart also creates the S3
`User`, Authentik workspace and Secret synchronization, HTTPRoute, and Envoy
SecurityPolicy.

YXL is intentionally constrained to 100,000 samples/s, a 200,000-sample burst,
12-hour retention, and one concurrent block upload. Home1 uses the chart
defaults of 500,000 samples/s, a 1,550,000-sample burst, 24-hour retention, and
20 concurrent uploads. Rate limiting rejects excess samples; it does not reduce
the collectors' Kubernetes watches or guarantee an immediate drop in sender
network retries. Retention is enforced asynchronously by the compactor and
does not immediately delete existing objects.

Mimir is the destination of the monitoring data, not the origin of the high
Kubernetes API traffic. See [Collectors](../Collectors/README.md) for the API
watch fan-out and [Exporters](../Exporters/README.md) for the highest-volume
metric sources.

Verify distributor accepted/rejected samples, active series, ingester WAL/head
size, block upload duration, compactor deletion markers, S3 throughput, and an
end-to-end query in Grafana. Render both site profiles before merging. Rollback
through Git/Argo CD; increasing retention does not restore blocks already
deleted, and lowering rate limits creates intentional monitoring gaps.
