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
- PostgreSQL metrics from a `postgres_exporter` sidecar, scraped by the
  cluster's Alloy annotation autodiscovery and forwarded to Mimir.

## Monitoring

The chart enables the [prometheus-community PostgreSQL exporter](https://github.com/prometheus-community/postgres_exporter)
as a sidecar on both the shared `psql-main` cluster and the site-local
PostgreSQL cluster. The Zalando operator injects `POSTGRES_USER` and
`POSTGRES_PASSWORD` into sidecars; the exporter uses those runtime values to
connect to the local PostgreSQL process over loopback. Credentials are never
stored in chart values or annotations.

The sidecar exposes port 9187 and the operator attaches the standard
`prometheus.io` annotations to every database pod. The cluster-local
[Alloy collector](../../Observability/Collectors/README.md) discovers those
annotated pods and forwards the resulting Prometheus metrics to Mimir. This
does not create a `ServiceMonitor`, so it does not require a separate
Prometheus instance or cross-cluster Service.

Verify after reconciliation that the exporter container is ready on every
PostgreSQL pod, `http://<pod-ip>:9187/metrics` responds from inside the cluster,
and Alloy reports successful scrapes and remote writes. A failed exporter must
not affect PostgreSQL readiness; disable it by setting
`monitoring.postgresExporter.enabled` to `false` and reconciling the owning
ApplicationSet.

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
PGPool's Deployment explicitly opts in to the installed
[Stakater Reloader](../../Operations/Configuration/README.md) for the named
`pgpool-config` Secret using its
[secret reload annotation](https://docs.stakater.com/reloader/latest/reference/annotations.html).
When External Secrets updates that Secret from the rendered configuration,
Reloader triggers a Deployment rollout. The
[rolling update](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#rolling-update-deployment)
keeps all three existing replicas available and permits one surge replica;
readiness gates each replacement and the PCP smart-stop hook drains the old
pod. During rollout, plan for up to four PGPool replicas and a corresponding
temporary pooled backend budget of 1024 connections.

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
health and streaming-replication checks run every 10 seconds. A failed health
check is retried three times with a two-second delay before node detachment, so
a brief PostgreSQL or network interruption can recover without removing the
backend. Node detachment is health-check driven: ordinary backend errors and
terminated sessions do not trigger failover. Automatic standby reattachment is
enabled and rate-limited to once per minute after streaming replication is
healthy again. The local backend application names match the Zalando/Patroni
pod names (`psql-main-N`); the remote peers are master Services and therefore
do not have fixed walreceiver identities. Relation metadata expires after five
minutes and unlogged-table checks remain enabled so read routing does not send
unsafe queries to replicas.
See the upstream [Pgpool-II connection settings](https://www.pgpool.net/docs/latest/en/html/runtime-config-connection.html)
and [failover behavior](https://www.pgpool.net/docs/latest/en/html/runtime-config-failover.html).

Each PGPool pod also runs a small auto-recovery sidecar. It reads detached-node
status through Pgpool's PCP control interface, which remains available when no
backend is attached, then connects directly to each detached endpoint. It uses
`pcp_attach_node` only when the endpoint reports `pg_is_in_recovery() = false`.
This lets a recovered primary rejoin without allowing the sidecar to promote
PostgreSQL or attach a recovering standby; Patroni owns promotion, and PGPool
owns standby reattachment through `auto_failback`. Recovery inventory and
attachment errors are reported to the sidecar log. The sidecar uses the same
pinned PGPool image and the existing operator credential Secret, and can be
disabled with `pooler.autoRecovery.enabled`.
PCP is bound to loopback and its Unix socket is kept in the shared
`/tmp/pgpool` runtime volume so the sidecar can reach it after a backend
network interruption without exposing the administrative interface outside the
pod.
The sidecar follows the upstream [PCP command and password-file
interface](https://pgpool.net/docs/latest/en/html/pcp-commands.html).

The ApplicationSet connects the k3s node1 and Home1 PGPool deployments to
their local `psql-main` pods and to the remote DC1 Talos PostgreSQL service.
The DC1 Talos PGPool uses k3s node1 as its remote peer. Local pods are generated
by the chart and must not also be repeated in `pooler.peers`, because duplicate
backend entries can route multiple PGPool node IDs to the same PostgreSQL pod.

The ApplicationSet's checked-in cluster list is the PostgreSQL topology source
of truth. A [matrix generator](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-Matrix/)
retains the complete list while its
[list generator `elementsYaml`](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-List/#dynamically-generated-elements)
expands one target at a time; the merge generator then adds current destination
and label data from registered Argo CD cluster Secrets. The one entry with
`values.hub: true` supplies its cluster name, datacenter and region to the exact
`psql.standbyHost` value in every render, while every other entry becomes a
standby. The same cluster entries provide the main PostgreSQL instance count
through `values.replicas`: the checked-in desired topology currently places the
hub at `core-home1-talos-prod` in YVR with `values.replicas: '3'`, rendered as
three PostgreSQL instances. The DC1 Talos and k3s targets each use one instance.
This describes desired configuration and does not by itself prove live
readiness. Exactly one hub is required and ApplicationSet templating fails if
the list contains zero or multiple hubs.

To move the hub, set the former entry's `values.hub` to `false` and the new
entry's value to `true` in the same Git change. After Argo CD reconciliation,
verify the former hub is a healthy standby, the new hub is writable, every
standby PostgreSQL resource reports the new `spec.standby.standby_host`, and
Patroni is streaming from the intended hub before removing the old endpoint.
Roll back by restoring both former `values.hub` settings and reconciling the
ApplicationSet.

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

The pgAdmin dependency values contain only site-specific overrides. Its
`pgadmin-envs` ExternalSecret supplies LDAP configuration and the bootstrap
password expected by the Runix chart, so the rendered chart does not create a
Secret from the upstream example password. The bootstrap identity is required
by the container even though pgAdmin is configured to authenticate users only
through LDAP. Persistent pgAdmin state uses a 10 GiB claim from each target
cluster's default storage class.

Each pgAdmin HTTPRoute uses `pgadmin.domain`. The owning ApplicationSet injects
`pgadmin.<cluster>.<datacenter>.<region>.mylogin.space`, giving every target a
distinct public endpoint instead of sharing `pgadmin.mylogin.space`. For
example, the DC1 Talos endpoint is
`pgadmin.core-dc1-talos-prod.dc1.yxl.mylogin.space` and the Home1 endpoint is
`pgadmin.core-home1-talos-prod.home1.yvr.mylogin.space`.

The owning ApplicationSet selects `ldap-dc1.mylogin.space` for the dc1
clusters and `ldap-home1.mylogin.space` for the home1 cluster, then injects the
site endpoint into PostgreSQL, PGPool and pgAdmin through `LOVELY_HELM_MERGE`.

The bind password is still resolved from Vault at render/reconciliation time;
do not put LDAP credentials in Helm values. PostgreSQL LDAP authentication is
documented in the [PostgreSQL client authentication documentation](https://www.postgresql.org/docs/17/auth-ldap.html),
PGPool LDAP parameters in the [PGPool pool_hba documentation](https://www.pgpool.net/docs/latest/en/html/auth-pool-hba-conf.html),
pgAdmin LDAP settings in the [pgAdmin LDAP authentication documentation](https://www.pgadmin.org/docs/pgadmin4/latest/ldap.html),
and pgAdmin SMTP settings in the [pgAdmin configuration documentation](https://www.pgadmin.org/docs/pgadmin4/latest/config_py.html).

## LDAP PostgreSQL administrator

Set `psql.ldapAdminUsername` in the site values to an approved LDAP username
when that identity needs PostgreSQL administrator access. Each site-local
render creates a Crossplane Terraform `Workspace` bound to the matching
per-cluster `psql-<datacenter>-<region>` `ProviderConfig`; the workspace creates
the username as a passwordless PostgreSQL `LOGIN`/`SUPERUSER` role. LDAP
authenticates the username through the existing `pg_hba` rule, and PostgreSQL
applies the role's administrator privileges. Leaving the value empty does not
create the workspace or role. Verify the Workspace and role reconciliation
before testing an LDAP login, and clear the value before removing the access
workflow so Terraform can reconcile the role deletion.

The Terraform PostgreSQL provider's [role resource](https://registry.terraform.io/providers/cyrilgdn/postgresql/latest/docs/resources/postgresql_role)
is used for the role lifecycle, while Crossplane's [Terraform Workspace](https://marketplace.upbound.io/providers/upbound/provider-terraform/latest/resources/tf.upbound.io/Workspace/v1beta1)
supplies the workflow and provider binding.

pgAdmin sends mail through `mail.mylogin.space` using STARTTLS on port 587. It
authenticates with the username and password generated for the `pgadmin-core`
User claim and published through the existing `PSQL/PGAdmin/Credentials` Vault
path. The default sender is generated per target as
`pgadmin-<region>-<datacenter>@mail.mylogin.space` through the chart-owned
`pgadmin-envs` ExternalSecret.

The checked-in `restore` value is operationally significant. Inspect rendered
output before every reconciliation and ensure restore resources reference the
intended source. A restore should use a new target/controlled cutover unless
the runbook explicitly requires replacement.

Validate Patroni leader/replicas, replication lag, quorum, client read/write,
PGPool backend state, LDAP/TLS, storage capacity, native backups and isolated
restore. Kubernetes/volume backup alone is not a transaction-consistent
PostgreSQL recovery plan.
