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

Chart dependencies are pinned to the
[BJW-S common library 4.6.2](https://github.com/bjw-s-labs/helm-charts/releases/tag/common-4.6.2)
and the
[Runix pgAdmin4 chart 1.65.0](https://artifacthub.io/packages/helm/runix/pgadmin4/1.65.0).
Exact versions keep Lovely dependency resolution and rendered manifests
deterministic. Common 4.6.2 is the newest v4 release and supports Kubernetes
1.28 and newer; common 5 requires Kubernetes 1.31 and Helm 3.18 across every
rendering and target environment.

PGPool discovers every local PostgreSQL pod through a headless per-pod Service
and appends the site-specific remote peers supplied by the ApplicationSet. Its
workload shape, image, resources and memory volumes are embedded in
`templates/PGPool/PGPoolDeployment.yaml`; operational pool sizing, health
checks and site-specific peers remain under `pooler` in `values.yaml`. The
deployment pins the inspected custom PGPool image by digest so its binaries and
shell behavior remain reproducible. See the upstream
[Pgpool-II backend settings](https://www.pgpool.net/docs/latest/en/html/runtime-config-backend-settings.html),
[connection pooling settings](https://www.pgpool.net/docs/latest/en/html/runtime-config-connection-pooling.html),
and [health-check settings](https://www.pgpool.net/docs/latest/en/html/runtime-config-health-check.html).

PGPool uses three probe levels. A TCP startup probe allows up to one minute for
the listener to appear. The TCP liveness probe checks only that PGPool still
accepts connections, so a PostgreSQL outage does not create a PGPool restart
loop. The readiness script runs `SHOW POOL_NODES` with psql startup files
disabled, strict error handling and a bounded connection timeout; the pod
receives Service traffic only when an attached primary is reported. This
chart-owned script replaces the image's non-POSIX `grep | wc` check and is
delivered through the existing externally rendered `pgpool-config` Secret.

The default PGPool capacity is 64 children with four cached connection pools
across three PGPool replicas. This gives a worst-case pooled backend budget of
768 connections, or 18.75% of the main cluster's 4096 connections. The
remaining capacity is reserved for replication, operator activity and direct
clients. PostgreSQL worker limits are configured under `psql.tuning`; the
defaults allow eight worker processes, four parallel workers globally and two
workers per parallel query. Recalculate the connection budget whenever
the embedded replica count, `numInitChildren`, `maxPool` or
`psql.tuning.maxConnections` changes.

PGPool mounts bounded, memory-backed `emptyDir` volumes at `/tmp`, `/dev/shm`,
and `/var/run/postgresql`; their size limits live with the workload definition
in `templates/PGPool/PGPoolDeployment.yaml`. `/dev/shm` supports the pre-forked PGPool processes and
shared caches, while the runtime volume holds the PostgreSQL and PCP sockets.
Memory-backed `emptyDir` usage counts toward the pod's memory consumption, so
include it when adjusting the PGPool memory request and limit. Kubernetes
documents this behavior under
[memory-backed `emptyDir` volumes](https://kubernetes.io/docs/concepts/storage/volumes/#emptydir).

PGPool also has a dedicated memory-backed `/tmp/pgpool` runtime volume for its
PID, status, OID metadata and password-file mount. Query caching uses PGPool's
Memcached client and a chart-owned `dragonfly-pgpool` Dragonfly instance on
port 11211, so the three PGPool replicas at a site share cached results without
using the general-purpose `dragonfly-core` service. The cache is deliberately
ephemeral: it has one replica, cache mode enabled, no snapshot configuration,
and no public Service annotation. The runtime volume remains pod-local,
bounded by the workload template, charged against pod memory and discarded
whenever the pod is replaced. See the upstream
[Pgpool-II in-memory query cache](https://www.pgpool.net/docs/latest/en/html/runtime-in-memory-query-cache.html),
[Dragonfly configuration reference](https://github.com/dragonflydb/dragonfly#configuration),
and [Dragonfly Operator repository](https://github.com/dragonflydb/dragonfly-operator).

Dragonfly's Memcached listener does not provide PGPool with the password and
TLS authentication path used by Redis clients. A NetworkPolicy therefore
restricts port 11211 to same-namespace pods labelled
`app.kubernetes.io/name: pgpool`; the instance's Redis port is not admitted.
The Dragonfly CR and policy sync before the PGPool workload and depend on the
cluster-wide Dragonfly Operator and CRD. If the cache is unavailable, PGPool
query-cache operations fail and the pooler may need to be restarted after the
cache recovers. Roll back by setting `pooler.queryCache.method` to `shmem`,
rendering, and reconciling the PSQL ApplicationSet; that also removes the
dedicated Dragonfly resources from desired state.

PGPool sends application logs exclusively to `stderr` and has its internal
logging collector disabled, so it does not create or rotate log files in the
container. Kubernetes exposes that stream to the cluster logging pipeline;
node-level container-runtime buffering and the external logging system retain
logs according to their own policies. See the upstream
[Pgpool-II logging destinations](https://www.pgpool.net/docs/latest/en/html/runtime-config-logging.html).

The pooler rejects excess clients before all 64 children are occupied, uses a
256-entry listen backlog, serializes `accept()` calls to avoid waking every
pre-forked child, and recycles a child after 1000 accepted connections. Backend
health and streaming-replication checks run every 10 seconds. Node detachment
is health-check driven: ordinary backend errors and terminated sessions do not
trigger failover. Automatic standby reattachment is rate-limited to five
minutes. Relation metadata expires after five minutes and unlogged-table
checks remain enabled so read routing does not send unsafe queries to replicas.
See the upstream [Pgpool-II connection settings](https://www.pgpool.net/docs/latest/en/html/runtime-config-connection.html)
and [failover behavior](https://www.pgpool.net/docs/latest/en/html/runtime-config-failover.html).

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
