# MySQL chart

This chart deploys Percona XtraDB Cluster through the Percona operator. It is
owned by `Apps/Storage/Database/MySQL.yaml`.

## Components

- PXC database, HAProxy and ProxySQL configuration.
- TLS and LDAP authentication.
- Crossplane-generated S3 backup user.
- ExternalSecret/PushSecret credential synchronization.
- S3 backup storage configuration.

Initial deployment currently has a known LDAP/plugin ordering problem: enabling
LDAP configuration during first initialization can cause startup failure.
Treat the existing manual disable/re-enable process as a defect to automate and
test, not a normal safety guarantee.

Before changes, verify cluster size/quorum, storage capacity, TLS, LDAP,
proxy health and a recent backup. Although S3 storage is configured, scheduled
backup entries may be disabled; confirm actual backup objects and perform an
isolated restore test.
