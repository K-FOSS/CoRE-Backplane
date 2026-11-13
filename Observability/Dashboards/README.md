# Grafana dashboards

This Lovely rendering unit deploys Grafana and the identity and secret resources
that make the same service available from both CoRE infrastructure clusters. It
is live, site-specific desired state; it is not a reusable example chart.

## Ownership and targets

The [`core-observability-dashboards` ApplicationSet](../../Apps/Observability/Dashboards.yaml)
owns this directory. Its merge generator selects clusters labelled with all of
the following:

- `mylogin.space/tenant: core.mylogin.space`
- `resolvemy.host/computetype: baremetal`
- `resolvemy.host/nodetype: infra`

The list generator currently limits the result to these applications:

| Cluster | Application | Namespace | `hub` | Grafana replicas | ApplicationSet mode |
| --- | --- | --- | --- | --- | --- |
| `core-home1-talos-prod` | `core-home1-talos-prod-dashboards` | `core-prod` | `true` | `2` | `SingleBinary` |
| `core-dc1-talos-prod` | `core-dc1-talos-prod-dashboards` | `core-prod` | `false` | `2` | `Distributed` |

`mode` is part of the generator data but is not consumed by this chart. The
ApplicationSet also derives the cluster domain, region, zone, and datacenter
from cluster Secret labels. Lovely merges the generated `hub` value, the
cluster identity context, and two cluster-specific Grafana settings into
[`values.yaml`](values.yaml). The chart consumes the injected cluster
`datacenter` to configure the LDAP endpoint as
`ldap-<datacenter>.mylogin.space`; `name`, `domain`, and `region` are retained
in the chart context for cluster-local addressing and site-specific
configuration.

- `grafanaReplicas` controls the replica count independently for each listed
  cluster.
