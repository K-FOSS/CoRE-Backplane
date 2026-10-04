# CoRE-Backplane Mesh/Service/Consul Stack

This Helm wrapper deploys HashiCorp Consul through the upstream `consul` chart.
It contains only the values that differ from the upstream defaults.

Deployment-specific values, including server replica count, bootstrap
expectation, and rolling-update partition, are supplied by
[the owning ApplicationSet](../../../Apps/Hashicorp/Consul.yaml). They are
intentionally not duplicated in this chart.

## Home1 resource requests

The ApplicationSet injects `100m` CPU and `1Gi` memory requests only for
`core-home1-talos-prod`. Other sites inherit the existing
[chart values](values.yaml). The upstream `consul.server.resources` values
are documented in the [Consul Helm chart reference](https://developer.hashicorp.com/consul/docs/reference/k8s/helm#server)
and the [pinned chart source](https://github.com/hashicorp/consul-k8s/tree/v1.7.0-rc1/charts/consul).

The October 4, 2026 Home1 sample measured about `33m` CPU and `99Mi` RAM,
compared with the admitted `1` CPU / `24G` requests. The new requests reduce
reserved capacity; they do not reduce memory limits or temporary-volume
capacity. These are short samples, so observe snapshot, startup and recovery
peaks after rollout. DC1's observed Consul memory demand was much higher and
must be reviewed independently.

Reconcile the owning ApplicationSet and Home1 child application, then verify
Consul leadership, API access, dependent Vault health and snapshot backups as
outlined in the [runbook](RUNBOOK.md). Changing the single server pod's
resource requests can briefly interrupt Consul and dependent Vault access.
Rollback means removing the Home1 request override in Git and reconciling the
same owner and child; it does not restore the old live `24G` request unless
that value is explicitly recorded, because the shared chart default is `8G`.
See [Kubernetes resource management](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
for request and limit behavior.

## Documentation

- [Production scaling and upgrade runbook](RUNBOOK.md)
- [Upgrade work](TODO.md)
- [Cluster and Consul backups](../../../Backups/README.md)

## Validation

Render and inspect the chart before merging a change:

```bash
helm dependency build
helm lint .
helm template consul .
```

Production changes must also be reviewed in Argo CD before syncing.
