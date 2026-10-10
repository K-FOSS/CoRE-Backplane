# CoRE-Backplane Storage/S3

This directory contains independent S3-compatible lab deployments alongside
the existing MinIO service. The first alternative lab is the YXL-only
[SeaweedFS stack](SeaweedFS/README.md), owned by its
[workload ApplicationSet](../../Apps/Storage/S3/SeaweedFS.yaml) and separate
[operator ApplicationSet](../../Apps/Storage/S3/SeaweedFS-Operator.yaml). The existing MinIO
tenant remains owned by [TenantLab](../../Apps/Storage/S3/TenantLab.yaml).
Operator charts are maintained under [`Operators/`](Operators/README.md).

## Current deployments

MinIO remains the existing application S3 service. SeaweedFS is a separate
YXL lab for evaluating distributed object storage and OIDC-backed temporary
S3 credentials. Garage is being integrated as the YXL Mimir object store: the
cluster lives in [Observability/Common](../../Observability/Common/README.md),
while Mimir's Garage buckets and key live in
[Observability/Metrics](../../Observability/Metrics/README.md). Garage uses
Longhorn PVCs and Garage object replication independently of Longhorn block
replication. Mimir continues using its existing MinIO backend until the
current Mimir objects are migrated.

## Candidate follow-up labs

Garage's optional management UI is a third-party component; its team
restrictions do not replace Garage's S3 key permissions. Review the [Garage
feature overview](https://github.com/deuxfleurs-org/garage/blob/main-v2/doc/book/reference-manual/features.md)
and [Garage UI access-control limits](https://github.com/Noooste/garage-ui/blob/main/docs/access-control.md)
before exposing or relying on that management path.
