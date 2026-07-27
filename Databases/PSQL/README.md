# PostgreSQL chart

This chart deploys CoRE PostgreSQL clusters managed by the Zalando operator,
plus PGPool, pgAdmin, services and credential automation. It is owned by
`Apps/Storage/PSQL.yaml`.

## Components

- Patroni-based PostgreSQL cluster and per-instance services.
- PGPool streaming-replication routing and TLS.
- pgAdmin route, authentication and secrets.
- LDAP authentication.
- ExternalSecret and PushSecret resources for administrators and application
  users.
- Crossplane/provider credentials.
- Optional restore cluster resource.

The checked-in `restore` value is operationally significant. Inspect rendered
output before every reconciliation and ensure restore resources reference the
intended source. A restore should use a new target/controlled cutover unless
the runbook explicitly requires replacement.

Validate Patroni leader/replicas, replication lag, quorum, client read/write,
PGPool backend state, LDAP/TLS, storage capacity, native backups and isolated
restore. Kubernetes/volume backup alone is not a transaction-consistent
PostgreSQL recovery plan.
