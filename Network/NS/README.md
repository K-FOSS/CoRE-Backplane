# Authoritative DNS

This rendering unit deploys the public PowerDNS authoritative service and its
PowerDNS-Admin UI. The owning `Apps/Network/NS.yaml` ApplicationSet is the
source of truth for target selection and site-specific service annotations.

## Current deployment

The ApplicationSet explicitly merges `core-dc1-talos-prod` and
`core-home1-talos-prod` with registered bare-metal infrastructure clusters.
Both currently receive `hub: false`. The authoritative PowerDNS credentials
continue to use the shared secret path; each site instead provisions its own
PowerDNS-Admin database role and database through a local `User` claim. Argo CD
deploys each release to `core-prod` with the Lovely Helm merge renderer.

The operator-provided authoritative DNS topology is `ns1.resolvemy.host`
through `ns4.resolvemy.host`, with two names assigned to DC1 and two to YVR.
All four are part of this Network/NS PowerDNS service. The ApplicationSet
currently emits `ns4.resolvemy.host` at DC1 address `66.165.222.100` and
`ns2.resolvemy.host` at Home1/YVR. Home1 uses a `ClusterIP` nameserver Service;
its public DNS target is supplied through the YVR ExternalDNS target annotation,
not through KubeVIP, UPnP, or PureLB. DC1 remains the LoadBalancer site using
the assigned PureLB address `66.165.222.100` and service group `anycast`.
Confirm the live DNS target and external reachability before relying on either
site for delegation.
The current values do not emit the other two names, so verify their live
records and site assignments against the authoritative zone before relying on
them for delegation.

Keep the logical nameserver set distinct from PowerDNS pod replicas. The
current `Network/NS` workload template leaves the PowerDNS controller at its
BJW-S default of one replica per cluster, and live inspection found one
`ns-core-main` pod in each cluster. It does not currently run two PowerDNS
pods per site. Update and verify that workload separately before describing
the two-per-site replica count as deployed pod capacity.

The chart renders:

