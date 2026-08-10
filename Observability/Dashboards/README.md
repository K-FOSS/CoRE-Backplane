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
| `core-home1-talos-prod` | `core-home1-talos-prod-dashboards` | `core-prod` | `false` | `2` | `SingleBinary` |
| `core-dc1-talos-prod` | `core-dc1-talos-prod-dashboards` | `core-prod` | `false` | `2` | `Distributed` |

`mode` is part of the generator data but is not consumed by this chart. The
ApplicationSet also derives the cluster domain, region, zone, and datacenter
from cluster Secret labels. Lovely merges the generated `hub` value and two
cluster-specific Grafana settings into [`values.yaml`](values.yaml):

- `grafanaReplicas` controls the replica count independently for each listed
  cluster.
- Grafana Live and Grafana's remote cache use the site's shared `dragonfly-core`
  Redis-compatible service. The remote cache uses TLS.
- Grafana reads the Dragonfly password from the existing
  `dragonfly-core-password` Secret and Reloader restarts the Deployment when
  that Secret changes.
- Grafana exports OpenTelemetry traces to the cluster-local Alloy service.
- LDAP mounts the existing `grafana-core-ldap` Secret.

Argo CD creates the namespace, uses the Lovely config-management plugin, and
preserves resources when an Application is deleted. Automated sync, prune, and
self-heal are not configured here.

## Rendered components

