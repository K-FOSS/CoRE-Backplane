# Configuration deployment

This deployment installs Stakater Reloader through Helm. It is owned by
`Apps/Operations/Configurations.yaml`.

Reloader restarts workloads when referenced ConfigMaps or Secrets change.
Confirm annotation/auto-discovery scope, RBAC and namespace selection before
enabling broader matching. A secret rotation can otherwise trigger many
simultaneous restarts.

After changes, update a non-critical referenced object and verify that only the
intended workload rolls and remains available.
