# CoRE-Backplane Storage/S3/SeaweedFS Stack

This stack deploys a separate SeaweedFS S3 lab on YXL with SeaweedFS object
replication, Longhorn PVC storage, and Authentik OIDC federation for S3 STS.
It is owned by the [SeaweedFS ApplicationSet](../../../Apps/Storage/S3/SeaweedFS.yaml)
and complements the existing [MinIO TenantLab](../TenantLab/README.md).

## Ownership, target and rendering

The ApplicationSet selects core bare-metal infrastructure clusters labelled
`dc1` and `yxl`; the current target is `core-dc1-talos-prod` in namespace
`core-prod`. This selector does not match Home1/YVR. Applications use the
Lovely renderer at repository `HEAD`, server-side apply and namespace
creation. The ApplicationSet preserves its generated Application's resources
when removed.

The [workload chart](Chart.yaml) renders the Seaweed custom resource, storage
classes, OIDC Secret and route. A separate YXL-only
[operator ApplicationSet](../../../../Apps/Storage/S3/SeaweedFS-Operator.yaml)
owns the official [SeaweedFS Operator chart](https://github.com/seaweedfs/seaweedfs-operator)
at version `0.1.43` (application `1.0.40`), including CRDs, controller,
webhook resources and cluster RBAC. Sync the operator child Application first
and wait for its CRDs to become Established before syncing the workload child
Application. The S3 workload image is pinned to the verified SeaweedFS 4.48
registry digest; the operator chart exposes a release tag rather than a digest
setting, so its image uses the chart's fixed `1.0.40` release tag.

## Architecture and configuration

The custom resource creates three masters, three volume servers, and one
filer. Masters use persistent metadata volumes. The filer keeps its namespace
and IAM metadata on a persistent volume. The single filer keeps this initial
lab compact; it is not a fully highly available metadata tier. The master
default replication setting `001` stores two object copies across the volume
servers. SeaweedFS documents its [Kubernetes operator](https://github.com/seaweedfs/seaweedfs-operator)
and [S3 IAM/OIDC configuration](https://github.com/seaweedfs/seaweedfs-operator/blob/master/IAM_SUPPORT.md).

The chart creates release-independent Longhorn StorageClasses named
`seaweedfs-yxl-longhorn-data` and `seaweedfs-yxl-longhorn-metadata`. Volume
server PVCs request `20Gi` each and use one Longhorn replica, while master and
filer metadata PVCs request `1Gi` and `2Gi` and use two Longhorn replicas.
This keeps SeaweedFS object copies distinct from Longhorn's block-level
replicas. Both classes use Longhorn V1, XFS, `best-effort` locality, expansion,
and `Retain`; the classes and their volumes need deliberate cleanup after the
lab is retired. Longhorn's [StorageClass reference](https://longhorn.io/docs/1.13.0/references/storage-class-parameters/)
describes the parameters used here.

OIDC client credentials are read from the existing `Minio/OIDC` CoreVault
entry through `mainvault-core`. The ExternalSecret templates a Secret-only
SeaweedFS IAM config and derives a stable STS signing key from the client
secret. The configured issuer is the YXL MinIO Authentik provider. A token
whose `policy` claim is `consoleAdmin` receives the S3 administrator role;
other authenticated users receive read-only access by default. The IAM API
is left read-only. SeaweedFS exchanges the identity token for temporary S3
credentials through `AssumeRoleWithWebIdentity`; clients use the normal
AWS-compatible STS flow.

The public S3 endpoint is `https://s3-seaweed.yxl.mylogin.space`. Its HTTPRoute
attaches to `main-gw` in `core-prod` and carries the `wan-mode: 'public'` label
for YXL ExternalDNS. Clients should use path-style bucket addressing at this
endpoint. The route does not expose the SeaweedFS filer or master management
ports.

## Reconciliation and verification

Build and inspect both charts from the repository root:

```bash
helm dependency build Storage/S3/SeaweedFS
helm lint Storage/S3/SeaweedFS
helm template seaweedfs-yxl Storage/S3/SeaweedFS --namespace core-prod
helm dependency build Storage/S3/SeaweedFS/Operator
helm lint Storage/S3/SeaweedFS/Operator
helm template seaweedfs-operator-yxl Storage/S3/SeaweedFS/Operator --namespace seaweedfs-operator-system
git diff --check -- Apps/Storage/S3/SeaweedFS.yaml Storage/S3
```

Before syncing, verify the YXL CoreVault OIDC entry is available to
`mainvault-core`, the Authentik token includes the `policy` claim used by the
role mapping, the Gateway accepts the route, and Longhorn has room for three
20Gi data PVCs plus metadata PVCs and Longhorn replicas. After reconciliation,
inspect the Seaweed resource and operator conditions, PVC/Longhorn volume
health, route acceptance and DNS publication. Exercise OIDC STS with both an
administrator and a non-admin account, then test signed S3 read/write using
the issued temporary credentials.

SeaweedFS IAM settings are read at process start. After rotating the CoreVault
OIDC secret, verify the Secret refresh and restart the filer workload so the
derived STS signing key and client credentials load together. STS sessions
signed by the previous key may stop working after rotation.

## Data retention and removal

The current MinIO Tenant and its PVCs are unchanged. The Seaweed Longhorn
StorageClasses retain their volumes when PVCs are deleted. Seaweed volume
replication `001` creates a second object copy inside SeaweedFS, but it is not
a backup. Back up important lab data independently and verify restore before
removing the stack. Removing the operator does not migrate the data; deleting
the Seaweed custom resource may remove its StatefulSets while retained PVCs
remain for recovery or explicit cleanup.