The chart pins the [Grafana Helm chart 10.1.0](https://github.com/grafana/helm-charts/tree/grafana-10.1.0/charts/grafana).
The release renders one Grafana replica named `grafana-core`, a ClusterIP
Service, cluster-scoped dashboard-sidecar RBAC, and an HTTPRoute for
`grafana.int.mylogin.space` attached to `core-prod/main-gw`. The upstream chart
provides the [Grafana configuration values](https://github.com/grafana/helm-charts/blob/grafana-10.1.0/charts/grafana/values.yaml)
and container defaults; local values deliberately override its authentication,
database, routing, plugin, and dashboard-discovery behavior.

Dashboard discovery uses the chart's
[k8s-sidecar integration](https://github.com/grafana/helm-charts/tree/grafana-10.1.0/charts/grafana#sidecar-for-dashboards)
to watch ConfigMaps labelled `grafana_dashboard` in the release namespace. This
is a namespaced dashboard watch, not the source of the cluster-wide telemetry
traffic described in the [Collectors guide](../Collectors/README.md).

The local templates additionally render:

- an [ExternalSecret](https://external-secrets.io/latest/api/externalsecret/)
  named `grafana-core-ldap` on every target;
- an [Envoy Gateway SecurityPolicy](https://gateway.envoyproxy.io/docs/api/extension_types/#securitypolicy)
  that performs Authentik OIDC and JWT validation for the `grafana-core`
  HTTPRoute;
- hub-only Crossplane `User` and
  [Terraform Workspace](https://marketplace.upbound.io/providers/upbound/provider-terraform/latest/resources/tf.upbound.io/Workspace/v1beta1)
  resources, plus [PushSecrets](https://external-secrets.io/latest/api/pushsecret/)
  that publish generated database and OIDC material to CoreVault; or
- spoke-only ExternalSecrets that retrieve the database and OIDC material from
  CoreVault.

At present both ApplicationSet entries inject `hub: false`. Consequently, the
hub-only `User`, Authentik Workspace, and PushSecrets are not rendered by these
two Applications. They remain chart behavior for a caller that explicitly
renders this unit with `hub: true`; do not assume the default in `values.yaml`
describes the current Argo CD deployment.

## Identity, secrets, and data flow

Grafana reads its administrator username, password, and PostgreSQL URL from
`core-grafana-creds`. It reads its OIDC client ID and client secret from
`grafana-core-authentik`. The ApplicationSet also exposes the `password` key
from `dragonfly-core-password` as `DRAGONFLY_PASSWORD`; Grafana expands that
environment variable in its Live and remote-cache configuration. Secret values
are created or synchronized by controllers and are never stored in Git.

Requests first pass through the HTTPRoute and SecurityPolicy. Envoy Gateway
uses Authentik for OIDC, validates JWTs, and forwards selected identity claims
as headers. Grafana has [auth proxy](https://grafana.com/docs/grafana/latest/setup-grafana/configure-security/configure-authentication/auth-proxy/)
configured for those headers. Grafana's generic OAuth block exists but is
disabled; LDAP remains enabled and reads `ldap-toml` from the ExternalSecret.
See Grafana's [LDAP documentation](https://grafana.com/docs/grafana/latest/setup-grafana/configure-security/configure-authentication/ldap/)
before changing mappings or bind behavior.

The access path spans Authentik scopes and groups, Envoy claim forwarding,
Grafana role mapping, and LDAP group mappings. Review those layers together.
In particular, the current LDAP configuration grants Grafana server-admin to
members of `authentik Admins` and `Grafana Admins`, while the disabled generic
OAuth mapping refers to `Network Admins` and `Grafana Editors`.

Grafana stores application state in the external PostgreSQL database; local PVC
persistence is disabled. Grafana Live and the
[remote cache](https://grafana.com/docs/grafana/latest/setup-grafana/configure-grafana/#remote_cache)
use the ApplicationSet-injected Dragonfly address. The cache stores temporary
authentication-related data, not Grafana sessions or authoritative application
state. It is isolated in Dragonfly database `132`; Grafana Live remains on the
default Redis database because its Redis client does not expose a database
selector. Refer to Grafana's [database configuration](https://grafana.com/docs/grafana/latest/setup-grafana/configure-grafana/#database)
and [Live HA setup](https://grafana.com/docs/grafana/latest/setup-grafana/set-up-grafana-live/#configure-grafana-live-ha-setup)
when changing either dependency. Grafana Live's Redis client does not support
TLS, while the remote-cache client is explicitly configured with `ssl=true`;
verify the Dragonfly listener behavior for both clients after reconciliation.

## Prerequisites

Before reconciliation, the target cluster must provide:

- Argo CD with the Lovely plugin and access to this repository;
- Gateway API and Envoy Gateway CRDs, `core-prod/main-gw`, and the corresponding
  public DNS and TLS path;
- External Secrets Operator, `mainvault-core`, and access to `Grafana/User`,
  `Grafana/Database`, and `Grafana/OIDC` remote keys;
- the platform `User` composition and Terraform provider for a hub render;
- Authentik flows, the `Logs` scope mapping, the `tls` signing certificate, and
  the groups referenced by the access configuration;
- PostgreSQL and the cluster-scoped `dragonfly-core` service and
  `dragonfly-core-password` Secret in `core-prod`;
- Alloy at the ApplicationSet-generated in-cluster OTLP address.

The chart also installs `grafana-advisor-app` and `grafana-llm-app` at pod
startup. Their component documentation is the
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
  --set grafana.replicas=2 \
  --set-string grafana.annotations.'secret\.reloader\.stakater\.com/reload'='dragonfly-core-password' \
  --set-string grafana.envValueFrom.DRAGONFLY_PASSWORD.secretKeyRef.name='dragonfly-core-password' \
  --set-string grafana.envValueFrom.DRAGONFLY_PASSWORD.secretKeyRef.key='password' \
  --set-string grafana.grafana\.ini.live.ha_engine_address='dragonfly.core-home1-talos-prod.home1.example-region.mylogin.space:6379' \
  --set-string grafana.grafana\.ini.live.ha_engine_password='$__env{DRAGONFLY_PASSWORD}' \
  --set-string grafana.grafana\.ini.remote_cache.type='redis' \
  --set-string grafana.grafana\.ini.remote_cache.connstr='network=tcp\,addr=dragonfly.core-home1-talos-prod.home1.example-region.mylogin.space:6379\,pool_size=100\,db=132\,password=$__env{DRAGONFLY_PASSWORD}\,ssl=true' \
  --set-string grafana.grafana\.ini.tracing\.opentelemetry\.otlp.address='core-home1-talos-prod-collectors-alloy.core-prod.svc.cluster.local:4317' \
  --set-string grafana.grafana\.ini.tracing\.opentelemetry\.otlp.propagation='w3c' \
  --set grafana.ldap.enabled=true \
  --set-string grafana.ldap.existingSecret='grafana-core-ldap'
```

The hostnames in that example are representative literals, not discovered live
values. Inspect the rendered HTTPRoute, SecurityPolicy, Secret references,
Workspace/ExternalSecret branch, RBAC, Deployment environment, and Grafana
ConfigMap before merging.

After Argo CD reconciliation, verify more than Application health:

1. Confirm ExternalSecret conditions and the presence of the expected Secret
   keys, including `dragonfly-core-password/password`, without printing their
   values.
2. Confirm the HTTPRoute is accepted by `main-gw` and the SecurityPolicy is
   attached without errors.
3. Check the Grafana Deployment rollout and `/api/health` endpoint.
4. Test OIDC and LDAP login with least-privileged and administrative accounts,
   including logout and refresh behavior.
5. Check dashboard-sidecar logs and confirm labelled dashboards appear.
6. Rotate the Dragonfly credential through its owning workflow and verify
   Reloader rolls both Grafana replicas after the Secret changes.
7. Verify PostgreSQL connectivity, Grafana Live and remote-cache connectivity,
   and OTLP traces reaching Alloy and the downstream traces backend.

## Rollback and deletion

Rollback is a Git revert followed by Argo CD reconciliation. Changes to resource
names, secret targets, redirect URIs, or identity mappings can cause replacement
or lockout and require an explicit migration plan.

`preserveResourcesOnDeletion: true` means deleting an Application does not
remove its managed resources. Conversely, removing a template from Git during
normal reconciliation may still prune it if pruning is enabled elsewhere.
Before deliberate teardown, identify the owning Application, controller
finalizers, Crossplane deletion policy, external Authentik objects, Vault data,
database state, and HTTPRoute. Do not delete shared remote secrets or the
PostgreSQL database as part of a routine Grafana rollback.
