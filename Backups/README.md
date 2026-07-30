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
- assigns the cluster name as the Velero object-store prefix; and
- controls the Consul backup deployment per cluster.

Current Consul backup placement:

| Argo CD cluster | Consul backup |
| --- | --- |
| `dc1-k3s-node1` | Enabled |
| `core-dc1-talos-prod` | Disabled |
| `core-home1-talos-prod` | Disabled |

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
`ghcr.io/sputnik-systems/consul-backup-s3:v0.0.4`. It continuously exports data
from the configured Consul API endpoint to R2. This chart does not create a
`CronJob`; backup timing, object naming, and retention behavior are controlled
by the backup application and object-store configuration.

### Consul endpoint selection

Unless a per-cluster override is supplied, the ApplicationSet derives:

```text
<cluster-name>-server.core-<environment>.svc.cluster.local:8500
```

For the currently enabled cluster this becomes:

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
5. Do not restore a live Consul server PVC as though it were an ordinary
   stateless workload.
6. Do not run Velero and Consul state restores concurrently without a written
   ordering and ownership plan.
7. Validate Consul membership, Raft health, Autopilot, application health, and
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
derivation, Velero bucket, and object prefix live in the ApplicationSet.

When changing backup behavior, review both files; rendering the chart with
`values.yaml` alone does not include the per-cluster ApplicationSet prefix.

## Local validation

Build dependencies and render both Consul variants:

```bash
helm dependency build
helm lint .
helm template backups . --namespace velero-system \
  --set consul.enabled=true \
  --set consul.address=consul-server.example.svc.cluster.local:8500
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

After deployment, repeat the runtime health checks above and verify a recent
object at each destination. Rendering and reconciliation alone do not prove
that a backup was uploaded successfully.

## Legacy resources

`templates/Velero/Secret.yaml` and `templates/Velero/ServiceAccount.yaml`
currently create `velero-core` compatibility resources in `kube-system`, while
the active release runs in `velero-system`. Their purpose and consumers should
be confirmed before changing or removing them. They are not the R2 credential
Secret used by the active `BackupStorageLocation`.
