# Name Server chart

This chart deploys CoRE's PowerDNS authoritative service and PowerDNS-Admin.
It is owned by `Apps/Network/NS.yaml`.

## Components and dependencies

- PowerDNS through the BJW-S common chart.
- Database credentials and a Crossplane-generated user.
- PowerDNS-Admin API/UI, identity and authentication policy.
- ExternalSecret and PushSecret resources.
- Service discovery and ExternalDNS annotations.

It depends on PostgreSQL, Authentik, Vault/External Secrets, Gateway API,
certificates, and correct external delegation/glue records.

After changes, query each authoritative server directly and verify SOA
serials, replication/transfer behavior, delegation, DNSSEC if enabled and
PowerDNS-Admin access. DNS caches can hide errors, so check TTLs before
migrations.
