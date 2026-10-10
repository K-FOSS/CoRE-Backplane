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

The Vault chart owns the site-local `vault-longhorn` StorageClass, ordered
before the StatefulSet. Each Vault pod requests one 50Gi ReadWriteOnce PVC.
Longhorn keeps two volume replicas per PVC, and
`migratable: 'false'` leaves Longhorn live volume migration disabled. The
class uses `Retain` so deleting a claim does not automatically delete its
backing volume. See Longhorn's
[StorageClass parameter reference](https://longhorn.io/docs/1.13.0/references/storage-class-parameters/)
for parameter behavior.

## Current and desired backend layout

YXL Consul at path `MainVault` is the migration source. The first migration
target is a single YXL Raft member on its 50Gi PVC. YVR is held at zero during
this phase; its existing PVC is retained and is not started from the in
progress copy. The migration init container and ConfigMap are rendered only for
the YXL release, with destination node ID
`core-dc1-talos-prod-core-vault-prod-0`.

Keep YXL at one replica until Vault reports Raft storage, unsealing works, and
representative data reads and writes succeed. Do not run Vault against the
Consul source while migration runs. The Consul source and a verified snapshot
must remain available until recovery is proven. Any later YVR rollout must be
planned as its own Raft membership or data migration; Vault's Raft peers do not
automatically span the two sites.

Vault's transit seal remains backed by CoreVault. Raft storage does not replace
that seal dependency or the existing
[Vault Auto Unseal](../VaultAutoUnseal/README.md) recovery path.

## Consul migration and recovery

Changing the YXL Helm storage stanza does not copy the Consul data. Before
reconciling the backend switch, take and verify a Consul snapshot, schedule
Vault downtime, and run HashiCorp's documented
[Consul-to-Raft migration](https://developer.hashicorp.com/vault/docs/concepts/integrated-storage/migrate-consul-storage)
once against the shared Consul source and the YVR destination PVC. Vault must
be offline during this operation. Preserve the Consul source and snapshot
until Vault data and recovery have been verified. The
[`vault operator migrate` reference](https://developer.hashicorp.com/vault/docs/commands/operator/migrate)
describes the source/destination configuration and command.

The migration destination's Raft node ID must match the first YXL pod's
configured ID. The chart sets node IDs from pod names. Bring up only the
migrated YXL member first and verify unseal and data before adding any other
Raft members. Do not initialize a second independent Raft cluster from the
same Consul data.

The migration phase is rendered by the ApplicationSet as one YXL replica plus
a `vault-storage-migration` init container and ConfigMap. The migration file
uses source path `MainVault`, destination `/vault/data`, and node ID
`core-dc1-talos-prod-core-vault-prod-0`. The init container mounts the same PVC
as the Vault server. Remove this migration-only configuration before scaling
up; otherwise each new pod would try to migrate the source again.

Enabling Vault data storage adds a StatefulSet `volumeClaimTemplate`, which is
immutable on an existing release. YXL's Main Vault StatefulSet is currently
absent, so the first YXL sync creates it with its PVC. The existing YVR
StatefulSet is scaled to zero; preserve its PVC while the YXL migration is
evaluated. The chart's server update strategy is `OnDelete`, so a ConfigMap
update alone does not switch a running pod from Consul to Raft.

## Operational verification

After migration, verify that YXL reports Raft storage, its single member is
healthy, the leader is stable, and transit auto-unseal works. Read and write a
representative non-secret test value through the Vault API, verify the
`mainvault-core` External Secrets store and its consumers, inspect the YXL PVC
and Longhorn replica health, and test the snapshot/restore procedure. Argo CD
health and pod readiness alone do not prove the migration succeeded.
