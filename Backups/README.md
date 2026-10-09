# CoRE backup infrastructure

This chart installs the backup services used by CoRE production clusters. It is
deployed by [`Apps/Infra/Backups.yaml`](../Apps/Infra/Backups.yaml) through an
Argo CD `ApplicationSet`.

The chart provides two independent backup paths:

| Path | Protects | Destination | Recovery mechanism |
| --- | --- | --- | --- |
| Velero | Kubernetes resources and selected pod volumes | Cloudflare R2 | Velero restore |
| `consul-backup-s3` | Consul state exported through the Consul API | Cloudflare R2 | Consul-supported snapshot restore |

These paths do not replace one another. A successful Velero backup does not
prove that Consul state is recoverable, and a Consul snapshot does not preserve
Kubernetes resources or application volumes.

## Deployment model

The ApplicationSet selects clusters labelled with:

```text
mylogin.space/tenant=core.mylogin.space
resolvemy.host/env=prod
```

Each generated Argo CD application:

- deploys this chart to `velero-system`;
- uses server-side apply;
- preserves managed resources if the ApplicationSet entry is deleted;
- assigns the cluster name as the Velero and Consul object-store prefix; and
- controls the Consul backup deployment per cluster.

Current Consul backup placement:

| Argo CD cluster | Consul backup |
| --- | --- |
| `core-dc1-talos-prod` | Enabled; backs the YXL Consul datacenter used by main Vault |
| `core-home1-talos-prod` | Enabled; backs the YVR Consul datacenter used by CoreVault |
| `dc1-k3s-node1` | Disabled |

The k3s row is the current Git configuration. At the October 9, 2026 live
inspection, `dc1-k3s-node1` still had a `consul-backup` Deployment carrying
the `dc1-k3s-node1-backups` tracking label and pointing directly to the Talos
Consul endpoint. The current chart values no longer render that Deployment,
but it remains live until its owning Application successfully prunes it. Keep
the Talos endpoint available for that existing consumer until cleanup is
planned and verified separately.

The chart creates the destination namespace with the privileged Pod Security
enforcement level. Velero's node agent needs access to host-mounted pod
volumes, so changing this namespace policy can prevent file-system backups from
running.

### Required cluster services

Before deploying the chart, a cluster must provide:

- Argo CD and the `argocd-lovely-plugin` used by the ApplicationSet;
- External Secrets Operator and the `ExternalSecret` CRD;
- the `mainvault-core` and `corevault-rootsecrets` `ClusterSecretStore`
  resources;
- network access to Cloudflare R2; and
- a reachable Consul server when Consul backup is enabled.

Helm dependencies are pinned in `Chart.yaml`:

| Dependency | Purpose |
| --- | --- |
| `velero` 5.2.1 | Velero controllers, CRDs, schedules, and node agent |
| BJW-S `common` 4.4.0 | Generates the Consul backup Deployment |

## Data and credential flow

```text
Vault / ClusterSecretStore
        |
        +--> backups-velero-cloudflare-s3 Secret --> Velero --> Cloudflare R2
        |
        +--> consul-s3 Secret --> consul-backup-s3 --> Cloudflare R2
```

Secrets are materialized by External Secrets Operator. They are not stored in
this repository and should not be decoded during routine troubleshooting.

The chart also creates `backups-velero-minio-s3` from
`Backups/Velero/S3/Minio`. No active `BackupStorageLocation` references that
secret; it is credential staging for the existing MinIO integration, not an
active backup destination in this chart.

## Velero

Velero uses the AWS object-store plugin with an S3-compatible Cloudflare R2
endpoint. The active `BackupStorageLocation` is `cloudflare-s3`, backed by the
`velero-backup` bucket.

The ApplicationSet overrides the location's prefix with the Argo CD cluster
name:

```text
velero-backup/<cluster-name>/...
```

This isolates each cluster's backup objects inside the shared bucket. Do not
remove or reuse a prefix for a different cluster without first reviewing the
existing backups.

### Credentials

The `cloudflare-s3-backups` `ExternalSecret` reads:

| Setting | Value |
| --- | --- |
| ClusterSecretStore | `mainvault-core` |
| Remote key | `Backups/Velero/CloudFlare` |
| Remote properties | `AccessKey`, `SecretKey` |
| Generated Secret | `backups-velero-cloudflare-s3` |
| Generated Secret key | `cloud` |

The R2 endpoint is supplied through the ApplicationSet's manifest-generation
configuration. Keep the endpoint and credentials aligned with the bucket
defined there.

### Schedules and coverage

| Schedule | Runs | Retention | Resource scope | File-system volume backup |
| --- | --- | --- | --- | --- |
| `core-prod` | Hourly | 24 hours | Resources labelled `resolvemy.host/env=prod` | Enabled by `defaultVolumesToFsBackup` |
| `core` | Daily | 240 hours | All resources in Velero's default scope | Not enabled by this schedule |

