# Consul production scaling and upgrade runbook

Use this runbook to expand an existing single-server production datacenter,
right-size its memory, and upgrade Consul. Perform each phase as a separate
Argo CD change with its own health and rollback gate.

Do not combine scaling, resource reduction, a Consul version upgrade, and a
Helm chart upgrade in one sync.

## 1. Inventory the live deployment

Do not assume Git represents the running release. Record the release,
namespace, chart and application versions, StatefulSet, PVCs, storage class,
server image, leader, voters, and Raft protocol:

```bash
helm list -A
helm get values RELEASE -n NAMESPACE --all
helm get manifest RELEASE -n NAMESPACE
kubectl get sts,pods,pvc -n NAMESPACE -o wide
kubectl exec -n NAMESPACE SERVER_POD -- consul version
kubectl exec -n NAMESPACE SERVER_POD -- consul members
kubectl exec -n NAMESPACE SERVER_POD -- consul operator raft list-peers
kubectl exec -n NAMESPACE SERVER_POD -- consul operator autopilot state
```

Stop if there is no leader, a server is unhealthy, a PVC is not bound, or
Autopilot reports an unhealthy datacenter.

## 2. Create and verify a backup

Continuous Consul backups are confirmed to be replicating to Cloudflare R2
through the [Backups chart](../../../Backups/README.md#consul-backups). Before
maintenance, confirm that deployment remains healthy and that a recent object
exists.

Create a Consul snapshot and copy it outside the cluster:

```bash
kubectl exec -n NAMESPACE SERVER_POD -- \
  consul snapshot save /tmp/pre-change.snap
kubectl cp NAMESPACE/SERVER_POD:/tmp/pre-change.snap ./pre-change.snap
consul snapshot inspect ./pre-change.snap
```

Keep a second off-cluster copy. Document and rehearse snapshot restoration and
manual Raft recovery before changing the only production server. A volume
snapshot is useful as a second recovery mechanism, but does not replace a
Consul snapshot. The [Backups restore policy](../../../Backups/README.md#restore-policy)
describes the boundary between Velero and Consul recovery.

## 3. Render and review

Set the target cluster's ApplicationSet values to:

```yaml
values:
  replicas: '3'
  bootstrapExpect: '3'
  updatePartition: '3'
```

The upstream chart rejects `bootstrapExpect` values lower than `replicas`.
`bootstrapExpect` is a bootstrap setting, not a desired quorum size.
`updatePartition` prevents existing StatefulSet ordinals from immediately
receiving the changed pod template.

Render the ApplicationSet and chart, then review the Argo CD diff. The change
must:

- increase the StatefulSet replica count;
- create PVCs for the new ordinals;
- set `rollingUpdate.partition` to `3`;
- update `bootstrap-expect` to `3`; and
- leave the image, resources, storage class, claim template, and unrelated pod
  settings unchanged.

Do not proceed if the diff recreates the StatefulSet, replaces or removes a
PVC, changes an immutable field, or permits the existing server to restart
before the new servers join.

Ensure the pods can be placed on separate nodes or failure domains. Confirm
that the storage class has sufficient capacity, latency, and IOPS.

## 4. Scale from one server to three

Sync only after reviewing the rendered diff. Watch the StatefulSet and require
each new pod to become Ready:

```bash
kubectl rollout status statefulset/STATEFULSET -n NAMESPACE
kubectl get pods,pvc -n NAMESPACE -w
```

Verify the datacenter after all three pods are Ready:

```bash
kubectl exec -n NAMESPACE SERVER_POD -- consul members
kubectl exec -n NAMESPACE SERVER_POD -- consul operator raft list-peers
kubectl exec -n NAMESPACE SERVER_POD -- consul operator autopilot state
```

Require three alive servers, exactly one leader, three healthy voters, and no
failed Autopilot checks. Take and verify another snapshot.

Do not use two replicas as an intermediate steady state. A two-voter cluster
still loses quorum when either voter is unavailable.

Once all three voters are healthy, lower `updatePartition` one step at a time:

```text
3 -> 2 -> 1 -> 0
```

Review and sync each step separately. Wait for the affected server to become
Ready and repeat all three Consul health checks before continuing. Leave
`updatePartition` at `0` after the rollout is healthy.

## 5. Right-size memory

Every Consul server stores the complete Raft working set. Adding replicas
improves availability but does not divide memory usage between servers.

Observe memory through leadership changes, snapshots, compaction, and normal
peak traffic:

```promql
consul_runtime_alloc_bytes
container_memory_working_set_bytes{
  namespace="NAMESPACE",
  pod=~".*consul.*server.*"
}
rate(container_oom_events_total{
  namespace="NAMESPACE",
  pod=~".*consul.*server.*"
}[1h])
```

Size each server from its measured peak working set. HashiCorp recommends
approximately two to four times `consul.runtime.alloc_bytes`. Lower requests
and limits in a separate change, one conservative step at a time. Stop after an
OOM kill, readiness failure, Raft instability, or sustained memory pressure.

The chart currently requests 8 GB and limits each server to 32 GB. Three
servers therefore request about 24 GB but can consume up to 96 GB. Kubernetes
schedules from requests; limits determine the OOM boundary.

Check whether stale services, checks, sessions, ACL objects, or inappropriate
large KV values can be removed through supported Consul APIs. Never edit Raft
data or PVC contents directly.

## 6. Upgrade Consul

Choose a stable Consul and Consul-K8s chart combination supported by the
cluster's Kubernetes version. Review every intervening version's upgrade
notes. Non-LTS upgrades should jump no more than two minor version lines unless
HashiCorp provides a dedicated path.

The repository currently pins chart `1.7.0-rc1`. Do not add or retain explicit
control-plane or dataplane image overrides unless they match the target chart's
compatibility matrix. These components are tested as a set.

Keep three healthy servers throughout the upgrade. Start with
`updatePartition: 3`, apply the new template, and lower the partition one step
at a time:

```text
3 -> 2 -> 1 -> 0
```

At each step, update one server and require healthy results from:

```bash
consul members
consul operator raft list-peers
consul operator autopilot state
kubectl get pods,pvc -n NAMESPACE
kubectl logs -n NAMESPACE UPDATED_SERVER
```

Stop if the updated member does not rejoin, quorum is degraded, Autopilot is
unhealthy, or applications report errors. Upgrade followers before the leader
when the rollout mechanism permits it.

After all servers are healthy on the new version, take another snapshot. Return
`updatePartition` to `0` in a separately reviewed sync.

## Rollback boundaries

- Before scaling, restore the verified snapshot only if normal recovery cannot
  restore the original server.
- During scaling, do not delete PVCs. Diagnose or remove a failed new Raft peer
  with supported Consul commands before reducing replicas.
- During an upgrade, stop lowering `updatePartition`. Roll back only the most
  recently upgraded server when the target version supports downgrade.
- Never treat a Helm rollback as a data rollback. Confirm downgrade
  compatibility and retain all PVCs and snapshots.

Use a maintenance window, have an operator watch quorum, and verify the
recovery path in advance. Restarting a single-server datacenter always carries
outage risk; establishing three healthy voters is the first risk-reduction
milestone.
