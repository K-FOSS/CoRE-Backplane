# Metrics exporters

This chart deploys selected parts of the pinned
[`kube-prometheus-stack`](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack),
plus the component-specific
[`smartctl-exporter`](https://github.com/prometheus-community/helm-charts/tree/main/charts/prometheus-smartctl-exporter)
and [`ipmi-exporter`](https://github.com/prometheus-community/helm-charts/tree/main/charts/prometheus-ipmi-exporter)
charts. The
[`core-observability-exporters` ApplicationSet](../../Apps/Observability/Exporters.yaml)
targets both infrastructure clusters and `dc1-k3s-node1`.

## Current behavior

The stack creates Prometheus Operator CRDs/controllers, recording and alerting
rules, kube-state-metrics, node-exporter, kubelet/cAdvisor and API-server
ServiceMonitors, and hardware exporters. The Prometheus resource is configured
with zero replicas; Grafana Alloy in [Collectors](../Collectors/) consumes the
generated monitor CRs and remote-writes their samples to Mimir. Kustomize moves
smartctl resources and its monitor selection to `kube-system`.

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
namespaces, scrape intervals, and the absence of a Prometheus pod. In-cluster,
check exporter targets in Alloy, kube-state-metrics and node-exporter readiness,
and Mimir accepted/rejected sample metrics. Roll back via Git/Argo CD. Removing
the stack also removes monitor definitions and can invalidate rules and
dashboards even when exporters remain running.
