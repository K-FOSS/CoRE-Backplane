# Resource operations deployment

This deployment installs Goldilocks and Descheduler and exposes Goldilocks
through Authentik/Gateway policy. It is owned by
`Apps/Infra/Resources.yaml`.

Goldilocks/VPA recommendations are advisory unless another process applies
them. Descheduler can evict workloads across the cluster. Review policies,
eviction limits, PDBs, priority classes, local storage and maintenance windows
before enabling new strategies.

Validate recommendations against observed workload behavior and canary
descheduling on non-critical workloads before fleet rollout.
