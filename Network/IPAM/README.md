# IPAM and DCIM

This rendering unit deploys CoRE's site-specific DHCP, authoritative DNS, and
NetBox IPAM/DCIM integration. NetBox is intended to become the source of truth
for network and bare-metal inventory, but that automation is not complete; the
current gaps and desired state are tracked in [TODO](TODO.md).

## Ownership and targets

The [Network/IPAM ApplicationSet](../../Apps/Network/IPAM.yaml) owns this chart.
It selects registered Argo CD clusters labelled with tenant
`core.mylogin.space` and compute type `baremetal`, then merges only these named
targets:

- `core-dc1-talos-prod`
- `dc1-k3s-node1`
- `core-home1-talos-prod`

Argo CD renders `Network/IPAM` with the
[Lovely plugin](https://github.com/crumbhole/argocd-lovely-plugin). The
ApplicationSet injects the environment, cluster identity, topology, EFI boot
server, stable DHCP service identity, enabled Kea server types, NetBox enablement,
and per-cluster Dragonfly host. It still supplies a legacy `persistence.configs` override; the chart-owned
bjw-s template now supplies the same Secret volume authoritatively, so that
legacy input has no rendered effect and should be removed from the
ApplicationSet. It also injects the target cluster domain into
Kea's local PGPool Service name. DHCPv4 and DHCP-DDNS are enabled on all three
targets; DHCPv6 is disabled on both DC1 targets and enabled on Home1. DHCPv6
currently has no registered `subnet6` allocation, so it starts without serving
leases instead of deploying the former documentation-only prefixes.
Applications are deployed to `core-prod`; deleting an ApplicationSet-generated
Application preserves its resources because `preserveResourcesOnDeletion` is
enabled. The source revision is the mutable `HEAD` reference, so Git history
and the rendered Argo CD revision must be used together during an audit.

## Components and reconciliation flow

- [bjw-s common library 5.0.1](https://github.com/bjw-s-labs/helm-charts/tree/common-5.0.1/charts/library/common)
  renders the Kea and PowerDNS workload, Services, ConfigMaps, and volumes.
  The upgrade crosses the documented [3.x to 4.x](https://bjw-s-labs.github.io/helm-charts/docs/app-template/upgrades/3-to-4/)
  and [4.x to 5.x](https://bjw-s-labs.github.io/helm-charts/docs/app-template/upgrades/4-to-5/)
  migrations. Its controller selector changes from `app.kubernetes.io/component`
  to `app.kubernetes.io/controller`. The v5 controller therefore renders as the
  new `netbox-ipam-kea` Deployment and Argo CD prunes the old immutable
  `netbox-ipam` Deployment through normal reconciliation. The unchanged
  LoadBalancer Service selects only the v5 label. Future controller updates use
  `Recreate` to avoid overlapping DHCP servers. The v5 dedicated ServiceAccount
  is used without an automounted API token.
- [ISC Kea 3.2](https://kea.readthedocs.io/en/kea-3.2.0/) serves DHCP and
  renders PXE paths for [Tinkerbell](https://tinkerbell.org/docs/). DHCP
  configuration is assembled by this chart and synchronized through External
  Secrets. DHCPv4, DHCPv6, and DHCP-DDNS use pathless UNIX control-socket names,
  which Kea resolves beneath its required `/var/run/kea` runtime directory.
  The container entry script restricts that memory-backed directory to mode
  `0750` before starting Kea, as required by Kea's control-socket checks.
  The removed Kea Control Agent is not configured; local management uses each
  daemon's control socket. Hook libraries use the Debian amd64 multiarch path
  supplied by the site image; both DHCP daemons load `libdhcp_pgsql.so` to
  register the PostgreSQL lease backend. The optional Netconf agent is disabled
  because it is not included in that image. Both DHCPv4 and DHCPv6 store leases
  through the site-local `psql` ClusterIP Service, which selects the local
  PGPool replicas in `core-prod`; database credentials and the port remain
  sourced from the secret store. The memory-backed Kea runtime directory lasts
  for the lifetime of the pod, including individual container restarts. On
  every container start, the entry script removes stale Kea PID files and
  control sockets before invoking `keactrl`; this prevents an unclean daemon
  exit from blocking recovery without deleting unrelated runtime files. The
  chart-managed healthcheck overrides Kea 3.2's PID directory with the mounted
  runtime path and requires every daemon enabled in `keactrl.conf` to report
  `active`; it does not rely on the image's DHCPv4-only `/Healthcheck.sh`. The
  entry script validates every enabled Kea configuration before startup and
  stops the daemons cleanly when the container receives a termination signal.
- [PowerDNS Authoritative Server 5.1.5](https://doc.powerdns.com/authoritative/changelog/5.1.html)
  serves DNS from the external PostgreSQL backend using the
  [official PowerDNS container](https://github.com/PowerDNS/pdns/blob/master/Docker-README.md),
  pinned to its multi-architecture manifest digest. Kea sends DHCP DDNS only
  to this pod's loopback listener; RFC 2136 updates are accepted from loopback
  only, and PowerDNS does not forward updates or NOTIFY messages. Its HTTP API
  and webserver are disabled because this instance has no API consumer. The
  upgrade from 4.8.4
  follows the [PowerDNS upgrade notes](https://doc.powerdns.com/authoritative/upgrading.html):
  PostgreSQL must be 9.5 or newer for the 5.1 default TSIG replacement query,
  API record representations may be normalized differently, and updates to
  LUA records remain disabled because this deployment does not enable them.
  Each enabled sidecar uses a cluster-specific Authentik service account from
  a `User` claim and generated PostgreSQL credentials, rather than the shared
  `NS/Database` username and password. The ApplicationSet injects the global
  `psql-int.mylogin.space` hostname and the `psql-main`/`psql` provider configs;
  PowerDNS connects to that primary endpoint for writes. Kea lease tables
  continue to use the separate site-local `psql.<cluster>` PGPool endpoint.
  The claim grants read/write access to the PowerDNS tables
  `domains`, `records`, `comments`, `domainmetadata`, `cryptokeys`, `tsigkeys`,
  and `supermasters` in `DlzcnePHKR`; it does not create a database. The User
  Composition also grants database `CONNECT`, `CREATE`, and `TEMPORARY`, plus
  schema-wide sequence privileges. The claim's credentials are mounted through
  a namespace-local Secret; PowerDNS's PostgreSQL port remains site-managed in
  Vault. The sidecar runs as UID/GID 953,
  drops all capabilities, forbids privilege escalation, uses RuntimeDefault
  seccomp and a read-only root filesystem, and has bounded CPU, memory, and
  ephemeral-storage resources. Its memory-backed `/tmp` holds the control
  socket. The pod ingress policy allows only the configured DHCP service ports,
  leaving the PowerDNS listener private to Kea within the pod; see Kubernetes'
  [NetworkPolicy documentation](https://kubernetes.io/docs/concepts/services-networking/network-policies/).
  The policy restricts ingress only; egress remains shared with Kea in the pod
  and is governed by the cluster's existing policy.
  Removing the claim does not remove the PostgreSQL role and grants because
  the User Composition orphans these provider resources; handle database
  cleanup separately. The former ExternalSecret-managed `-ns` Secret is
  replaced by a port-only `-pdns-port` Secret and the claim-owned `-pdns-creds`
  Secret; both port and credential changes trigger the pod reloader.
- [NetBox chart 8.3.51](https://github.com/netbox-community/netbox-chart/tree/netbox-8.3.51/charts/netbox)
  deploys the NetBox web and worker components using the site image and enabled
  plugins. The running DC1 pod confirms NetBox Community
  `v4.7.5-Docker-5.1.2` from its release metadata;
  its settings are documented in the upstream
  [v4.7.5 configuration reference](https://github.com/netbox-community/netbox/blob/v4.7.5/docs/configuration/system.md)
  and [database configuration](https://github.com/netbox-community/netbox/blob/v4.7.5/docs/configuration/required-parameters.md).
  The checked-in
  [CoRE-Docker NetBox image README](https://slop.writemy.codes/CoRE/CoRE-Docker/src/branch/main/Images/NetBox/README.md)
  and [image source](https://slop.writemy.codes/CoRE/CoRE-Docker/src/branch/main/Images/NetBox)
  describe the custom image, while this ApplicationSet selects the mutable
  `kristianfoss/netbox:core` tag. The current DC1 pod uses image digest
  `sha256:b12127b5ecce5ec0e9ae8465514231faa7e538a32fca401f2708c7cf59d6e3c9`,
  while the YVR Deployment currently has zero replicas. The checked-in
  CoRE-Docker Dockerfile currently declares a `v4.6.8` base, so that source
  snapshot does not describe the current image artifact. Keep the deployed
  digest and release metadata as the live version evidence. The chart's
  bundled Valkey and PostgreSQL dependencies are disabled; chart 8.x renamed
  the former `redis.enabled` dependency control to `valkey.enabled` and the
  external Redis settings to `tasksDatabase` and `cachingDatabase`. The
  ApplicationSet configures the shared global primary
  `psql-int.mylogin.space` as `externalDatabase.host`, so every cluster writes
  to the same PostgreSQL primary. Each target has a dedicated PostgreSQL login
  while all targets share the existing database. PostgreSQL also publishes
  site-local replica services at
  `psql-int-rep.<cluster>.<datacenter>.<region>.mylogin.space`.
  NetBox container requests come from the target's `netbox.resources` values;
  Home1/YVR requests `1Gi` and limits memory to `3Gi`.
  The base values
  allocate Dragonfly databases `80` and `81` and select the generated password
  Secret, while the ApplicationSet injects each target's site-local TLS
  endpoint. The chart's application version does not select the running
  NetBox version because this deployment deliberately overrides the image and
  tag.
  The chart configures `DATABASES.default` against global primary
  `psql-int.mylogin.space` and a `replica` alias against each site's
  `psql-int-rep.<cluster>.<datacenter>.<region>.mylogin.space` standby service.
  The aliases use the same cluster-specific username and generated password;
  the replica password is passed with a `secretKeyRef` from the existing
  `netbox-db-creds` Secret. No credential is rendered into values or a
  ConfigMap. PostgreSQL `target_session_attrs: read-only` makes the replica
  connection reject a primary endpoint if that Service or DNS answer changes
  during failover. See the PSQL chart's
  [replica Service configuration](../../Databases/PSQL/templates/PSQL-Core/PSQL.yaml)
  and PostgreSQL's
  [connection selection settings](https://www.postgresql.org/docs/17/libpq-connect.html#LIBPQ-CONNECT-TARGET-SESSION-ATTRS).

  The chart mounts a custom
  [Django database router](files/netbox_database_router.py) and configures it
  for web and worker processes. Reads use the local standby unless they access
  authentication or session models, the request is mutating, a write has
  occurred in the current request context, an ORM instance is pinned to a
  database, or a transaction is already active. Writes and migrations use the
  global primary; the router does not migrate the replica alias. Asynchronous
  replication can still make a later read request briefly stale. The custom
  middleware is inserted before the image's current
  v4.7.5 middleware list, so review that list when updating the NetBox image.
  This runtime module is mounted from a chart-owned ConfigMap because the
  upstream chart supports YAML configuration and arbitrary ConfigMap volumes
  but does not provide an SQL read/write router. Django documents the generic
  [database router interface](https://docs.djangoproject.com/en/6.1/topics/db/multi-db/#database-routers);
  NetBox documents its [`DATABASE_ROUTERS` setting](https://github.com/netbox-community/netbox/blob/v4.7.5/docs/configuration/system.md#database_routers).
- [External Secrets Operator](https://external-secrets.io/latest/) reads
  runtime credentials from `mainvault-core`. Home1 owns the stable
  `netbox-core` LDAP bind identity and publishes only that identity's username
  and password. Kea's existing hub identity and site-managed database
  connection remain unchanged.

  Every target creates a namespaced
  [`User` claim](templates/Netbox/NetboxDatabaseUser.yaml) whose username
  includes its cluster name. Each claim connects through that site's
  `psql-int` PGPool and uses the shared `psql-main` SQL and `psql` Terraform
  ProviderConfigs to grant its role read/write access to all public tables in
  the existing `3dzxoCeJ1f` database; it does not create a database. The
  generated `netbox-db-creds` Secret is consumed directly by NetBox in that
  namespace. This matches the per-site service-user approach used by Network
  Nameservers while keeping NetBox data shared. The separate hub-only
  [`netbox-core` identity claim](templates/Netbox/NetboxUser.yaml) remains for
  LDAP binding and is not used for PostgreSQL connections. The
  [User Composition](../../Operations/SSO/User/templates/User/UserComposition.yaml)
  orphans PostgreSQL resources on claim deletion, so removing a per-site claim
  does not prove its PostgreSQL role and grants were removed.
- An [HTTPRoute](https://gateway-api.sigs.k8s.io/api-types/httproute/) attaches
  NetBox to the shared Gateway. An [Envoy Gateway SecurityPolicy](https://gateway.envoyproxy.io/latest/api/extension_types/)
  applies OIDC credentials synchronized from the secret store.
- When enabled by the owning ApplicationSet, a second HTTPRoute serves
  `ipam.gslb.mylogin.space` and a [K8GB `Gslb`](https://www.k8gb.io/latest/resource_ref/)
  advertises the regular `ipam.mylogin.space` hostname using failover between
  the `dc1` and `home1` geo tags. This uses the existing
  `gslb.mylogin.space` zone configured by the [Network Global stack](../Global/README.md);
  it does not create a separate DNS zone. The NetBox OIDC SecurityPolicy
  applies to both routes.
- External PostgreSQL stores NetBox and PowerDNS data. The cluster's shared
  authenticated, TLS-enabled `dragonfly-core` supplies two dedicated logical
  databases: DB `80` for NetBox tasks and DB `81` for NetBox caching; see
  [Dragonfly compatibility](https://www.dragonflydb.io/docs/category/managing-dragonfly).
- A Crossplane Terraform `ProviderConfig` configures the
  [NetBox Terraform provider](https://registry.terraform.io/providers/e-breuninger/netbox/latest/docs).
  It depends on the
  [Upbound Terraform provider](https://github.com/upbound/provider-terraform)
  and a synchronized NetBox token.
- S3 settings are generated from an ExternalSecret for NetBox object storage.
  [Django storage configuration](https://netboxlabs.com/docs/netbox/en/stable/configuration/system/#storages)
  describes the settings consumed by NetBox.

The controller path is Git -> Argo CD/ApplicationSet -> Lovely/Helm ->
Kubernetes and External Secrets -> Vault-backed secrets -> NetBox, Kea,
PowerDNS, PostgreSQL, Dragonfly, Gateway/OIDC, S3, and Crossplane/Terraform.
Argo CD `Synced`, pod readiness, or a Crossplane `Ready` condition alone does
not verify that this complete path works.

### DHCP identities, relay redundancy, and diagnostics

The DHCP server identifier is site-specific: Home1 renders `10.1.1.67`, while
the DC1/Talos and legacy DC1/K3s IPAM instances render `66.165.222.112`. These
values correspond to the observed stable IPAM Service paths: Home1 reports
`10.1.1.67`, and the DC1 Services expose `66.165.222.112` while PureLB reports
the shared `10.1.1.67` anycast allocation. The two Cisco helper destinations
are therefore preserved as distinct site paths; neither is removed by this
stack.

Home2 relays may deliver one DISCOVER to both site paths. The client chooses an
OFFER and sends DHCPREQUEST with option 54 set to the selected server. The
selected server should ACK; the other server may correctly log
`DHCP4_PACKET_DROP_0003` because the request contains a foreign server
identifier. The failure condition is when the selected server also does not
ACK. Set `dhcp.diagnostics.enabled: true` for temporary Kea DEBUG level 15
logging to inspect that decision, then return it to `false`.

```text
client DISCOVER -> relay 172.31.193.16 -> Home1 / DC1 Kea
client <- OFFER (server identifier A or B)
client DHCPREQUEST (option 54 = selected OFFER) -> relay -> both paths
selected Kea -> DHCPACK
other Kea -> DHCP4_PACKET_DROP_0003 (expected foreign-server discard)
```

Kea HA hooks are not configured in this repository: there is no
`libdhcp_ha.so`, `high-availability`, or load-balancing configuration. Shared
PostgreSQL lease storage is not equivalent to Kea HA; active/active behavior
across the two helper paths remains an intentional design and operational
verification item.

## Values and secrets

[`values.yaml`](values.yaml) contains site inputs and dependency overrides only.
The bjw-s workload definition is intentionally kept in
[`templates/00-common.yaml`](templates/00-common.yaml), while cluster values
come from the owning ApplicationSet. `dhcp.identity.ipv4` is required when
DHCPv4 is enabled and `dhcp.interfaces` defaults to `['eth0']`; the latter is
applied to both DHCPv4 and DHCPv6. `dhcp.diagnostics.enabled` temporarily
changes the DHCPv4 logger to severity `DEBUG` and debug level `15`.
The fixed `dhcp-core` Service is configured by the `dhcp.service.global`
values map, including its name, type, traffic policy, labels, ports, and other
Service properties. The owning ApplicationSet supplies `dhcp.global.enabled`,
`dhcp.address`, and the PureLB/Cilium global-service annotations for each
target. The reserved `dhcp.service.local.enabled` flag remains disabled for the
current global-only deployment.
Kea uses the fixed global LoadBalancer Service name `dhcp-core` in every target
namespace, matching the other shared global services. The Service selector and
DHCP UDP/67 endpoint remain site-local; only the Kubernetes Service identity is
shared across clusters. Kea runs with three replicas using a bounded RollingUpdate (`maxUnavailable: 1`,
`maxSurge: 1`) and the configured DHCP resource requests/limits. Stakater
Reloader watches both the generated DHCP Secret and source ConfigMap, so a
configuration change replaces pods through the controlled rollout rather than
leaving old Kea processes serving stale configuration.
The Kea Service follows the existing CDN global-service pattern: Cilium
ClusterMesh synchronizes EndpointSlices across sites, keeps local endpoints
preferred, and can fail over over the inter-site link. PureLB remains the
LoadBalancer VIP allocator, so the site-specific DHCP identities and helper
paths are unchanged. See the upstream [Cilium global service documentation](https://docs.cilium.io/en/stable/network/clustermesh/services/)
and [service affinity documentation](https://docs.cilium.io/en/stable/network/clustermesh/affinity/).
`dhcp.servers.dhcp4`, `dhcp6`, and `dhcpDdns` control the corresponding
`keactrl` process flags per target. The
PowerDNS sidecar uses the same `dhcpDdns` flag and is omitted when DHCP-DDNS is
disabled. The Kea image is pinned to the inspected `vps1-core` digest. The
custom NetBox image remains mutable and uses `Always`; it should be pinned when
that site image has a versioned publication process.

The complete editable Kea DHCPv4 baseline is under `dhcp.dhcp4` in
[`values.yaml`](values.yaml). It is native YAML rather than embedded JSONC, so
networks and assignments can be changed without editing an ExternalSecret
template. The chart prepends the site-derived Tinkerbell, iPXE, PXE, and UniFi
client classes and injects the secret-backed PostgreSQL lease configuration;
[External Secrets templating v2](https://external-secrets.io/latest/guides/templating/)
JSON-encodes the database name, username, and password before inserting them
into the configuration. Do not add those generated entries to `dhcp.dhcp4`. A
typical network is:

```yaml
dhcp:
  dhcp4:
    shared-networks:
      - name: 'example.dc1.resolvemy.host'
        relay:
          ip-addresses:
            - '192.0.2.1'
        subnet4:
          - id: 3001
            subnet: '192.0.2.0/24'
            option-data:
              - name: 'routers'
                data: '192.0.2.1'
            pools:
              - pool: '192.0.2.100 - 192.0.2.199'
            reservations:
              - hw-address: '02:00:00:00:00:10'
                hostname: 'example-host'
                ip-address: '192.0.2.10'
```

[`values.schema.json`](values.schema.json) rejects malformed IPv4 addresses,
CIDRs, MAC addresses, pools, subnet IDs, incomplete reservations, and malformed
DHCPv6 subnet/prefix-delegation entries. Helm
template validation additionally rejects duplicate network names, subnet IDs,
reservation IPs, reservation MACs, and client-class names. The generated
configuration is strict JSON, and the container runs Kea 3.2's documented
[`kea-dhcp4 -t` configuration check](https://kea.readthedocs.io/en/kea-3.2.0/man/kea-dhcp4.8.html)
before starting an enabled DHCPv4 daemon. This check does not establish the
lease-database connection; verify that separately after reconciliation.

DHCPv4 evaluates only the five generated site classes. Each expression first
checks that its source option exists, and the UEFI fallback now requires PXE
architecture option 93 so ordinary DHCP clients do not receive boot settings.
Only the PostgreSQL hook and `hw-address` reservation identifier are loaded,
matching the actual lease backend and assignments, consistent with Kea's
[configuration performance guidance](https://kea.readthedocs.io/en/kea-3.2.0/config-examples.html).
DHCPv6 is configured under
`dhcp.dhcp6`; add approved `subnet6`, address pools, prefix-delegation pools,
and reservations there. Documentation prefix `2001:db8::/32` is rejected.

The upstream NetBox chart now uses the distinct `netbox` resource name instead
of colliding with the release-derived `netbox-ipam` Kea/PowerDNS resources.
This renames and replaces the stateless NetBox web and worker workloads and
their Service; PostgreSQL, Dragonfly, and S3 data remain external. The
HTTPRoute and Terraform provider endpoint are updated to the new Service.

No credential values belong in Git. `netbox-secret`, `netbox-auth-creds`,
`netbox-db-creds`,
`dragonfly-core-password`, the DNS secret, pull credentials, OIDC
configuration, S3 credentials, and Terraform tokens are references to
controller-managed Secrets. NetBox uses `netbox-db-creds` for both PostgreSQL
aliases and the generated Dragonfly password for its tasks and cache. Rotating
either credential requires restarting the NetBox web and worker pods after the
updated Secret is available; the replica DB password is injected through an
environment variable. Keep an emergency access path independent of NetBox,
Authentik, the public Gateway, Vault application credentials, and any single
cluster.

## Validation and operations

Before merging a change:

```sh
helm dependency build .
helm lint .
helm template netbox-ipam . \
  --namespace core-prod \
  --set netbox.enabled=true
git diff --check -- Network/IPAM
```

Also render each ApplicationSet target with its injected values. Inspect the
DHCP boot server and artifact paths, IP-address uniqueness and overlap, Gateway
parent references, secret names and keys, LDAP groups, database endpoints, and
Crossplane provider configuration. The example secret name above is a literal
representative value, not a credential.

After Argo CD reconciliation, verify all of the following:

1. ExternalSecret and PushSecret conditions, without printing Secret data.
   On every target, verify the site-specific NetBox database `User` claim,
   composite, `netbox-db-creds` Secret, PostgreSQL role and table grants. On
   Home1, also verify the `netbox-core` LDAP identity claim and its
   `netbox-auth-creds` PushSecret.
2. On Home2, capture one transaction by MAC and confirm the sequence
   `DISCOVER -> OFFER -> REQUEST -> ACK`; compare option 54 in the selected
   OFFER and REQUEST, and confirm the selected server's identifier matches the
   site value. A drop on the non-selected server is expected; no ACK from the
   selected server is not.
3. Confirm Kea startup no longer reports DHCP socket-open failures for `tunl0`,
   `sit0`, or `ip6tnl0`, and that DHCP traffic continues on `eth0`.
4. Kea configuration load, lease allocation, PXE for the intended firmware,
   and Tinkerbell boot artifact retrieval on each target network. Also restart
   only the Kea container after an unclean daemon exit and verify it removes
   stale PID and control-socket files and returns ready without replacing the
   pod. Confirm the healthcheck fails when any enabled DHCPv4, DHCPv6, or
   DHCP-DDNS process is stopped and succeeds when all enabled processes are
   active.
5. Kea lease reads and writes through
   `psql.core-prod.svc.<cluster-domain>`, the PowerDNS `User` claim and scoped
   PostgreSQL grants, plus authoritative TCP/UDP answers. Confirm Kea's local
   RFC 2136 updates succeed, while external updates and access to the private
   PowerDNS listener are blocked; confirm no DNS UPDATE or NOTIFY forwarding.
   After a PowerDNS upgrade, verify TSIG operations, authorized zone transfers,
   and representative API consumers.
6. NetBox migrations, web and worker health, TLS-authenticated Dragonfly
   connectivity to DBs `80` and `81`, and database routing. Using the generated
   DB credential without printing it, confirm `psql-int.mylogin.space` returns
   `pg_is_in_recovery() = false`; confirm the site's
   `psql-int-rep.<cluster>...` endpoint returns `true` and
   `transaction_read_only = on`. Exercise a read request, a write request, and
   an immediate read after the write. Confirm each target's cluster-specific
   PostgreSQL role can access the shared database, plus OIDC login and group
   entitlement, API access, plugins, and S3 operations.
7. Gateway attachment and policy status, then the user-facing NetBox workflow.
8. Crossplane provider conditions and a harmless NetBox provider read.

After rotating `dragonfly-core-password`, reconcile or restart both NetBox
Deployments and verify that task processing and cache access recover. Secret
volume updates alone do not make the running NetBox processes reconnect with
the new password.

Inventory changes may eventually drive physical provisioning. Resolve the
exact site, cluster, machine, hardware identity, install disk, network, and
workflow state before retrying or applying a provisioning action. Never retry
an unidentified Tinkerbell/Talos failure.

Rollback through Git and let Argo CD reconcile the prior desired state. A chart
rollback does not roll back PostgreSQL contents, DHCP leases, Vault records,
S3 objects, or Terraform-created state. Back up NetBox and test restoration
before treating it as provisioning authority; explicitly assess those external
side effects before reverting or deleting resources. Rolling back this upgrade
recreates the former `netbox-ipam` bjw-s Deployment and the former
`netbox-ipam`-named NetBox resources; verify that the Service selectors,
HTTPRoute backend, and Terraform endpoint return to the same revision together.
