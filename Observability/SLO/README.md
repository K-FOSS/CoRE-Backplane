# Service-level objectives

This chart wraps the pinned [Sloth Helm chart](https://github.com/slok/sloth/tree/main/helm-chart)
for Prometheus-compatible SLO generation. The
[`core-observability-slo` ApplicationSet](../../Apps/Observability/SLO.yaml)
currently selects only `core-home1-talos-prod` and deploys into `core-prod`.

There are no site-specific Sloth values or SLO specifications in this directory,
so current behavior is the upstream chart deployment only. Desired SLOs must be
added explicitly and their generated PrometheusRule resources must be consumed
by the collector/ruler path. This stack does not perform cluster-wide workload
discovery and is not a material source of Kubernetes API monitoring traffic.

Before adding an objective, document its indicator query, ownership, error
budget window, alert routing, and missing-data behavior. Render the generated
rules, validate PromQL against Mimir, and confirm the rules are selected by the
active controller. Roll back through Git/Argo CD; deleting an SLO removes its
future evaluation but does not delete historical metric series.
