# Authoritative DNS

This rendering unit deploys the public PowerDNS authoritative service and its
PowerDNS-Admin UI. The owning `Apps/Network/NS.yaml` ApplicationSet is the
source of truth for target selection and site-specific service annotations.

## Current deployment

The ApplicationSet explicitly merges `core-dc1-talos-prod` and
`core-home1-talos-prod` with registered bare-metal infrastructure clusters.
Both currently receive `hub: false`, so they pull the shared database and
admin credentials from `mainvault-core`; the `User` and `PushSecret` resources
for a hub deployment are not rendered. Argo CD deploys each release to
`core-prod` with the Lovely Helm merge renderer.

The chart renders:

- [PowerDNS Authoritative Server 5.1.3](https://doc.powerdns.com/authoritative/changelog/5.1.html#change-5.1.3)
  backed by PostgreSQL and exposed on TCP and UDP port 53 through PureLB. The
  [official PowerDNS container](https://github.com/PowerDNS/pdns/blob/master/Docker-README.md)
  is pinned to its multi-architecture manifest digest.
- [PowerDNS-Admin 0.4.2](https://github.com/PowerDNS-Admin/PowerDNS-Admin/tree/v0.4.2)
  behind an [Envoy Gateway security policy](https://gateway.envoyproxy.io/docs/api/extension_types/#securitypolicy)
  and fail-closed [Authentik forward authentication](https://docs.goauthentik.io/add-secure-apps/providers/proxy/server_envoy/).
- [External Secrets Operator](https://external-secrets.io/latest/) resources
  for the PowerDNS API key and database, LDAP, and application credentials.
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
secret-backed. PowerDNS-Admin uses the internal PowerDNS API Service. Envoy
Gateway calls the Authentik external-auth service before allowing UI traffic.

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

The upgrade from 4.9.14 to 5.1.3 follows the
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
