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

Validate bucket read/write, S3 signature/authentication, dashboard OIDC,
LDAP users, TLS/DNS, metrics and Crossplane provider access. Back up critical
objects to an independent site/account and test restoring both data and bucket
policy/users.