CSI snapshots are disabled and the Velero node agent is enabled. The node agent
makes file-system backup available, but it does not cause every schedule or
volume to use it. The hourly `core-prod` schedule explicitly opts in. The daily
`core` schedule protects Kubernetes resources unless a workload opts a volume
in through a supported Velero annotation or another policy.

`useOwnerReferencesInBackup` is enabled for both schedules. Deleting a Schedule
can therefore garbage-collect Backup objects owned by it; consider this before
renaming or replacing a schedule.

### Velero health checks

```bash
kubectl get backupstoragelocations.velero.io -n velero-system
kubectl describe backupstoragelocation cloudflare-s3 -n velero-system
kubectl get schedules.velero.io -n velero-system
kubectl get backups.velero.io -n velero-system --sort-by=.metadata.creationTimestamp
kubectl describe backup -n velero-system BACKUP_NAME
kubectl get daemonset,pod -n velero-system
kubectl logs -n velero-system deployment/velero-core
```

Expected results:

- `cloudflare-s3` reports `Available`;
- each schedule has recent Backup objects;
- recent Backup objects report `Completed`;
- node-agent pods are ready on eligible nodes; and
- Velero logs contain no persistent authentication, upload, or repository
  errors.

Treat `PartiallyFailed` as a failed health check until every item error has
been reviewed. A completed resource backup also does not prove that application
data is consistent or restorable.

## Consul backups

When `consul.enabled` is true, the chart creates:

- the `consul-backup` Deployment;
- the `consul-s3-backups` `ExternalSecret`; and
- the resulting `consul-s3` Secret.

