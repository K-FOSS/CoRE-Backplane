# Cluster Broker chart

This chart packages a Submariner broker and publishes broker credentials
through a `PushSecret`.

## Deployment status

No direct `Apps/Network` ApplicationSet reference was found. Treat the chart as
inactive, indirectly consumed or experimental until its owner is confirmed.

Configuration is under `submariner-k8s-broker`; the dependency is conditional
and must be enabled. Deployment requires compatible member clusters, broker
API reachability, supported cluster/service CIDRs, and an authorized
PushSecret destination.

Verify broker health, member registration, connection status, cross-cluster
service discovery and real pod/service connectivity.
