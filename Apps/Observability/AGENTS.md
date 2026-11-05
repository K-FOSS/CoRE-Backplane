# Observability fleet-owner guidance

This file adds fleet-owner rules for `Apps/Observability`. The
[repository-wide guidance](../../AGENTS.md) remains authoritative. When an
ApplicationSet points into `Observability/`, also follow the nearest
`AGENTS.md` in that implementation subtree; these instructions do not replace
it.

## Ownership and target selection

- Treat each file in this directory as the fleet owner for its matching
  `Observability/<component>` rendering unit. Start here before changing the
  chart so cluster selectors, list/merge generators, target namespaces,
  injected `LOVELY_HELM_MERGE` values, and all affected clusters are known.
- Keep fleet selection, site-specific endpoints, placement, and per-cluster
  feature switches here. Keep reusable workload behavior in the matching
  implementation directory. Do not hide a site-specific exception in chart
  defaults or copy general chart behavior into an ApplicationSet.
- Evaluate generator intersections rather than reading a list generator in
  isolation. A listed cluster must also satisfy the cluster selector, and
  injected values may come from both generator branches.
- Preserve the shared telemetry identity across sites. In particular, verify
  the rendered `cluster`, `dc`, `region`, tenant, cluster-domain, and backend
  endpoint values for every target. Do not infer YVR behavior from a YXL render
  or assume that a reachable Cilium global Service proves the intended site
  owns the active writer.

## Collector coordination

Changes to [`Collectors.yaml`](Collectors.yaml) must be reviewed with the
[Collector-specific guidance](../../Observability/Collectors/AGENTS.md), the
Collector values and templates, and the downstream Metrics, Logs, Traces,
Exporters, and Dashboards contracts.
The current internal signal agents send to the main `*-collectors-alloy`
gateway. The `alloy-otlp` Service remains the ingress for external OTLP clients
and forwards to that main gateway; do not add it back as an unnecessary hop for
internal Alloy agents.

Placement exceptions apply only to the workloads explicitly configured here.
For example, excluding a node from clustered collectors must not prevent the
node-local DaemonSets from collecting that node. Render and inspect every Alloy
custom resource and its resulting controller before changing affinity,
tolerations, controller type, replica count, environment placement, or service
address.

## Reconciliation and verification

Render the full Lovely unit with representative values for each distinct target
profile, not only a Helm chart with defaults. After publishing a change,
reconcile only the affected parent ApplicationSet and child Applications in
dependency order. Verify the source, Collector, backend, recording rule, and
Grafana query path on every affected site; Argo CD health and pod readiness are
not sufficient evidence that telemetry is complete or correctly labelled.
