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
- PostgreSQL metrics from a `postgres_exporter` sidecar, exposed through
  internal metrics Services and scraped by the cluster's Alloy ServiceMonitor
  collector before being forwarded to Mimir.
- PGPool frontend, backend and health-check metrics from a site-local exporter
  sidecar on the two Talos production clusters.

## Monitoring

The [official Pgpool-II exporter](https://github.com/pgpool/pgpool2_exporter/blob/v1.2.2/README.md)
runs beside each PGPool process on HOME1 and DC1 Talos. The
[fleet ApplicationSet](../../Apps/Storage/PSQL.yaml) enables it for those two
clusters; the legacy K3s target is excluded. Its v1.2.2 image is pinned by
digest in [`values.yaml`](values.yaml). The exporter connects over pod loopback
using the existing operator-managed `opsadmin` Secret and TLS; no credential is
stored in Git. An internal metrics Service and
[`ServiceMonitor`](templates/Monitoring/PGPoolExporter.yaml) expose each pod on
port 9719 to Alloy, which adds site labels before forwarding to Mimir. This
Service has no external DNS or ingress. Exporter failure does not gate PGPool
readiness, so database traffic can continue while monitoring is repaired.

The [PGPool dashboard ConfigMap](templates/Monitoring/PGPoolDashboard.yaml)
imports the [chart-owned dashboard](dashboards/pgpool.json) into the
`PostgreSQL` folder. Its queries use the [upstream exporter metrics](https://github.com/pgpool/pgpool2_exporter/blob/v1.2.2/README.md#metrics)
to show exporter health, frontend occupancy, backend status, and Pgpool's own
backend health-check failures, retries and durations. Those health-check
counters are separate from Kubernetes readiness-probe failures; inspect pod
events and the kubelet probe metrics for the latter. Verify the exporter
ServiceMonitor has one healthy target per PGPool pod, `pgpool2_frontend_total`
and `pgpool2_pool_health_check_stats_fail_count` appear in Mimir, and the
dashboard resolves those series. Set `monitoring.pgpoolExporter.enabled` to
`false` for a site and reconcile its PostgreSQL Application to remove the
sidecar, metrics Service, ServiceMonitor and dashboard ConfigMap there.

The chart enables the pinned [nbari `pg_exporter`](https://github.com/nbari/pg_exporter)
0.22.2 image as a sidecar on both the shared `psql-main` cluster and the
site-local PostgreSQL cluster. This is the exporter associated with the pinned
[PostgreSQL Monitoring dashboard](https://grafana.com/grafana/dashboards/24298-postgresql-monitoring-dashboard/)
revision 11: its `database` collector provides the PostgreSQL 14+ session
counters (`pg_stat_database_sessions_total` and related metrics), session-time
counters, and checksum metrics used by the dashboard. The exporter also
provides the dashboard's database, activity, vacuum, lock, I/O, replication,
and other enabled collector families. The Zalando operator injects
`POSTGRES_USER` and `POSTGRES_PASSWORD` into sidecars; the exporter consumes
those runtime values through standard PostgreSQL environment variables and
connects to the local PostgreSQL process over loopback. Credentials are never
stored in chart values or annotations.

The sidecar exposes port 9187. This chart creates one internal ClusterIP
metrics Service and one `ServiceMonitor` for `psql-main` and the site-local
cluster. The cluster-local [Alloy collector](../../Observability/Collectors/README.md)
discovers those ServiceMonitors, adds the cluster, datacenter and region
labels, sets `instance` to `<cluster>/<psql-cluster>/<pod-name>`, and forwards the resulting
Prometheus metrics to Mimir. The metrics Services are not published through
ingress or external DNS.

Site-local PSQL also renders a dedicated `md5` `pg_hba` entry for the
cluster-local Forgejo role and database (`forgejo-<cluster>`), limited to the
Forgejo source pod CIDR injected by [`Apps/Storage/PSQL.yaml`](../../Apps/Storage/PSQL.yaml).
The current production CIDRs are `172.20.48.0/21` for DC1 and `172.20.56.0/21`
for Home1. This compatibility rule is narrower than the legacy LDAP catch-all
rules and does not create or publish a password; the Forgejo `User` claim
remains the identity and credential owner.

The chart also imports Grafana's pinned [PostgreSQL Monitoring
Dashboard](https://grafana.com/grafana/dashboards/24298-postgresql-monitoring-dashboard/)
revision 11 into the `PostgreSQL` folder through
[`templates/Monitoring/PostgreSQLDashboard.yaml`](templates/Monitoring/PostgreSQLDashboard.yaml).
The dashboard covers exporter health, connections, query activity, cache and
I/O, locks, vacuum, WAL, replication and database size. The chart explicitly
enables the exporter collectors used by the dashboard for database sessions,
activity, vacuum, locks, I/O, replication and related PostgreSQL state. The
`statements` collector is not enabled because it requires PostgreSQL's
`pg_stat_statements` extension and `shared_preload_libraries` provisioning;
enabling it without those prerequisites causes scrape errors. Panels for that
collector remain empty until the extension is deliberately added.

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
deployment pins the inspected custom PGPool image at the October 2026
`sha256:62d5239f2c3bc53066327867968294142146d7a8bc548a51ac239bac9050ebdb`
release by digest so its binaries and shell behavior remain reproducible. See
the upstream
[Pgpool-II backend settings](https://www.pgpool.net/docs/latest/en/html/runtime-config-backend-settings.html),
[connection pooling settings](https://www.pgpool.net/docs/latest/en/html/runtime-config-connection-pooling.html),
and [health-check settings](https://www.pgpool.net/docs/latest/en/html/runtime-config-health-check.html).

The pool keeps backend connections for reuse. A failed primary can remain
marked down in PGPool's runtime status file after a container restart. The
[fleet ApplicationSet](../../Apps/Storage/PSQL.yaml) bounds primary discovery
to 60 seconds on DC1 Talos, allowing PGPool to finish startup even if the
HOME1 primary was previously detached. Its local PCP listener can then accept
the recovery sidecar's reattachment request after the sidecar independently
verifies a writable primary. DC1 Talos readiness also requires PGPool's
observed `pg_status` and `pg_role` to report an available primary; this avoids
advertising a pool whose attached primary is currently unreachable.
The same DC1 Talos override sets the `pgpool-config` ExternalSecret refresh
interval to one minute, so its rendered Secret updates after the ConfigMap
change and Stakater Reloader rolls PGPool. Other sites retain the default
External Secrets interval and unlimited primary search. See
[Pgpool-II primary search and failback](https://www.pgpool.net/docs/latest/en/html/runtime-config-failover.html)
and [startup behavior](https://www.pgpool.net/docs/latest/en/html/server-start.html),
plus [External Secrets refresh behavior](https://external-secrets.io/latest/api/externalsecret/).

PGPool uses three probe levels. A TCP startup probe allows up to one minute for
the listener to appear. The TCP liveness probe checks only that PGPool still
accepts connections, so a PostgreSQL outage does not create a PGPool restart
loop. The readiness script runs `SHOW POOL_NODES` with psql startup files
disabled, strict error handling and a bounded connection timeout; the pod
receives Service traffic only when the site-specific primary checks pass. This
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
workers per parallel query. `workMem` sets PostgreSQL's per-operation sort/hash
memory budget; `sharedBuffers` sets the PostgreSQL buffer pool and
`effectiveCacheSize` sets the planner's estimate of PostgreSQL plus OS cache.
The core cluster requests 2 CPU and 4GiB memory and is limited to 6 CPU and
16GiB memory. Recalculate the connection budget whenever
the embedded replica count, `numInitChildren`, `maxPool` or
`psql.tuning.maxConnections` changes.

PGPool mounts bounded, memory-backed `emptyDir` volumes at `/tmp`, `/dev/shm`,
and `/var/run/postgresql`; their size limits live with the workload definition
in `templates/PGPool/PGPoolDeployment.yaml`. `/dev/shm` supports the pre-forked PGPool processes and
shared caches, while the runtime volume holds the PostgreSQL and PCP sockets.
An init container removes stale socket files before Pgpool startup because
these memory-backed volumes survive a container restart; this keeps the
loopback PCP listener available to the auto-recovery sidecar without exposing
PCP as a Service port. See the upstream
[Pgpool-II connection settings](https://www.pgpool.net/docs/latest/en/html/runtime-config-connection.html)
for the PCP listener and socket behavior.
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

The `pgadmin-ingress` route is protected by the chart-owned
[`SecurityPolicy`](templates/PGAdmin/PGAdminSecurityPolicy.yaml), which sends
requests through the shared Authentik forward-auth service before they reach
pgAdmin. LDAP remains pgAdmin's application-level identity source after the
gateway check; the gateway policy is the external access boundary.

The chart's Authentik Terraform
[`Workspace`](templates/PGAdmin/PGAdminAuth.yaml) creates the matching
forward-single proxy provider and application and attaches it to the existing
`myloginspace-proxy` outpost.
The configuration follows Authentik's [forward-auth provider
model](https://docs.goauthentik.io/add-secure-apps/providers/proxy/create-proxy-provider/)
and the Terraform provider's [`authentik_provider_proxy`
resource](https://registry.terraform.io/providers/goauthentik/authentik/latest/docs/resources/provider_proxy).

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

### Home1/YVR node scheduling

The Home1/YVR entry in the [PSQL ApplicationSet](../../Apps/Storage/PSQL.yaml)
adds the `load=testing:NoSchedule` toleration to both the site-local and shared
PostgreSQL resources. This allows their pods to run on HPC2 while retaining the
default empty toleration list for other clusters. The control-plane taint is
removed by the cluster composition, so this setting is intentionally limited to
the load-pool taint.

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
