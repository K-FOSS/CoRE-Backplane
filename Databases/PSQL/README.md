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

PGPool discovers every local PostgreSQL pod through a headless per-pod Service
and appends the site-specific remote peers supplied by the ApplicationSet. Its
replica count, image, resources, pool sizing and health-check intervals are
configured under `pooler` in `values.yaml`. The deployment currently consumes
the custom PGPool image through the mutable `latest` tag; replace it with a
verified immutable release or digest. See the upstream
[Pgpool-II backend settings](https://www.pgpool.net/docs/latest/en/html/runtime-config-backend-settings.html),
[connection pooling settings](https://www.pgpool.net/docs/latest/en/html/runtime-config-connection-pooling.html),
and [health-check settings](https://www.pgpool.net/docs/latest/en/html/runtime-config-health-check.html).

The default PGPool capacity is 64 children with four cached connection pools
across three PGPool replicas. This gives a worst-case pooled backend budget of
768 connections, or 18.75% of the main cluster's 4096 connections. The
remaining capacity is reserved for replication, operator activity and direct
clients. PostgreSQL worker limits are configured under `psql.tuning`; the
defaults allow eight worker processes, four parallel workers globally and two
workers per parallel query. Recalculate the connection budget whenever
`pooler.replicas`, `numInitChildren`, `maxPool` or
`psql.tuning.maxConnections` changes.

The ApplicationSet connects the k3s node1 and Home1 PGPool deployments to
their local `psql-main` pods and to the remote DC1 Talos PostgreSQL service.
The DC1 Talos PGPool uses k3s node1 as its remote peer. Local pods are generated
by the chart and must not also be repeated in `pooler.peers`, because duplicate
backend entries can route multiple PGPool node IDs to the same PostgreSQL pod.

The main CoRE PostgreSQL cluster maintenance windows are configured with
`psql.maintenanceWindows`. The default CRD value is `10:00-12:00`, evaluated
in UTC by the Zalando Postgres Operator, which corresponds to 02:00-04:00 PST
(UTC-08:00). This is a fixed UTC schedule and does not shift for Pacific
daylight time. Use the operator's
[maintenance window syntax](https://postgres-operator.readthedocs.io/en/latest/reference/cluster_manifest/)
for daily or weekday-qualified windows; set the list to empty to omit the CRD
field.

## LDAP configuration

LDAP endpoints and directory search settings are configured under `ldap` in
`values.yaml`. The core PostgreSQL cluster uses the top-level server; the
additional PostgreSQL cluster overrides it under `ldap.postgres`. Both use the
shared port, base DN, bind DN and search attribute. PGPool has its endpoint and
scheme under `ldap.pooler`, while pgAdmin uses the settings under
`ldap.pgadmin`.

The owning ApplicationSet selects `ldap-dc1.mylogin.space` for the dc1
clusters and `ldap-home1.mylogin.space` for the home1 cluster, then injects the
site endpoint into PostgreSQL, PGPool and pgAdmin through `LOVELY_HELM_MERGE`.

The bind password is still resolved from Vault at render/reconciliation time;
do not put LDAP credentials in Helm values. PostgreSQL LDAP authentication is
documented in the [PostgreSQL client authentication documentation](https://www.postgresql.org/docs/17/auth-ldap.html),
PGPool LDAP parameters in the [PGPool pool_hba documentation](https://www.pgpool.net/docs/latest/en/html/auth-pool-hba-conf.html),
and pgAdmin LDAP settings in the [pgAdmin LDAP authentication documentation](https://www.pgadmin.org/docs/pgadmin4/latest/ldap.html).

The checked-in `restore` value is operationally significant. Inspect rendered
output before every reconciliation and ensure restore resources reference the
intended source. A restore should use a new target/controlled cutover unless
the runbook explicitly requires replacement.

Validate Patroni leader/replicas, replication lag, quorum, client read/write,
PGPool backend state, LDAP/TLS, storage capacity, native backups and isolated
restore. Kubernetes/volume backup alone is not a transaction-consistent
PostgreSQL recovery plan.