- [PowerDNS Authoritative Server 5.1.4](https://doc.powerdns.com/authoritative/changelog/5.1.html#change-5.1.4)
  backed by PostgreSQL and exposed on TCP and UDP port 53 through PureLB in
  DC1 and KubeVIP in Home1. The
  [official PowerDNS container](https://github.com/PowerDNS/pdns/blob/master/Docker-README.md)
  is pinned to its multi-architecture manifest digest.
- [PowerDNS-Admin 2026.08.1](https://github.com/PowerDNS-Admin/PowerDNS-Admin/tree/v2026.08.1)
  provides forward and reverse zone management against this PowerDNS API. Its
  [official multi-architecture image](https://hub.docker.com/r/powerdnsadmin/pda-legacy/tags)
  is pinned by manifest digest. The UI is available
  at a per-site `nsadmin.<cluster>.<datacenter>.<region>.resolvemy.host`
  hostname. Each site has a separate
  [Authentik OAuth2/OIDC provider](https://docs.goauthentik.io/add-secure-apps/providers/oauth2/)
  restricted to the
  `Network` group; native LDAP stays enabled for existing LDAP logins and its
  configured user/admin group role mapping. OIDC-created accounts receive the
  application's default user role until an administrator assigns zone access.
  Local password login and signup are disabled.
- [External Secrets Operator](https://external-secrets.io/latest/) resources
  for the authoritative PowerDNS API key and database credentials.
- The [BJW-S common library chart 5.0.1](https://github.com/bjw-s-labs/helm-charts/tree/common-5.0.1/charts/library/common)
  used to generate workloads, Services, storage mounts, and the HTTPRoute.

The chart retains the pre-v4 names of the primary Service and ConfigMap to
avoid changing the public LoadBalancer identity or its volume reference. The
[v3-to-v4 migration](https://bjw-s-labs.github.io/helm-charts/docs/app-template/upgrades/3-to-4/)
changes the immutable Deployment selector label from
`app.kubernetes.io/component` to `app.kubernetes.io/controller`, so the first
5.x reconciliation requires both Deployments to be deliberately recreated.
The [v4-to-v5 migration](https://bjw-s-labs.github.io/helm-charts/docs/app-template/upgrades/4-to-5/)
introduces dedicated ServiceAccount creation by default. This chart opts out,
so workloads use the namespace's default identity without mounting its API
token; neither workload uses the Kubernetes API. The authoritative
PowerDNS container is pinned to the image's `pdns` UID/GID 953, uses the runtime
default seccomp profile, drops all Linux capabilities, forbids privilege
escalation, and runs with a read-only root filesystem. Only a size-limited,
memory-backed `/tmp` volume remains writable for its control socket. Both
containers have explicit CPU, memory, and ephemeral-storage requests and
limits so a DNS or administration failure cannot consume unbounded node
resources.

The public address, ExternalDNS hostname/target,
[PureLB](https://purelb.gitlab.io/purelb/) sharing key, cluster identity, and
region are injected by the ApplicationSet. Keep site-specific values there
rather than adding another literal to this chart.

`templates/common.yaml` owns the bjw-s resource model: controllers, Services,
route, mounts, and generated ConfigMap. `values.yaml` contains the supported
deployment inputs, including image pins, PowerDNS and PowerDNS-Admin settings,
resource requests, and the ApplicationSet's `service.main.annotations` merge
point. Keep new bjw-s implementation details in the template and expose a value
only when operators or target clusters need to change it.

## Reconciliation and prerequisites

Argo CD renders Helm and creates the resources in the target cluster. External
Secrets must populate the referenced Kubernetes Secrets before PowerDNS and
PowerDNS-Admin can become ready. PowerDNS connects to the
[cluster-local Pgpool `psql` Service](../../Databases/PSQL/README.md) using the
FQDN injected by the ApplicationSet; its database credentials remain
secret-backed. PowerDNS-Admin uses the internal PowerDNS API Service and
is protected by the shared Authentik forward-auth outpost through a fail-closed
Envoy Gateway `SecurityPolicy`. The Authentik proxy application and the native
OIDC application are restricted to the `Network` group. The native PowerDNS
Admin application is displayed as `DNS Admin` and grouped in Authentik under
`<datacenter>-<cluster>`, like other cluster-scoped applications. The Forward
Auth application is hidden from the Authentik application dashboard with the
`blank://blank` launch URL, so it does not show a duplicate launch card; the
policy binding and proxy provider remain active for route authorization.
Authentik documents this as the hiding method before 2026.5 and migrates it to
the dashboard hide setting on upgrade
([application visibility documentation](https://docs.goauthentik.io/add-secure-apps/applications/manage_apps)).
After the proxy admits the request, PowerDNS-Admin handles its own OIDC or LDAP
login and role mapping. The policy uses Authentik's
[proxy provider](https://docs.goauthentik.io/add-secure-apps/providers/proxy/)
through Envoy Gateway's
[external authorization](https://gateway.envoyproxy.io/v1.8/tasks/security/ext-auth/)
integration. The generated HTTPRoute backend targets the full Service name
`ns-core-nsadmin`, rather than the chart's short logical service identifier.

PowerDNS-Admin's PostgreSQL connection is independent at each site. The
`Apps/Network/NS.yaml` injects the site-local `psql-local.<cluster>.<datacenter>.<region>.mylogin.space`
endpoint and matching `psql-<datacenter>-<region>` provider names. The
`ns-core-nsadmin-db` `User` claim uses those values to create the Authentik
service identity, PostgreSQL role and database. The [User claim composition](../../Operations/SSO/User/README.md)
publishes the generated `psqlURI` in the claim Secret; the Deployment consumes
it from `ns-core-nsadmin-creds`, and [Stakater Reloader's Secret annotation](https://docs.stakater.com/reloader/latest/reference/annotations.html)
restarts the app when that Secret changes. These credentials are not pushed to
the shared Vault database path. Claim deletion orphans its PostgreSQL
resources, so removal needs a separate database and role cleanup decision.
The claim explicitly uses SQLAlchemy's `postgresql://` URI scheme; PowerDNS-Admin's
[v0.5.1 release notes](https://github.com/PowerDNS-Admin/PowerDNS-Admin/releases/tag/v0.5.1)
document that SQLAlchemy 1.4 removed support for the old `postgres://` form.

The current PostgreSQL topology makes `core-dc1-talos-prod` a physical standby
of the writable Home1 hub. A standby cannot accept the role/database writes
requested by the DC1 `User` claim, and PowerDNS-Admin also needs a writable
database. The site-local configuration therefore requires DC1 to have a
writable PostgreSQL target before that site's claim and Deployment can become
operational; rendering the manifests does not establish that prerequisite.

The Authentik provider credentials are generated per site by the
[Authentik Terraform provider](https://registry.terraform.io/providers/goauthentik/authentik/latest/docs/resources/provider_oauth2)
Workspace and written to its local `ns-core-nsadmin-oidc` connection
Secret, consumed by the PowerDNS-Admin container. The provider registers strict
`/oidc/authorized` and `/oidc/logged-out` URLs for that site's hostname. Keep
these callback URLs aligned if the hostname or OIDC routes change.

The deployment requires the PowerDNS PostgreSQL schema and user, the
`mainvault-core` and `corevault-rootsecrets` `ClusterSecretStore` objects,
External Secrets CRDs, PureLB, Gateway API and Envoy Gateway CRDs, ExternalDNS,
and valid public delegation and glue records. Secret values must remain in the
secret stores and must not be placed in Git or rendered validation output.

## Validation and operations

Resolve dependencies and validate both Helm branches before merging:

```sh
helm dependency build .
helm lint . --set hub=false \
  --set powerdns.database.host=psql.core-prod.svc.cluster.local
helm template ns-core . --namespace core-prod --set hub=false \
  --set powerdns.database.host=psql.core-prod.svc.cluster.local >/tmp/ns.yaml
helm template ns-core . --namespace core-prod --set hub=true \
  --set powerdns.database.host=psql.core-prod.svc.cluster.local >/tmp/ns-hub.yaml
```

Use representative ApplicationSet-injected values when reviewing Service
annotations. After reconciliation, confirm the `ExternalSecret` conditions,
PowerDNS database/API connectivity, LoadBalancer address, endpoints, Envoy
authorization, and Application health. Then query every authoritative address
directly over UDP and TCP and verify delegation, SOA serials, transfers and
notifications, DNS updates, and DNSSEC where enabled. Cached recursive answers
are not sufficient evidence.

For the first 3.x-to-5.x sync, recreate only the identified `ns-core-main` and
`ns-core-nsadmin` Deployments in each target cluster after confirming their
site and namespace. Do not force-sync the whole Application. Argo CD then
creates them with the new immutable selectors while preserving the Services,
ConfigMap, routes, and credentials. Confirm both replacements are ready before
continuing with the DNS checks above.

PowerDNS retains packet-cache, positive backend-query, and negative
backend-query results for 300 seconds. This allows it to continue answering
with the cached backend value during brief database interruptions, but it can
also delay visibility of database or API changes for up to five minutes. Use
`pdns_control purge` inside the authoritative-server pod when a verified
change must be visible immediately; this clears cache state but does not alter
zone data.

The upgrade from 4.9.14 to 5.1.4 follows the
[PowerDNS upgrade notes](https://doc.powerdns.com/authoritative/upgrading.html).
PostgreSQL must be 9.5 or newer for the 5.1 default TSIG replacement query.
During upgrade verification, test a harmless RFC 2136 update and rollback,
TSIG operations, zone transfers and notifications, and representative API
consumers; API record representations can be normalized differently in 5.1.
Updates to LUA records remain disabled because this deployment does not enable
them.

Rollback through Git and let Argo CD reconcile the previous render. Removing
the Application deletes namespaced resources unless Argo CD preservation is
configured elsewhere; it does not remove external Vault data, the shared
database, public delegation/glue, or cached DNS answers. Review TTLs and
database compatibility before version rollback or site removal.
