# Configuration deployment

This deployment installs Stakater Reloader through Helm. It is owned by
`Apps/Operations/Configurations.yaml`, which selects the `core-dc1-talos-prod`
and `core-home1-talos-prod` infrastructure clusters. The ApplicationSet injects
each cluster's identity and in-cluster Kubernetes API endpoint before Lovely
renders the chart. See the upstream [Reloader chart README](https://github.com/stakater/Reloader/tree/master/deployments/kubernetes/chart/reloader)
and [Reloader usage documentation](https://github.com/stakater/Reloader#how-to-use-reloader).

Reloader restarts workloads when referenced ConfigMaps or Secrets change.
Confirm annotation/auto-discovery scope, RBAC and namespace selection before
enabling broader matching. A secret rotation can otherwise trigger many
simultaneous restarts.

After changes, update a non-critical referenced object and verify that only the
intended workload rolls and remains available.
