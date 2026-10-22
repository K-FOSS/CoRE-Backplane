# Load testing deployment

This deployment installs the Grafana k6 Operator and is owned by
`Apps/Operations/Load.yaml`.

The operator executes distributed load tests described by custom resources.
Load tests can overload shared ingress, identity, databases, storage or
external services. Require explicit test targets, rate/duration limits and an
abort path. Do not allow arbitrary scripts or credentials from untrusted
namespaces.

The chart dependency is the pinned [Grafana k6 Operator](https://github.com/grafana/k6-operator)
release published through the [Grafana Helm repository](https://grafana.github.io/helm-charts).

Validate operator health with a small non-production test and monitor both the
generators and the target service.