The Deployment is generated through the BJW-S common library and runs
[`consul-backup-s3` `v0.0.4`](https://github.com/sputnik-systems/consul-backup-s3/tree/v0.0.4).
It takes a Consul snapshot daily at `00:00` and retains snapshots for `744h`
(31 days), explicitly configured by the Deployment arguments. It writes the
snapshots to R2 using the configured S3 prefix. This chart does not create a
`CronJob`; the long-running backup process owns scheduling, rotation, and
upload. Consul snapshots are point-in-time backups of the Consul server state;
see HashiCorp's [Consul snapshot and restore guidance](https://developer.hashicorp.com/consul/docs/manage/disaster-recovery/backup-restore).

### Vault storage coverage

Main Vault uses the YXL Consul datacenter and stores its data under the Consul
path `MainVault`. CoreVault is hosted in YVR and stores its data under
`MainCoreVault` in the YVR Consul datacenter; YXL and YVR consumers use that
CoreVault service. These are separate Consul datacenters, so each needs its own
snapshot stream. The `core-dc1-talos-prod` backup deployment targets YXL Consul
and uses the `core-dc1-talos-prod` R2 prefix. The `core-home1-talos-prod`
deployment targets YVR Consul and uses the `core-home1-talos-prod` prefix.

HashiCorp documents that Vault's Consul-backed storage data is encrypted by
Vault and recommends native Consul snapshots for this backend. Before moving
main Vault to Integrated Storage, use the latest verified YXL Consul snapshot
as the source-data recovery point, then follow Vault's
[Consul-to-Raft Kubernetes migration procedure](https://developer.hashicorp.com/vault/docs/deploy/kubernetes/consul-to-raft).
The migration must keep Vault offline while copying data. A Consul snapshot is
not a Vault Raft snapshot and cannot be restored with `vault operator raft
snapshot restore`.

R2 also encrypts stored objects at rest with Cloudflare-managed AES-256 and
uses TLS for client transfers, as described in its
[data security documentation](https://developers.cloudflare.com/r2/reference/data-security/).
This setup relies on Vault's storage encryption and R2's server-side
encryption; it does not add customer-managed client-side encryption to the
snapshot archive. Keep the Vault recovery keys and R2 credentials independently
available as described below.

The Consul backup's S3 credentials are read through `corevault-rootsecrets`
from CoreVault at `Backups/Consul/S3/CloudFlare`. Since CoreVault and its
credential path depend on the YVR Consul datacenter, keep a recovery copy of
the R2 access credentials and CoreVault unseal material outside Vault, Consul,
and the clusters. Do not treat the configured backup as disaster-recovery proof
until an operator has verified a recent object in each relevant R2 prefix and
rehearsed retrieval and restore using those independent credentials and keys.

### Consul endpoint selection

Unless a per-cluster override is supplied, the ApplicationSet derives:

```text
<cluster-name>-server.core-<environment>.svc.cluster.local:8500
```

The explicit production overrides point the enabled backups at the Talos YXL
and Home1 YVR Consul servers. Consul backups remain disabled for
`dc1-k3s-node1`, so the generic fallback below is not used there. The k3s
Consul client agents join the Talos Consul datacenter through the endpoint
configured by the [Consul ApplicationSet](../Apps/Hashicorp/Consul.yaml).

The generic fallback would derive the old k3s-local address below, but its
Consul server is being disabled as part of the client-agent join. Do not enable
Consul backups for `dc1-k3s-node1` without explicitly pointing them to the
Talos server:

```text
dc1-k3s-node1-server.core-prod.svc.cluster.local:8500
```

Override the endpoint only when the Consul Service does not follow that naming
convention:

```yaml
- name: CLUSTER_NAME
  values:
    consul:
      enabled: true
      address: custom-consul.example.internal:8500
```

An empty `address` in the ApplicationSet means "use the derived address"; it
does not produce an empty argument in the Deployment.

### Consul credentials

The `consul-s3-backups` `ExternalSecret` reads:

| Setting | Value |
| --- | --- |
| ClusterSecretStore | `corevault-rootsecrets` |
| Remote key | `Backups/Consul/S3/CloudFlare` |
| Remote properties | `AccessKey`, `SecretKey`, `Bucket`, `URL` |
| Generated Secret | `consul-s3` |

The Secret provides the R2 bucket and endpoint as environment variables and an
AWS credentials file mounted read-only at `/home/.aws/credentials`.

### Consul health checks

```bash
kubectl get deployment,pod -n velero-system \
  -l app.kubernetes.io/name=consul-backup
kubectl rollout status deployment/consul-backup -n velero-system
kubectl get externalsecret consul-s3-backups -n velero-system
kubectl describe externalsecret consul-s3-backups -n velero-system
kubectl logs deployment/consul-backup -n velero-system
```

Verify that the Deployment is available, the ExternalSecret reports ready, and
logs show successful exports. Confirm recent objects through the approved R2
administration path without exposing their credentials.

Before scaling or upgrading Consul, also create and verify a change-specific
snapshot using the
[Consul production runbook](../Mesh/Service/Consul/RUNBOOK.md#2-create-and-verify-a-backup).
See the [Consul chart documentation](../Mesh/Service/Consul/README.md) for the
server topology and operating model.

## Restore policy

This chart automates backup creation, not disaster recovery. No automated
Consul restore resource or Velero Restore is defined.

During recovery:

1. Define the authoritative recovery point and affected cluster before making
   changes.
2. Preserve the original backup objects and PVCs until recovery validation is
   complete.
3. Use Velero for Kubernetes resources and volumes actually captured by
   file-system backup.
4. Use a verified Consul snapshot and supported Consul snapshot procedures for
   the Consul state machine.
5. Restore the Consul datacenter that owns the selected Vault storage path
   (YXL for main Vault; YVR for CoreVault). Unseal CoreVault using its
   independently held recovery keys, then validate CoreVault transit and main
   Vault health before restoring dependent services.
6. Do not restore a live Consul server PVC as though it were an ordinary
   stateless workload.
7. Do not run Velero and Consul state restores concurrently without a written
   ordering and ownership plan.
8. Validate Consul membership, Raft health, Autopilot, application health, and
   restored data before declaring recovery complete.

Backup presence is not restore proof. Restore tests should be performed
regularly in an isolated environment and should record the selected backup,
elapsed recovery time, observed data loss, and validation results.

## Configuration

Direct chart values for Consul are deliberately small:

```yaml
consul:
  enabled: true
  address: consul-server.example.svc.cluster.local:8500
```

The Consul workload definition lives in
`templates/Consul/common.yaml`. Cluster-specific enablement, endpoint
derivation, Velero bucket, and object prefixes live in the ApplicationSet.

When changing backup behavior, review both files; rendering the chart with
`values.yaml` alone does not include the per-cluster ApplicationSet prefix.

## Local validation

Build dependencies and render both Consul variants:

```bash
helm dependency build
helm lint . --set consul.prefix=example-site
helm template backups . --namespace velero-system \
  --set consul.enabled=true \
  --set consul.address=consul-server.example.svc.cluster.local:8500 \
  --set consul.prefix=example-site
helm template backups . --namespace velero-system \
  --set consul.enabled=false
```

Check that:

- the enabled render contains one `consul-backup` Deployment and its
  ExternalSecret;
- the disabled render contains neither Consul resource;
- `cloudflare-s3` references `backups-velero-cloudflare-s3`;
- no resolved credential values appear in rendered or committed files; and
- the ApplicationSet render adds a unique Velero prefix for every cluster.
- the ApplicationSet render adds the same unique cluster prefix to Consul
  backup arguments.

After deployment, repeat the runtime health checks above and verify a recent
object at each destination. Rendering and reconciliation alone do not prove
that a backup was uploaded successfully.

## Legacy resources

`templates/Velero/Secret.yaml` and `templates/Velero/ServiceAccount.yaml`
currently create `velero-core` compatibility resources in `kube-system`, while
the active release runs in `velero-system`. Their purpose and consumers should
be confirmed before changing or removing them. They are not the R2 credential
Secret used by the active `BackupStorageLocation`.
