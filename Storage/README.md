# CoRE storage charts

The `Storage` directory contains persistent block storage, S3/object storage,
cache/distribution services, search, CDN access and supporting tools.

| Chart | Purpose | Fleet entry point |
| --- | --- | --- |
| [Base](Base/README.md) | Longhorn, storage classes and storage UI policy. | `Apps/Storage/Base.yaml` |
| [CDN](CDN/README.md) | S3-backed HTTP bucket/proxy exposure and SLOs. | `Apps/Storage/CDN.yaml` |
| [Dragonfly CoRE](Dragonfly/CoRE/README.md) | Dragonfly distribution/cache service and S3 integration. | `Apps/Storage/Dragonfly/CoRE.yaml` |
| [Dragonfly Operator](Dragonfly/Operator/README.md) | Kustomize-imported Dragonfly Operator wrapped in a Lovely deployment directory. | `Apps/Storage/Dragonfly/Operator.yaml` |
| [KeyDB](KeyDB/KeyDBChart/README.md) | Redis-compatible StatefulSet and services. | `Apps/Storage/Redis.yaml` |
| [S3 Operator](S3/Operator/README.md) | MinIO Operator. | `Apps/Storage/S3/Operator.yaml` |
| [S3 TenantLab](S3/TenantLab/README.md) | MinIO tenant, identity, routes and monitoring. | `Apps/Storage/S3/TenantLab.yaml` |
| [Bytebase](Databases/ByteBase/ByteBaseChart/README.md) | Database schema-management application. | No direct ApplicationSet currently found. |
| [Search](Search/README.md) | OpenSearch Operator. | No direct ApplicationSet currently found. |

`Storage/S3/KJDev` contains a legacy/manually composed MinIO tenant rather than
a Helm chart; its existing README remains relevant during migration.

In this repository a `Chart.yaml` does not imply that Helm is the only resource
source. Lovely can combine chart templates, Kustomize resources, remote HTTP
assets and patches within the same deployment directory. Inspect the complete
directory and owning ApplicationSet, not only `templates/`.

## Data-safety principles

- Replication is not backup.
- A Kubernetes resource backup is not necessarily an application-consistent
  data backup.
- Backups stored in the same site, credentials domain or storage system do not
  cover that failure domain.
- Snapshot, backup, restore and deletion behavior must be tested.
- Capacity planning must reserve room for rebuilds, failover, compaction and
  maintenance—not only normal data.

Before changing storage classes, replica counts, node selectors, disks,
endpoints or credentials, map every PVC/bucket/client affected and preserve an
independent recovery path.
