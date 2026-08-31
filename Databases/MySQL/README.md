# MySQL chart

This chart deploys Percona XtraDB Cluster through the Percona operator. It is
owned by `Apps/Storage/Database/MySQL.yaml`.

The owning ApplicationSet creates one MySQL deployment in each of the three
explicit core fleet clusters (`dc1-k3s-node1`, `core-dc1-talos-prod`, and
`core-home1-talos-prod`) when the matching core cluster object is present. The
cluster selector supplies the environment and namespace; the chart resources
remain namespaced and use the existing Vault-backed credential flow.

## Components

- PXC database, HAProxy and ProxySQL configuration.
- TLS and LDAP authentication.
- Crossplane-generated S3 backup user.
- ExternalSecret/PushSecret credential synchronization.
- S3 backup storage configuration.

The chart follows the [Percona XtraDB Cluster Helm chart documentation](https://docs.percona.com/percona-operator-for-mysql/helm.html)
and the [External Secrets Operator documentation](https://external-secrets.io/latest/).

Initial deployment currently has a known LDAP/plugin ordering problem: enabling
LDAP configuration during first initialization can cause startup failure.
Treat the existing manual disable/re-enable process as a defect to automate and
test, not a normal safety guarantee.

Before changes, verify cluster size/quorum, storage capacity, TLS, LDAP,
proxy health and a recent backup. Although S3 storage is configured, scheduled
backup entries may be disabled; confirm actual backup objects and perform an
isolated restore test.
