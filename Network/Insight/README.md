# OpenNMS Insight

This Helm rendering unit deploys a basic, single-replica OpenNMS Horizon
instance. The owning `Apps/Network/Insight.yaml` ApplicationSet selects only
the `core-home1-talos-prod` bare-metal infrastructure cluster and deploys into
`core-net-prod`. That namespace enforces the privileged Pod Security profile
required for OpenNMS's narrowly scoped `NET_RAW` capability. Lovely injects the
target's region, datacenter, cluster domain,
site-local PostgreSQL hostname, local provider names, and administrative Secret
name. The deployment uses the writable `psql-home1-yvr` cluster owned by
`Apps/Storage/PSQL.yaml`, not the fleet-wide `psql-main` replication topology or
PGPool endpoint.

The chart pins the
[BJW-S common library 5.0.1](https://github.com/bjw-s-labs/helm-charts/tree/common-5.0.1/charts/library/common)
to generate the StatefulSet, init containers, claim templates, Service,
HTTPRoute, ConfigMap, and NetworkPolicy from `templates/common.yaml`. The
OpenNMS-specific User claim, Authentik Workspace, SecurityPolicy, and
NodeFeatureRule remain direct templates because they are site or controller
CRDs outside the common library's typed resource model. Common 5 requires
Kubernetes 1.31 and Helm 3.18 according to its
[v5 release notes](https://github.com/bjw-s-labs/helm-charts/releases/tag/common-5.0.0).
The target was observed at Kubernetes 1.36.3, and the pinned
[`lovely-vault-plugin` 1.2.5 renderer](https://github.com/crumbhole/lovely)
contains Helm 3.21.2; verify both again before changing either dependency.

## Runtime and persistence

The StatefulSet runs the official
[`opennms/horizon` container](https://hub.docker.com/r/opennms/horizon) at
version `36.0.3`, pinned to the inspected multi-platform manifest digest. The
image is built from OpenNMS's component-specific
[`opennms-container` source](https://github.com/OpenNMS/opennms/tree/e05049c7ec4/opennms-container).
The configuration follows the upstream
[Horizon 36 container installation procedure](https://docs.opennms.com/horizon/latest/deployment/core/install.html#install-core-docker):
an init container runs the guarded `-i` database/configuration initialization,
then the main container runs `-s`. The image runs as UID/GID `10001` with the
runtime-default seccomp profile. The configuration-preparation container drops
all Linux capabilities. The database-initialization and OpenNMS runtime
containers drop all capabilities and add back only `NET_RAW`, which the pinned
image's capability-bearing Java executable requires for its native ICMP
pollers. Removing `NET_RAW` from the container bounding set causes Linux to
reject Java execution with `EPERM` before OpenNMS can run its configuration
tester. The chart does not expose Karaf, trap, or syslog listeners publicly.

Two ReadWriteOnce claims retain `/opt/opennms/etc` and `/opennms-data`. The
configuration claim also caches the pinned time-series plugin after its first
verified download. The data claim remains mounted for the image's reports and
MIB directories and is retained for rollback and any historical RRD files, but
the production ApplicationSet selects the integration strategy, so new
performance and latency samples are not written there. Back up both claims and
the PostgreSQL database before changing or rolling back the storage strategy.

Filesystem-backed claims can expose a `lost+found` directory at the volume
root. The pinned
[Horizon 36.0.3 entrypoint](https://github.com/OpenNMS/opennms/blob/e05049c7ec4/opennms-container/core/container-fs/entrypoint.sh)
considers any such entry to be existing configuration and therefore does not
copy `share/etc-pristine`. Before the upstream `-i` initialization, the
`prepare-configuration` init container checks for the required
`opennms.properties` file, adds missing pristine configuration when it is
absent, and ensures `opennms.properties.d` and the optional `featuresBoot.d`
directory exist for mounted configuration.
This operation does not delete or overwrite existing files, so it repairs the
partially initialized claim while preserving deliberate configuration. After
reconciliation, verify all init containers complete and inspect the
`initialize` log for successful confd, config-tester, and schema initialization.

## Namespace and storage migration

The ApplicationSet moves the workload from `core-prod` to `core-net-prod`
because the former namespace rejects `NET_RAW`. This creates a new StatefulSet
and new `config` and `data` PVCs in `core-net-prod`; Kubernetes PVCs cannot move
between namespaces. The original claims remain in `core-prod` after its
StatefulSet is pruned. Do not delete them until any required configuration and
RRD history has been copied to the new claims and the monitoring workflow has
been validated. `migration.replaceStatefulSet` is `false` because the target
namespace receives a new StatefulSet and has no immutable selector to replace.

This is a clean deployment rather than a state-preserving migration. The new
`User` claim creates the distinct `opennms-insight` PostgreSQL role and database
in `core-net-prod`; the failed `core-prod` claim and its orphaned external
objects are not reused. A BJW-S raw resource creates an External Secrets
Operator
[`PushSecret`](https://external-secrets.io/v1.0.0/api/pushsecret/) in
`core-prod` and an `ExternalSecret` in `core-net-prod` to reproduce only the
PostgreSQL administrator credential through `mainvault-core`. The remote record
uses the ApplicationSet-injected
`Network/Insight/core-home1-talos-prod/PostgreSQLAdmin` key, contains no literal
credential in Git, and is retained if the PushSecret is removed. Verify the
PushSecret is synced and the target admin Secret exists before expecting the
new init container to start.

## Identity and PostgreSQL

The namespaced `User.mylogin.space/v1alpha1` claim in `core-net-prod` creates
the `opennms-insight` service identity, role, and database through the
`psql-home1-yvr` SQL and
Terraform ProviderConfigs. Both providers target the Home1 site-local cluster
through
[`provider-sql` 0.14.0](https://github.com/crossplane-contrib/provider-sql/tree/v0.14.0)
and the
[`provider-terraform` Workspace API](https://github.com/crossplane-contrib/provider-terraform).
Its stable local `opennms-creds` Secret supplies `OPENNMS_DBUSER` and
`OPENNMS_DBPASS`; no application database password is stored in Git. The
application connects to
`psql-local.core-home1-talos-prod.home1.yvr.mylogin.space` rather than PGPool or
a chart-private database.

Horizon schema installation and upgrades require a PostgreSQL superuser, as
documented by the upstream installation guide. The init container therefore
reads a synchronized copy of the local-cluster Zalando operator credential
Secret named by `postgresql.adminSecretName`. The owning ApplicationSet selects the
`opsadmin.psql-home1-yvr.credentials.postgresql.acid.zalan.do` Secret so schema
initialization targets the same database as the site-local providers; it does
not create another administrative identity. Confirm the PostgreSQL instance
permits at least the
[70 connections required by the default Horizon pools](https://docs.opennms.com/horizon/latest/deployment/core/install.html#setup-postgresql-pool-size).

The current `sso-user` Composition orphans PostgreSQL roles, databases, and
grants on deletion. Removing the claim or Argo CD Application is not proof that
database state or credentials were removed.

## Time-series storage

Production uses the official OpenNMS
[Prometheus RemoteWrite plugin](https://github.com/OpenNMS-Plugins/opennms-prometheus-remotewrite-plugin/tree/v2.1.0)
2.1.0, following Horizon's
[plugin deployment guidance](https://docs.opennms.com/horizon/36/deployment/time-series-storage/timeseries/prometheus-remotewrite.html),
and Horizon's
[time-series integration strategy](https://docs.opennms.com/horizon/36/deployment/time-series-storage/timeseries/configuration.html)
instead of local RRD storage. The plugin artifact comes from its immutable
[Maven Central 2.1.0 directory](https://repo1.maven.org/maven2/org/opennms/plugins/timeseries/org.opennms.plugins.timeseries.prometheus.remotewrite.assembly.kar/2.1.0/)
and must match the SHA-256 stored in `values.yaml`. The
`install-timeseries-plugin` init container downloads it only when the cached
copy on the configuration claim is absent or has the wrong digest. A first
installation therefore requires egress to `repo1.maven.org`; later starts use
the verified cache. The runtime mounts the KAR into `deploy`, enables
`opennms-plugins-prometheus-remotewrite`, and sets
`org.opennms.timeseries.strategy=integration`.

Writes go to the cluster-local central Alloy Service at
`core-home1-talos-prod-collectors-alloy.core-prod` on port `9090`. Alloy's
[`prometheus.receive_http`](https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.receive_http/)
receiver forwards samples through the existing Mimir remote-write component,
which adds `cluster=core-home1-talos-prod` and the site `dc` label. OpenNMS
reads its graphs through the internal `core-mimir` Cilium global Service and
Mimir's
[remote-read API](https://grafana.com/docs/mimir/latest/references/http-api/#remote-read).
Reads deliberately bypass `core-mimir-proxy` because
its `prom-label-proxy` handles PromQL and label APIs, not the protobuf
remote-read protocol. Both paths remain private ClusterIP/global-Service
traffic and use no credential stored in this chart; Mimir currently has
multitenancy disabled and maps traffic to its configured `core` tenant.

This is a cutover, not a migration. Existing RRD samples remain on the retained
data PVC and are not copied into Mimir or visible through integration-backed
graphs. The current
[`core-observability-metrics` owner](../../Apps/Observability/Metrics.yaml)
retains only 12 hours at YXL, and Home1 depends on Cilium ClusterMesh to reach
that backend. Confirm the required history and capacity before increasing
collection scope. To roll back, restore the RRD strategy through Git and keep
the data PVC; samples collected only in Mimir during the integration interval
will not be backfilled into RRD. OpenNMS keeps its integration buffer in memory
by default; the data PVC is not a fallback if Alloy or Mimir is unavailable, so
an extended write-path outage can create a permanent collection gap.

## Dragonfly compatibility

The site-local `dragonfly-core` service is deliberately not connected to this
basic deployment. Horizon's upstream
[`opennms.properties` reference](https://github.com/OpenNMS/opennms/blob/e05049c7ec4/opennms-base-assembly/src/main/filtered/etc/opennms.properties)
offers Redis only as the external metadata cache for the Newts time-series
strategy. This chart instead uses the Prometheus RemoteWrite integration and
deploys no Cassandra. Supplying unused Redis environment variables would not
make Horizon consume Dragonfly. Consequently this chart reserves no logical
database in the
[`dragonfly-core` allocation registry](../../Storage/Dragonfly/CoRE/README.md).
Introduce Newts/Cassandra as a separately reviewed architecture change before
allocating and configuring a Dragonfly database.

## Access and first login

The public route is `https://insight.mylogin.space/opennms`. It uses the same
fail-closed Envoy Gateway external authorization pattern as the Media stacks:
a Crossplane Terraform Workspace creates an Authentik `forward_single` proxy,
an application under `Infrastructure`, the `insight-access` entitlement, and
bindings for `Server Admins`. An Authentik
[proxy-provider property mapping](https://docs.goauthentik.io/add-secure-apps/providers/proxy/custom_headers/)
adds `X-OpenNMS-Roles`; the SecurityPolicy sends cookies to the shared
`aaa-myloginspace-proxy` service and forwards only Authentik's verified username
and that OpenNMS-specific role header. See Authentik's
[proxy-provider documentation](https://docs.goauthentik.io/add-secure-apps/providers/proxy/)
and Envoy Gateway's
[external authorization documentation](https://gateway.envoyproxy.io/v1.8/tasks/security/ext-auth/).

A read-only `public-url.properties` file sets
`opennms.web.base-url=https://insight.mylogin.space/opennms/` in both the
database-initialization and runtime containers. Horizon uses this public HTTPS
URL for its HTML base element, so browser assets, navigation, and redirects do
not resolve to the internal HTTP Service address. The value is rendered from
`gateway.hostname`; keep that value aligned with the HTTPRoute hostname. This
follows Horizon's
[system-property override guidance](https://docs.opennms.com/horizon/36/operation/deep-dive/admin/configuration/system-properties.html)
and the pinned Horizon 36.0.3
[`opennms.web.base-url` reverse-proxy setting](https://github.com/OpenNMS/opennms/blob/e05049c7ec4/opennms-base-assembly/src/main/filtered/etc/opennms.properties).

The chart enables Horizon 36's documented
[HTTP-header pre-authentication](https://docs.opennms.com/horizon/36/operation/deep-dive/user-management/pre-authentication.html)
and granted-authorities user-details service. The Authentik username therefore
becomes the named Horizon principal without a duplicate local password. Members
admitted by the `Server Admins` binding receive `ROLE_USER`, `ROLE_ADMIN`,
`ROLE_REST`, and `ROLE_PROVISION`; adjust that fixed mapping only as a coordinated
Authentik/OpenNMS authorization change.

Username/password login through the Horizon form is also enabled using
Horizon 36's documented
[external LDAP authentication](https://docs.opennms.com/horizon/36/operation/deep-dive/admin/configuration/external-auth.html)
and the pinned
[`ldap.xml.disabled` example](https://github.com/OpenNMS/opennms/blob/e05049c7ec4/opennms-webapp/src/main/webapp/WEB-INF/spring-security.d/ldap.xml.disabled).
The existing `opennms-creds` connection Secret is the only credential source:
the runtime reads its `ldapsURI`, `ldapsBIND`, and `password` keys to bind and
search Authentik's LDAP outpost, then authenticates the submitted user by bind.
The bind password remains a Secret-backed environment value and is not rendered
into the ConfigMap. User searches use `cn` below
`ou=users,dc=ldap,dc=mylogin,dc=space`, and group membership searches use
`member` below `ou=groups,dc=ldap,dc=mylogin,dc=space`. Authentik's
[LDAP provider documentation](https://docs.goauthentik.io/add-secure-apps/providers/ldap/)
describes bind and directory-search behavior. The `User` claim's existing
`LDAPService` group membership must continue to grant this service account the
`Search full LDAP directory` permission; a successful bind without that search
permission is insufficient for user and group resolution.

LDAP and proxy authorization intentionally share `authentik.accessGroups` and
`authentik.proxyAuth.authorities`. A directory user receives access only when a
searched group is one of those configured access groups; the current `Server
Admins` mapping grants the same `ROLE_USER`, `ROLE_ADMIN`, `ROLE_REST`, and
`ROLE_PROVISION` roles as header pre-authentication. Built-in OpenNMS login
remains available for the independent break-glass account. Treat changes to the
LDAP search bases, filters, access groups, or roles as coordinated directory,
Authentik entitlement, and OpenNMS authorization changes.

OpenNMS header authentication is safe only behind a trusted proxy. The
NetworkPolicy permits port `8980` solely from the Envoy pods owned by
`core-prod/main-gw`, and the SecurityPolicy forwards exact header names rather
than the complete `x-authentik-*` set. Keep both controls aligned with any
Gateway rename or relocation. `failOnError` remains false so the built-in login
continues to work without Authentik for emergency recovery from inside the pod;
it is not exposed as a second public route. Immediately replace the upstream
`admin` password with a generated credential stored outside Git, and verify the
break-glass procedure independently of Authentik, DNS, and the Gateway.

## Reconciliation, verification, and removal

Before sync, the target cluster must have the `User`, Terraform `Workspace`,
Gateway API `HTTPRoute`, Envoy Gateway `SecurityPolicy`, PushSecret, and
ExternalSecret CRDs; the
`psql-home1-yvr` PostgreSQL service, matching SQL and Terraform ProviderConfigs,
and local admin Secret; the `authentik` ProviderConfig
and named flows; the `Server Admins` group; the public Gateway; and the shared
Authentik proxy service. The Collectors and Metrics ApplicationSets are created
in wave 20 before Insight's wave 30, but that ordering does not prove their
downstream services are healthy. Confirm the Home1 central Alloy Service has
its port-`9090` receiver and the `core-mimir` global Service has healthy YXL
query and write backends before Insight starts collecting.

After reconciliation, verify the User claim and composite, generated Role and
Database, grants, the admin PushSecret and ExternalSecret, `opennms-creds`, and
the synchronized admin credential before checking the init container.
Verify the plugin init container reports either a valid cache hit or a
successful checksum, the Karaf feature and time-series integration health check
are active, and OpenNMS logs contain no TSS write/read failures. Verify Alloy's
`prometheus.receive_http` request and forwarded-sample metrics, Mimir accepted
samples carrying the expected `cluster` and `dc` labels, and a graph read back
through OpenNMS after one collection cycle. Confirm that no new RRD files are
created after the cutover. Then verify the StatefulSet is Ready, both PVCs are
mounted, the HTTPRoute is Accepted, the SecurityPolicy is attached, and the
Authentik Workspace and
downstream provider, property mappings, application, and bindings are healthy.
Confirm the rendered NetworkPolicy selectors match the actual Envoy data-plane
pods before sync. Test denial for an unauthenticated user and a non-member,
automatic named Horizon login and effective roles for a `Server Admins` member,
form login with a directory username/password for a `Server Admins` member,
rejection of a valid directory user outside the configured access group,
rejection of spoofed headers through any non-Gateway path, break-glass local
login, node provisioning, the configured ICMP and SNMP polling mechanisms,
alarm generation, Mimir-backed graphing, and restart persistence. Pod readiness
alone does not validate the monitoring workflow.

Rollback through Git and Argo CD. The ApplicationSet preserves resources on
deletion, PVCs retain local configuration and RRD data, the User composition
orphans external database objects, and Terraform resources may have finalizers.
Take a coordinated backup and explicitly verify every retained or destroyed
resource before deleting PVCs, claims, Workspaces, or finalizers. The namespace
move creates new PVCs and the distinct `opennms-insight` database identity. It
does not copy configuration or RRD data from the preserved `core-prod` claims
or adopt the orphaned `opennms` database objects. Validate the complete new
monitoring workflow before explicitly retiring those stale resources.
Disabling `timeseries.enabled` removes the runtime plugin configuration and
returns new samples to Horizon's default RRD strategy after restart; the cached
KAR remains inert on the retained configuration PVC. The shared Alloy receiver
remains available to other internal producers and is removed only by reverting
the Collectors change.
