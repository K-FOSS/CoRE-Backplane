# S3 TenantLab chart

This chart deploys a MinIO Tenant with S3/API and dashboard exposure,
monitoring, Authentik OIDC, LDAP, Crossplane provider configuration and
Vault-backed credentials. It is owned by
`Apps/Storage/S3/TenantLab.yaml`.

Important values include cluster/site identity, tenant name, replica count,
node selector, storage class/size, domains, secret-store paths, Prometheus and
OIDC/LDAP settings.

For the standalone one-server deployment, set `s3.storage.volumeName` to the
existing Longhorn Volume CR name. The chart creates a cluster-scoped PV whose
`spec.csi.volumeHandle` points to that volume, then binds it to the chart-managed
PVC in the release namespace. It sets the PV reclaim policy to `Retain` so
removing the claim does not delete the Longhorn volume. The configured capacity,
filesystem type, data engine and replica attributes must match the existing
Longhorn volume. The PV storage class matches the chart-created storage class;
this class is used for PV/PVC matching and does not provision this static PV.

Longhorn requires an existing volume to be detached before a new pod uses it
([PV/PVC creation for an existing volume](https://longhorn.io/docs/1.12.1/nodes-and-volumes/volumes/create-volumes/)).
Verify that the volume is detached and healthy, and that no workload uses it,
before reconciling the PV and allowing MinIO to start. `s3.storage.existingClaim`
mounts an existing PVC instead; set only one of these values. A Longhorn volume
name is not a PVC name, and the volume itself remains in `longhorn-system` while
the MinIO PVC is in the release namespace.

The PV uses `Retain`. Removing the claim leaves the Longhorn volume and PV data
in place; the released PV retains its claim reference and requires an explicit
recovery or cleanup decision before reuse. Do not delete the Longhorn Volume CR
or the PV when preserving the data.

The chart currently keeps the standalone MinIO path at one server/one PVC so
existing object data remains attached. New PVCs use the release-scoped
`<release>-longhorn-2` StorageClass: Longhorn v1 with two full replicas,
`best-effort` locality, and XFS. This is storage redundancy, not MinIO
distributed erasure coding. Two Longhorn replicas are the deliberate default
for this data-intensive workload; Longhorn recommends two when capacity or
performance cost matters and three or more storage nodes are available.

The StorageClass does not change an existing PVC or its Longhorn volume.
Longhorn documents that StorageClass parameters apply only at volume creation
([StorageClass parameters](https://longhorn.io/docs/1.12.1/references/storage-class-parameters/)).
For each existing S3 PVC, first verify the volume name, current health,
replica placement, free capacity, and a tested backup. Then increase that
existing Longhorn Volume's `spec.numberOfReplicas` from `1` to `2` through the
Longhorn UI or an explicitly targeted `kubectl` change, and wait for the new
replica to become healthy before moving on. Do not recreate the PVC or change
its `volumeName`.

Changing the MinIO setting from one server to four is a separate migration:
the distributed Tenant creates four new PVCs and cannot consume the current
standalone PVC as its four-volume erasure set. Keep the current standalone
release serving data, provision a separate four-server Tenant, copy and
verify objects, quiesce writes, run a final copy, and only then switch the
route. Do not set `replicas: 4` in the existing ApplicationSet until that
migration is planned and capacity/placement have been verified. See the
[MinIO Operator Tenant documentation](https://min.io/docs/minio/kubernetes/upstream/operations/install-deploy-manage/deploy-minio-tenant.html)
for the distributed volume model.

## Peer S3 providers

The owning [S3 TenantLab ApplicationSet](../../../Apps/Storage/S3/TenantLab.yaml)
uses an ApplicationSet matrix to provide each release with its peer S3
clusters. For every entry in `crossplane.peers`, the chart creates both a
[Crossplane Minio ProviderConfig](https://github.com/vshn/provider-minio/tree/main/examples)
and a [Crossplane Terraform ProviderConfig](https://docs.crossplane.io/latest/packages/providers/provider-terraform/),
plus an [External Secrets ExternalSecret](https://external-secrets.io/latest/api/externalsecret/).

Peer credentials are read from the configured secret store at
`<rootPrefix>/<peer-cluster>/Credentials`, using the `AccessKey` and
`AccessSecretKey` properties. The generated Minio provider name is
`s3-<peer-cluster>` and the Terraform provider name is
`tf-s3-<peer-cluster>`. Both use the endpoint
`https://s3.<peer-cluster>.<datacenter>.<region>.<domain>`.

When adding or removing a peer, update the matrix entry for every affected
cluster and verify the corresponding Vault/CoreVault credential path exists.
Provider readiness should be checked after ExternalSecret reconciliation;
successful manifest generation alone does not verify remote S3 access.

Validate bucket read/write, S3 signature/authentication, dashboard OIDC,
LDAP users, TLS/DNS, metrics and Crossplane provider access. Back up critical
objects to an independent site/account and test restoring both data and bucket
policy/users.
