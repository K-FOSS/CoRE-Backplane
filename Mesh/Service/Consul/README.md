# CoRE-Backplane Mesh/Service/Consul Stack

This Helm wrapper deploys HashiCorp Consul through the upstream `consul` chart.
It contains only the values that differ from the upstream defaults.

Deployment-specific values, including server replica count, bootstrap
expectation, and rolling-update partition, are supplied by
[the owning ApplicationSet](../../../Apps/Hashicorp/Consul.yaml). They are
intentionally not duplicated in this chart.

## Home1 server topology

[The owner](../../../Apps/Hashicorp/Consul.yaml) requests three YVR servers,
with `bootstrapExpect: '3'`. Required hostname anti-affinity distributes them
across `srv2`, `srv3` and `hpc2`; the Home1-only `load=testing:NoSchedule`
toleration permits the third server on `hpc2` without changing node taints.
The third server uses the YVR control-plane node: `hpc3` lacked the hostname
label needed for consistent anti-affinity at rollout. Other sites keep one server. A second cluster generator selects the existing
Home1 registration using tenant, YVR region and cluster ID `1`, then overrides
replicas, bootstrap expectation and update partition. Using cluster generators
on both sides avoids the observed Go-template merge panic between cluster
string maps and nested List maps. See the
[ApplicationSet merge generator](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-Merge/). Each new ordinal receives a `50Gi` PVC from the
default storage class, observed as Longhorn with two storage replicas at YVR.
Consul Raft voters and Longhorn volume replicas are separate redundancy layers.
See the [upstream server scaling guidance](https://developer.hashicorp.com/consul/docs/manage/scale#number-of-consul-servers)
and [pinned server template](https://github.com/hashicorp/consul-k8s/blob/v1.7.0-rc1/charts/consul/templates/server-statefulset.yaml).

Expansion starts at update partition `3`, retaining the existing leader while
new servers join. Keep the observed `1` CPU / `8G` requests during this phase;
apply resource reductions separately after three healthy voters are established.
Then lower the partition one ordinal per Git/Argo change, verifying Raft and
Autopilot each time, as described in the [scaling runbook](RUNBOOK.md).
Do not reduce replicas or remove PVCs as a blind rollback after new peers join.

## Home1 resource requests

The intended Home1 sizing is `100m` CPU and `1Gi` memory requests.
During the initial three-server expansion the ApplicationSet temporarily
retains the live `1` CPU / `8G` requests for `core-home1-talos-prod`. Other sites inherit the existing
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
