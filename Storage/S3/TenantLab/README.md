# S3 TenantLab chart

This chart deploys a MinIO Tenant with S3/API and dashboard exposure,
monitoring, Authentik OIDC, LDAP, Crossplane provider configuration and
Vault-backed credentials. It is owned by
`Apps/Storage/S3/TenantLab.yaml`.

Important values include cluster/site identity, tenant name, replica count,
node selector, storage class/size, domains, secret-store paths, Prometheus and
OIDC/LDAP settings.

The chart permits low replica counts and currently defaults to one replica.
That is a single storage failure domain, not highly available object storage.
Confirm erasure-set requirements, disks/PVC retention, free capacity and node
placement before changing replicas or storage.

## Peer S3 providers

The owning [S3 TenantLab ApplicationSet](../../../Apps/Storage/S3/TenantLab.yaml)
uses an ApplicationSet matrix to provide each release with its peer S3
clusters. For every entry in `crossplane.peers`, the chart creates both a
[Crossplane Minio ProviderConfig](https://github.com/vshn/provider-minio/tree/main/examples)
and a [Crossplane Terraform ProviderConfig](https://docs.crossplane.io/latest/packages/providers/provider-terraform/),
plus an [External Secrets ExternalSecret](https://external-secrets.io/latest/api/externalsecret/).

Peer credentials are read from the configured secret store at
`<rootPrefix>/<peer-cluster>/Credentials`, using the `AccessKey` and
`AccessSecretKey` properties. The generated provider names are
`s3-<peer-cluster>`, and their endpoints are
`https://s3.<peer-cluster>.<datacenter>.<region>.<domain>`.

When adding or removing a peer, update the matrix entry for every affected
cluster and verify the corresponding Vault/CoreVault credential path exists.
Provider readiness should be checked after ExternalSecret reconciliation;
successful manifest generation alone does not verify remote S3 access.

Validate bucket read/write, S3 signature/authentication, dashboard OIDC,
LDAP users, TLS/DNS, metrics and Crossplane provider access. Back up critical
objects to an independent site/account and test restoring both data and bucket
policy/users.
