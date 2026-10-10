# CoRE-Backplane Hashicorp/Vault Stack

This stack runs the shared Vault service. The
[Vault ApplicationSet](../../Apps/Hashicorp/Vault.yaml) owns the YXL and YVR
deployments; [Operations/Secrets](../../Operations/Secrets/README.md) documents
the platform secret-store consumers.

## Ownership, targets, and rendering

The ApplicationSet targets `core-dc1-talos-prod` in YXL and
`core-home1-talos-prod` in YVR, installing into each cluster's `core-prod`
namespace. It renders the pinned
[HashiCorp Vault Helm chart](https://developer.hashicorp.com/vault/docs/deploy/kubernetes/helm)
dependency at version `0.24.1`.

The YVR Vault chart owns the YVR-only `vault-longhorn` StorageClass, ordered
before the StatefulSet. Each YVR Vault pod requests one 50Gi ReadWriteOnce
PVC. Longhorn keeps two volume replicas per PVC, and
`migratable: 'false'` leaves Longhorn live volume migration disabled. The
class uses `Retain` so deleting a claim does not automatically delete its
backing volume. See Longhorn's
[StorageClass parameter reference](https://longhorn.io/docs/1.13.0/references/storage-class-parameters/)
for parameter behavior.

## Current and desired backend layout

YXL currently uses Consul storage at path `MainVault`. The YVR ApplicationSet
is configured for three Vault replicas with integrated Raft on local PVCs;
its Raft peers discover one another through YVR's own headless service. This
does not create cross-cluster Raft replication. YXL remains on its existing
Consul configuration until a later coordinated change.

Both current releases use the same Consul `MainVault` data. After the YVR data
migration, YVR's Raft state and YXL's Consul state will be separate copies and
can diverge. Do not treat both endpoints as writable sources of the same Vault
state after that cutover. Consumer routing and the later YXL migration remain
separate operational work.

Vault's transit seal remains backed by CoreVault. Raft storage does not replace
that seal dependency or the existing
[Vault Auto Unseal](../VaultAutoUnseal/README.md) recovery path.

## Consul migration and recovery

Changing the YVR Helm storage stanza does not copy the Consul data. Before
reconciling the backend switch, take and verify a Consul snapshot, schedule
Vault downtime, and run HashiCorp's documented
[Consul-to-Raft migration](https://developer.hashicorp.com/vault/docs/concepts/integrated-storage/migrate-consul-storage)
once against the shared Consul source and the YVR destination PVC. Vault must
be offline during this operation. Preserve the Consul source and snapshot
until Vault data and recovery have been verified. The
[`vault operator migrate` reference](https://developer.hashicorp.com/vault/docs/commands/operator/migrate)
describes the source/destination configuration and command.

The migration destination's Raft node ID must match the first YVR pod's
configured ID. The chart sets node IDs from pod names. Bring up the migrated
YVR member first, verify unseal and data, and then allow the remaining YVR
members to join through `retry_join`. Do not initialize a second independent
Raft cluster from the same Consul data.

Enabling Vault data storage adds a StatefulSet `volumeClaimTemplate`, which is
immutable on the existing release. Plan the StatefulSet replacement and pod
downtime explicitly; preserve the Consul source and any created PVCs. The
chart's server update strategy is `OnDelete`, so a ConfigMap update alone does
not switch a running pod from Consul to Raft. Do not use a force or replace
sync as a shortcut for the migration sequence.

## Operational verification

After migration, verify that YVR reports Raft storage, all three YVR peers are
healthy, the leader is stable, and transit auto-unseal works. Read and write a
representative non-secret test value through the Vault API, verify the
`mainvault-core` External Secrets store and its consumers, inspect all three
PVCs and Longhorn replica health, and test the snapshot/restore procedure.
Argo CD health and pod readiness alone do not prove the migration succeeded.
