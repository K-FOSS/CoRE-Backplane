# Load testing deployment

This deployment installs the Grafana k6 Operator and is owned by
`Apps/Operations/Load.yaml`.

The operator executes distributed load tests described by custom resources.
Load tests can overload shared ingress, identity, databases, storage or
external services. Require explicit test targets, rate/duration limits and an
abort path. Do not allow arbitrary scripts or credentials from untrusted
namespaces.

Validate operator health with a small non-production test and monitor both the
generators and the target service.
