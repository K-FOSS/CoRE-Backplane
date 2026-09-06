# Photos

This rendering unit deploys the [official Immich Helm chart](https://github.com/immich-app/immich-charts/tree/main/charts/immich)
version `0.12.0`, using Immich `v2.6.3`, at `photos.mylogin.space`. The chart
also uses the [BJW-S common library](https://github.com/bjw-s-labs/helm-charts/tree/common-5.0.1/charts/library/common)
through the upstream chart.

The Immich library is a dedicated `50Gi` Longhorn `ReadWriteMany` PVC named
`photos-library`, using the `photos-library` StorageClass. The StorageClass
uses one replica and a `Delete` reclaim policy; deleting the ApplicationSet
preserves Argo CD-managed resources, but deliberate PVC/StorageClass cleanup
deletes the volume. The library contains the user photo and video data and
must be included in backups before changing or removing this application.

The `photos` [`User` claim](../../Operations/SSO/User/README.md) creates the
Immich PostgreSQL role and database through the site-local Crossplane providers.
The workload consumes its generated `photos` connection Secret and connects to
`psql-local.<cluster>.<datacenter>.<region>.mylogin.space`. Immich requires a
PostgreSQL vector extension; this deployment selects `pgvector`, so the target
site-local PostgreSQL image must provide that extension. The chart bundles
[Valkey](https://github.com/immich-app/immich-charts/blob/main/charts/immich/values.yaml)
for the Immich job queue and persists no Valkey data.

The route is protected by the repository's Authentik Envoy external-authorization
path and the `Media Consumers` group. Verify the `User` claim, generated
Secret, PostgreSQL role/database and vector extension, PVC `Bound` status,
Immich server and machine-learning readiness, HTTPRoute `Accepted` status,
and an authenticated upload/download through the public hostname after Argo CD
reconciliation. See [Immich's Kubernetes guidance](https://docs.immich.app/install/kubernetes/)
and [database environment variables](https://docs.immich.app/install/environment-variables)
for upstream operational requirements.
