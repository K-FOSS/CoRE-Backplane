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
new servers join. The October 4 expansion kept the observed `1` CPU / `8G`
requests until three healthy voters were established, then applied the smaller
requests separately. Lower the partition one ordinal per Git/Argo change,
verifying Raft and Autopilot each time, as described in the
[scaling runbook](RUNBOOK.md). The steady-state partition is `0`.
Do not reduce replicas or remove PVCs as a blind rollback after new peers join.

## YXL server placement

The YXL Talos child application `core-dc1-talos-prod-consul` keeps one Consul
server and assigns weight `100` to the `srv7` hostname through preferred node
affinity. This is a scheduler preference: if `srv7` cannot host the pod,
Kubernetes may place it on another eligible node. The Talos server keeps its
`1` CPU and `8G` memory requests and `8` CPU limit, with no memory limit. Its
rolling-update partition is `0` so the server can receive the shared
`bootstrapExpect: 3` setting alongside the two K3s servers. The existing
server has persisted Raft state; verify it remains leader and healthy before
syncing the K3s child. For later scale or rollout work, use the
[scaling runbook](RUNBOOK.md).

The placement and resource rules are injected by the owning
[ApplicationSet](../../../Apps/Hashicorp/Consul.yaml); other sites are
unaffected. The hostname follows the YXL node identity documented in the
[cluster environment](../../../Operations/Clusters/ENVIRONMENT.md).

## DC1 K3s Consul servers

The `dc1-k3s-node1` child runs two Consul server agents in the same `dc1`
datacenter as `core-dc1-talos-prod`. Each K3s server uses Consul `retry_join`
to discover the Talos server at
`consul.core-dc1-talos-prod.dc1.yxl.mylogin.space`; this is LAN gossip joining,
not Consul cluster peering between independent datacenters. The chart's
`server.extraConfig` supplies that address. The
[Consul agent join reference](https://developer.hashicorp.com/consul/docs/reference/agent/configuration-file/join)
documents `retry_join`, and the [Consul Helm chart reference](https://developer.hashicorp.com/consul/docs/reference/k8s/helm#server)
documents server replicas, bootstrap expectations, storage and affinity.

The shared `bootstrapExpect` is `3` for the one Talos server and two K3s
servers. Sync the Talos child first, verify its existing persisted server
remains healthy, then sync K3s. The K3s Kubernetes cluster currently has one
node, so the chart's default required server pod anti-affinity is cleared to
allow both replicas to run there. They are separate Raft voters but share that
node and its failure domain; three Consul servers across only two hosts do not
provide tolerance to loss of either host. Add another server on an independent
host before treating this as a fault-tolerant three-server topology. See
HashiCorp's [Consul deployment guidance](https://developer.hashicorp.com/consul/docs/deploy/server)
for server-count and failure-tolerance planning.

The server pods use the stack's existing `1` CPU / `8Gi` memory request and
`8` CPU limit. Kustomize removes the K3s server memory limit. Their StatefulSet
requests `50Gi` per replica on K3s's default `local-path` StorageClass; these
volumes are node-local and are not a cross-node recovery mechanism. The
previous zero-replica local server had no PVC at the October 9 inspection, so
the two server PVCs will be newly provisioned. Keep PVCs as recovery data and
use the [Consul recovery runbook](RUNBOOK.md) before restoring or deleting
server state. Kubernetes resource requests and limits are described in the
[Kubernetes resource management guide](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/).

## Home1 resource requests

The ApplicationSet injects `100m` CPU and `1Gi` memory requests for each of
the three `core-home1-talos-prod` servers, totaling `300m` CPU and `3Gi` RAM. Other sites inherit the existing
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