- The Grafana Service advertises `kubernetes.io/ws` on its HTTP port. This
  enables the Gateway API backend protocol selection needed for Grafana Live
  WebSocket upgrades through Envoy Gateway. The public route remains an
  `HTTPRoute`; WebSockets begin as HTTP/1.1 Upgrade requests on that route. See
  the [Gateway API backend protocol guide](https://gateway-api.sigs.k8s.io/guides/user-guides/backend-protocol/)
  and [Envoy Gateway HTTPRoute backend-protocol documentation](https://gateway.envoyproxy.io/latest/api/gateway_api/httproute/).
- Grafana Live and Grafana's remote cache use the site's shared `dragonfly-core`
  Redis-compatible service. The remote cache uses TLS.
- Grafana reads the Dragonfly password from the existing
  `dragonfly-core-password` Secret. The chart keeps Grafana's `$__env`
  expansion expressions outside the ApplicationSet plugin environment so Argo
  CD does not interpolate them during manifest generation. The ApplicationSet
  injects only the cluster-specific `DRAGONFLY_ADDRESS`, and Reloader restarts
  the Deployment when the password Secret changes. The ApplicationSet adds the
  Reloader annotation with a post-render Kustomize patch targeted only at
  `Deployment/grafana-core`; the annotation is not copied to pods, ConfigMaps,
  RBAC, or other resources.
- Grafana exports OpenTelemetry traces to the cluster-local Alloy service over
  OTLP/gRPC with W3C propagation and 10 percent probabilistic sampling. The
  settings follow Grafana's
  [OpenTelemetry tracing configuration](https://grafana.com/docs/grafana/latest/setup-grafana/configure-grafana/#tracingopentelemetryotlp),
  and Alloy forwards sampled spans to Tempo.
- LDAP mounts the existing `grafana-core-ldap` Secret. Its
  `servers.group_mappings` entries are configured through
  `grafana.ldap.groupMappings` in [`values.yaml`](values.yaml), so a target
  can add or remove Grafana role mappings through the ApplicationSet merge
  without editing the ExternalSecret template. Each entry supplies a quoted
  LDAP `groupDn`, Grafana `orgRole`, and boolean `grafanaAdmin` flag.

Argo CD creates the namespace, uses the Lovely config-management plugin, and
preserves resources when an Application is deleted. Automated sync, prune, and
self-heal are not configured here.

## Rendered components

The chart pins the maintained
[Grafana Community Helm chart 13.5.0](https://github.com/grafana-community/helm-charts/tree/grafana-13.5.0/charts/grafana)
and the [BJW-S common chart 5.0.1](https://github.com/bjw-s-labs/helm-charts/tree/common-5.0.1/charts/library/common),
which deploys Grafana `13.2.3`.
The release renders one Grafana replica named `grafana-core`, a local ClusterIP
Service, a dedicated dashboard-sync Deployment and RBAC, a central dashboard
API Service, and an HTTPRoute for
`grafana.int.mylogin.space` attached to `core-prod/main-gw`. The site route is
private and the chart additionally renders a `grafana.gslb.mylogin.space`
HTTPRoute plus a K8GB `Gslb` advertising `grafana.int.mylogin.space`; K8GB owns
the global DNS decision while each site route sends traffic to its local
Grafana Service. See the [K8GB resource reference](https://www.k8gb.io/latest/resource_ref/)
and [K8GB dynamic zones](https://www.k8gb.io/latest/dynamic_zones/). The upstream chart
provides the [Grafana configuration values](https://github.com/grafana-community/helm-charts/blob/grafana-13.5.0/charts/grafana/values.yaml)
and container defaults; local values deliberately override its authentication,
database, routing, plugin, and dashboard-discovery behavior.

Grafana 13 enables unified storage and the chart mounts a disposable
`emptyDir` at `/var/lib/grafana-search` for each replica's local search index.
The PostgreSQL database remains the authoritative application store; do not
treat the per-pod search volume as backup or recovery data. The upgrade
preserves the names of the Deployment, Service, ServiceAccount, ConfigMap,
HTTPRoute, ClusterRole, and ClusterRoleBinding. The newer chart no longer
renders the previous empty namespaced Role and RoleBinding or Helm test hooks.

Dashboard discovery uses the chart's
[k8s-sidecar integration](https://github.com/grafana-community/helm-charts/tree/grafana-13.5.0/charts/grafana#sidecar-for-dashboards),
which is separated from the Grafana Deployment. The syncer workload and
namespace-scoped RBAC are generated by the pinned BJW-S common chart. A dedicated
`kiwigrid/k8s-sidecar` Deployment watches ConfigMaps labelled
with the `grafana_dashboard` key, then imports their JSON through the
authenticated Grafana API. Repository-managed dashboards use the value `'true'`;
the syncer does not filter on the value so chart-managed dashboards using `'1'`
are also accepted. The syncer watches only the explicitly configured
`core-prod`, `k8gb`, `kube-system`, and `longhorn-system` namespaces through separate
namespace-scoped Roles and RoleBindings. Folder discovery uses Grafana's
[current folder API](https://grafana.com/docs/grafana/latest/developer-resources/api-reference/http-api/folder/)
and creates a deterministic cluster folder with dashboard-type subfolders, for
example `core-dc1-talos-prod/Mimir`. The central Home1 syncer retains the
upstream dashboard UIDs; non-central cluster syncers receive stable
cluster-prefixed UIDs so copies do not overwrite or move the central copy.
Internal dashboard links are rewritten to the local UID and include the owning
cluster folder UID, keeping navigation within the same cluster folder even
when a dashboard is stored in a dashboard-type subfolder.
Folder creation is keyed by the deterministic parent-aware UID, and the syncer
removes only empty, root-level legacy folders after verifying that no dashboard
or child folder remains in them. Before importing, the syncer compares the
desired dashboard with Grafana's existing dashboard by UID and skips an
unchanged dashboard, preventing refresh events from generating needless
overwrite alerts. Prometheus dashboards imported from upstream are normalized
to the repository's `datasource` variable convention, so datasource inputs such
as `${DS_PROMETHEUS}` do not remain unresolved in the saved dashboard. A
Prometheus dashboard imported by a syncer also receives visible `Cluster`, `Dc`,
and `Region` selectors initialized to that syncer's source cluster. The syncer
adds those matchers to unscoped PromQL selectors before writing the dashboard to
Grafana, which prevents identically named resources such as PVCs from being
joined across the two source clusters. If a query already contains a `cluster`
label matcher, the syncer preserves it unchanged; this is required for
intentionally multi-cluster dashboards and aggregation rules such as Kubernetes
multi-cluster and CPU panels. The selectors remain part of the dashboard so an
operator can see the scope applied to its queries. A separate
`grafana-dashboard-api` Service is the only Cilium
Global Service: its selector points at the YVR/Home1 Grafana pods, and
EndpointSlice synchronization makes that central API reachable from DC1.
Normal Grafana UI and data traffic remains cluster-local. See the
[syncer common-chart definition](templates/common.yaml), while the values file
keeps only the enablement, central cluster selector, and pinned image settings;
[k8s-sidecar script and request configuration](https://github.com/kiwigrid/k8s-sidecar#configuration-environment-variables)
and [Cilium Global Services](https://docs.cilium.io/en/stable/network/clustermesh/global-services/).

The `grafana-dashboard-node-exporter-full` ConfigMap imports [Grafana dashboard
1860, Node Exporter Full](https://grafana.com/grafana/dashboards/1860-node-exporter-full/)
from the pinned [revision 45 download URL](https://grafana.com/api/dashboards/1860/revisions/45/download)
into the `Infrastructure` folder. The syncer supports `.url` entries alongside
repository-managed `.json` dashboards; the URL is fetched when the labeled
ConfigMap is observed. The dashboard expects Prometheus node-exporter metrics
and provides `job`, `nodename`, and `instance` selectors. The dedicated
privileged Alloy host DaemonSet emits those standard labels; the exporter
ApplicationSet also forces the pinned upstream Kubernetes dashboard ConfigMaps
to render so the standalone syncer receives dashboard updates even though no
Prometheus or kube-prometheus-stack Grafana pod is deployed.
The syncer also applies a local overlay to this dashboard: panels use a
15-second minimum query interval and the dashboard offers a 15-second refresh
interval. This affects query and refresh resolution only; the WAN-GW2 scrape
currently runs every 30 seconds, so intervals shorter than that cannot recover
samples that were not collected.

Cilium dashboards are provided by the Cilium Helm release in the
[Network/Base stack](../../Network/Base/README.md), which enables the chart's
dashboard ConfigMaps in `kube-system`. This stack only watches and imports
those ConfigMaps; it does not create a duplicate Cilium dashboard definition.

The hub Authentik Workspace creates the `Grafana Dashboard Sync` group once.
Each dashboard Application then creates its own `mylogin.space` `User` with a
cluster-specific name in that group. Its generated connection Secret is used
only to bootstrap that Application's Grafana Terraform provider. The local
Crossplane Workspace then creates a cluster-specific `dashboard-sync` Grafana
service account and token and writes the sensitive token to the local
`grafana-dashboard-sync-auth` Secret. The bootstrap group maps to the Grafana
organization `Admin` role because Grafana requires organization Admin rights or
the appropriate fixed service-account creator roles to create a service account;
the generated dashboard token remains limited to the `Editor` role. No admin
password or token value belongs in Git. The provider uses the official
[Grafana Terraform provider service-account resources](https://registry.terraform.io/providers/grafana/grafana/latest/docs/resources/service_account_token)
and Grafana documents the [service-account creation permissions](https://grafana.com/docs/grafana/latest/administration/service-accounts/)
and intended authentication mechanism for automated API clients; see the
[Grafana HTTP API authentication documentation](https://grafana.com/docs/grafana/latest/developer-resources/api-reference/http-api/authentication/).

The chart provisions the `PostgreSQL / Database Capacity and Connections`
dashboard from [`templates/PostgreSQL.yaml`](templates/PostgreSQL.yaml). It
uses the PostgreSQL exporter's `pg_database_size_bytes` and
`pg_stat_database_numbackends` metrics for per-database size and connection
tables, plus a connection time series. PostgreSQL scrape targets use the
canonical `instance` label `<cluster>/<psql-cluster>/<pod-name>`, matching the PSQL chart's
ServiceMonitor relabeling.

The chart also provisions the `Loki / Container Logging Volume` dashboard from
[`templates/LokiLogging.yaml`](templates/LokiLogging.yaml). It uses the
existing Alloy pod-log instrumentation: the collector preserves `cluster`,
`dc`, `namespace`, `pod`, and `container` labels before forwarding logs to
Loki. Loki LogQL `bytes_over_time` and `count_over_time` queries show total
volume, bytes per second, lines per second, and the top containers by bytes or
lines. The dashboard's time range and variables can be narrowed to isolate a
noisy namespace, pod, or container. It intentionally measures the stored log
stream rather than adding a second metric pipeline.

The chart imports Grafana Labs' pinned [Mimir / Overview dashboard](https://grafana.com/grafana/dashboards/17607-mimir-overview/)
and [Mimir / Writes dashboard](https://grafana.com/grafana/dashboards/16026-mimir-writes/)
from [`templates/Mimir.yaml`](templates/Mimir.yaml). Overview provides cluster
health and component status; Writes covers the ingestion path through the
gateway, distributor, and ingester. The dashboard URLs are pinned to immutable
Grafana dashboard revisions and are fetched by the existing syncer into the
`Mimir` folder. These dashboards follow Grafana Mimir's
[production monitoring dashboard guidance](https://grafana.com/docs/mimir/latest/manage/monitor-grafana-mimir/dashboards/)
and require the Mimir metrics, recording rules, and labels described in the
[dashboard requirements](https://grafana.com/docs/mimir/latest/manage/monitor-grafana-mimir/requirements/).

The Garage operator remains the canonical source for the Garage S3 dashboard in
DC1. Its labelled ConfigMap is imported by the DC1 syncer into the central YVR
Grafana database and is consequently available through either Grafana URI.

The local templates additionally render:

- an [ExternalSecret](https://external-secrets.io/latest/api/externalsecret/)
  named `grafana-core-ldap` on every target;
- an [Envoy Gateway SecurityPolicy](https://gateway.envoyproxy.io/docs/api/extension_types/#securitypolicy)
  that performs Authentik OIDC and JWT validation for the `grafana-core`
  HTTPRoute. Its OIDC provider and JWT remote-JWKS fetch both use the
  `grafana-authentik-idp` Envoy Gateway `Backend` for the Authentik HTTPS FQDN,
  with system CA validation, explicit authorization/token endpoints, and
  bounded retries for transient 5xx, gateway, and connection-reset failures;
- hub-only Crossplane `User` and
  [Terraform Workspace](https://marketplace.upbound.io/providers/upbound/provider-terraform/latest/resources/tf.upbound.io/Workspace/v1beta1)
  resources, plus [PushSecrets](https://external-secrets.io/latest/api/pushsecret/)
  that publish generated database and OIDC material to CoreVault; or
- spoke-only ExternalSecrets that retrieve the database and OIDC material from
  CoreVault.

The Home1 ApplicationSet entry injects `hub: true`, so it renders the
hub-owned Grafana User, Authentik Workspace, and group. Every dashboard
Application renders its own bootstrap User, Grafana ProviderConfig, and
Grafana Workspace; only the main Grafana database credentials and Authentik
OIDC material use the hub PushSecret/spoke ExternalSecret flow. Do not assume
the default in
`values.yaml` describes the current Argo CD deployment.

## Identity, secrets, and data flow

Grafana reads its administrator username, password, and PostgreSQL URL from
`core-grafana-creds`. It reads its OIDC client ID and client secret from
`grafana-core-authentik`. The chart exposes the `password` key from
`dragonfly-core-password` as `DRAGONFLY_PASSWORD`; the ApplicationSet supplies
the non-secret, cluster-specific Dragonfly endpoint as `DRAGONFLY_ADDRESS`.
Grafana expands both environment variables in its Live and remote-cache
configuration. Secret values are created or synchronized by controllers and
are never stored in Git.

Requests first pass through the HTTPRoute and SecurityPolicy. Envoy Gateway
uses Authentik for OIDC, validates JWTs, and forwards selected identity claims
as headers. Grafana has [auth proxy](https://grafana.com/docs/grafana/latest/setup-grafana/configure-security/configure-authentication/auth-proxy/)
configured for those headers. Grafana's generic OAuth block exists but is
disabled; LDAP remains enabled and reads `ldap-toml` from the ExternalSecret.
See Grafana's [LDAP documentation](https://grafana.com/docs/grafana/latest/setup-grafana/configure-security/configure-authentication/ldap/)
before changing mappings or bind behavior.

The access path spans Authentik scopes and groups, Envoy claim forwarding,
Grafana role mapping, and LDAP group mappings. Review those layers together.
The default LDAP values grant Grafana server-admin to members of `authentik
Admins` and `Grafana Admins`, while the disabled generic OAuth mapping refers to
`Network Admins` and `Grafana Editors`. Treat changes to
`grafana.ldap.groupMappings` as access-control changes and verify the rendered
ExternalSecret without exposing its secret values.

Grafana stores application state in the external PostgreSQL database; local PVC
persistence is disabled. Its managed `User` claim explicitly publishes a
`postgres://` connection URI because Grafana does not recognize the
composition's generic `postgresql://` default as a database type. Grafana Live
uses Dragonfly as its Redis-compatible
HA messaging/pub-sub engine on logical database `0`, allowing both Grafana
replicas to exchange Live connection state. Grafana's
[remote cache](https://grafana.com/docs/grafana/latest/setup-grafana/configure-grafana/#remote_cache)
uses the same ApplicationSet-injected Dragonfly address and is isolated in
logical database `132`. The cache stores temporary
authentication-related data, not Grafana sessions or authoritative application
state. Grafana Live remains on the default Redis database because its Redis
client does not expose a database selector. Refer to Grafana's [database configuration](https://grafana.com/docs/grafana/latest/setup-grafana/configure-grafana/#database)
and [Live HA setup](https://grafana.com/docs/grafana/latest/setup-grafana/set-up-grafana-live/#configure-grafana-live-ha-setup)
when changing either dependency. Grafana Live uses the TLS-enabled `rediss://`
address, and the remote-cache client is explicitly configured with `ssl=true`;
verify the Dragonfly listener behavior for both clients after reconciliation.
The PostgreSQL pool is bounded at 50 open and 10 idle connections, reusing
connections for up to 30 minutes. The shared `psql-int.mylogin.space` URI is
the PostgreSQL HA/PGPool endpoint, so Grafana writes remain on the active
primary while standby promotion and routing remain owned by PostgreSQL/PGPool;
Grafana does not have a separate read-replica pool. The Dragonfly address also
resolves to the operator-managed primary service. Dragonfly replicas provide
replication and failover, but Grafana Live and the remote cache must not connect
directly to read-only replicas. The remote-cache pool is bounded at 50
connections per Grafana pod.
The shared Dragonfly allocation is recorded in the
[Dragonfly logical database registry](../../Storage/Dragonfly/CoRE/README.md),
which reserves `132` for this remote cache and keeps Grafana Live on the
legacy shared `0` database.

## Prerequisites

Before reconciliation, the target cluster must provide:

- Argo CD with the Lovely plugin and access to this repository;
- Gateway API and Envoy Gateway CRDs, `core-prod/main-gw`, and the corresponding
  public DNS and TLS path;
- External Secrets Operator, `mainvault-core`, and access to `Grafana/User`,
  `Grafana/Database`, and `Grafana/OIDC` remote keys. Each dashboard
  Application's Crossplane Workspace creates its own Grafana service account
  and publishes its token to the local syncer Secret;
- the platform `User` composition and Terraform provider on the Home1 hub,
  which owns the `grafana-core` LDAP/PostgreSQL identity and publishes its
  username, password, database name, and PostgreSQL URI to Vault for the
  non-hub deployment;
- Authentik flows, the `Logs` scope mapping, the `tls` signing certificate, and
  the groups referenced by the access configuration;
- PostgreSQL and the cluster-scoped `dragonfly-core` service and
  `dragonfly-core-password` Secret in `core-prod`;
- Alloy at the ApplicationSet-generated in-cluster OTLP address.

The chart also installs `grafana-advisor-app` version `1.0.2` and
`grafana-llm-app` version `0.22.1` synchronously at pod startup through
`GF_PLUGINS_PREINSTALL_SYNC`. Their component documentation is the
[Grafana Advisor app repository](https://github.com/grafana/grafana-advisor-app)
and [Grafana LLM app repository](https://github.com/grafana/grafana-llm-app).
Plugin availability is therefore an external startup dependency.

## Validation and operations

Resolve the dependency and validate both the chart default and a representative
ApplicationSet merge:

```sh
helm dependency build .
helm lint .
helm template dashboards . \
  --namespace core-prod \
  --set hub=false \
  --set-string cluster.name='core-home1-talos-prod' \
  --set-string cluster.domain='home1.example-region.mylogin.space' \
  --set-string cluster.datacenter='home1' \
  --set-string cluster.region='example-region' \
  --set grafana.replicas=2 \
  --set-string 'grafana.env.DRAGONFLY_ADDRESS=dragonfly.core-home1-talos-prod.home1.example-region.mylogin.space:6379' \
  --set-string 'grafana.grafana\.ini.tracing\.opentelemetry\.otlp.address=core-home1-talos-prod-collectors-alloy.core-prod.svc.cluster.local:4317' \
  --set-string 'grafana.grafana\.ini.tracing\.opentelemetry\.otlp.propagation=w3c' \
  --set grafana.ldap.enabled=true \
  --set-string grafana.ldap.existingSecret='grafana-core-ldap'
```

The hostnames in that example are representative literals, not discovered live
values. Inspect the rendered HTTPRoute, SecurityPolicy, Secret references,
Workspace/ExternalSecret branch, RBAC, Deployment environment, and Grafana
ConfigMap before merging.

After Argo CD reconciliation, verify more than Application health:

1. Before the first Grafana 13 rollout, take and verify a PostgreSQL backup.
   Grafana 13 migrates dashboards and folders to unified storage, so rollback
   to Grafana 12 requires restoring the pre-upgrade database backup. See the
   [Grafana 13 upgrade guide](https://grafana.com/docs/grafana/latest/upgrade-guide/upgrade-v13.0/#unified-storage-for-folders-and-dashboards).
2. Confirm ExternalSecret conditions and the presence of the expected Secret
   keys, including `dragonfly-core-password/password`, without printing their
   values.
3. Confirm the Grafana Service port has `appProtocol: kubernetes.io/ws`, the
   HTTPRoute is accepted by `main-gw`, the SecurityPolicy is attached without
   errors, and a browser can open Grafana Live WebSocket connections.
4. Check the Grafana Deployment rollout, database migration logs, unified
   storage migration status, and `/api/health` endpoint.
5. Test OIDC and LDAP login with least-privileged and administrative accounts,
   including logout and refresh behavior.
6. Check `grafana-dashboard-sync` logs and confirm labelled dashboards appear
   through the central `grafana-dashboard-api` Service and Grafana API.
7. Rotate the Dragonfly credential through its owning workflow and verify
   Reloader rolls both Grafana replicas after the Secret changes.
8. Verify PostgreSQL connectivity, Dragonfly connectivity for both Live
   messaging on DB `0` and remote caching on DB `132`, and OTLP traces reaching
   Alloy and the downstream traces backend.

## Rollback and deletion

Rollback is a Git revert followed by Argo CD reconciliation. After Grafana 13
has migrated folders and dashboards to unified storage, a version rollback also
requires restoring the pre-upgrade PostgreSQL backup; Grafana 12 otherwise reads
stale legacy tables. Changes to resource names, secret targets, redirect URIs,
or identity mappings can cause replacement or lockout and require an explicit
migration plan.

`preserveResourcesOnDeletion: true` means deleting an Application does not
remove its managed resources. Conversely, removing a template from Git during
normal reconciliation may still prune it if pruning is enabled elsewhere.
Before deliberate teardown, identify the owning Application, controller
finalizers, Crossplane deletion policy, external Authentik objects, Vault data,
database state, and HTTPRoute. Do not delete shared remote secrets or the
PostgreSQL database as part of a routine Grafana rollback.
