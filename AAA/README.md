# AAA chart

This chart deploys CoRE's authentication, authorization, and accounting
services. Authentik provides the primary identity service; local templates add
Vault-backed database and outpost credentials, LDAP/RADIUS/proxy outposts,
Gateway API routing and policy, multi-cluster backends, and an optional legacy
OpenLDAP proxy.

The fleet entry point is
[`Apps/AAA/AAA.yaml`](../Apps/AAA/AAA.yaml). It selects bare-metal clusters,
marks one cluster as the credential hub, and injects cluster identity,
environment, database, service-discovery, and TLS-mount values through Lovely.
Those merged values are authoritative for deployed clusters;
[`values.yaml`](values.yaml) contains shared defaults.

## Architecture

Every selected cluster receives:

- the upstream Authentik server and worker;
- ExternalSecrets for database credentials and the shared Authentik service
  user;
- the public `idp.mylogin.space` HTTPRoute, Envoy Gateway traffic/security
  policies, and cross-namespace ReferenceGrants;
- optional LDAP, RADIUS, and proxy outpost Deployments and Services; and
- optional Envoy `Backend` objects for peer Authentik clusters.

The HTTPRoute sends traffic to the local Authentik server and every configured
peer backend with equal weight. This provides multi-cluster reachability, but
it also means a bad peer endpoint can affect the shared identity hostname.

Authentik uses the external PostgreSQL host configured in values. Server
replicas default to two with a PodDisruptionBudget; the worker and all enabled
outposts depend on the shared database and secret-store chain.

## Hub and spoke credential flow

`hub` changes how the `authentik-core` service credential is managed:

- On the hub cluster, a `mylogin.space/v1alpha1` `User` named
  `authentik-core` is created in the `LDAPService` group. Its generated
  connection Secret is published to Vault by a `PushSecret`.
- On spoke clusters, an `ExternalSecret` reads the same username and password
  from Vault into a local `authentik-core` Secret.

Exactly one fleet member should be the hub. Changing hubs without sequencing
the User, PushSecret, Vault data, and spoke synchronization can rotate or
remove credentials used by Authentik email or other integrations.

Database and application secrets are read from the `mainvault-core`
ClusterSecretStore:

| Kubernetes Secret | Vault path(s) | Consumer |
| --- | --- | --- |
| `aaa-authentik-database` | `AAA/Authentik/Database`, `AAA/Authentik/General` | Authentik PostgreSQL settings and secret key. |
| `authentik-core` | `AAA/Authentik/User` | Authentik email/service identity. |
| `ldap-credentials` | `AAA/Authentik/LDAP` | LDAP outpost token. |
| `radius-credentials` | `AAA/Authentik/RADIUS` | RADIUS outpost token. |
| `aaa-proxy-credentials` | `AAA/Authentik/Proxy` | Proxy outpost token. |

Secret references in Git are not secret values. Avoid printing synchronized
Secret contents during routine diagnostics.

## Prerequisites

- External Secrets with the `mainvault-core` ClusterSecretStore and PushSecret
  support.
- The `User` Crossplane API/composition used on the hub.
- An externally reachable PostgreSQL service and initialized Authentik
  database.
- Gateway API and Envoy Gateway's `BackendTrafficPolicy`, `SecurityPolicy`,
  and `Backend` CRDs.
- The shared Gateway and TLS certificate Secret injected by the ApplicationSet.
- ExternalDNS and any service-label controllers used for public/private
  exposure.
- Prometheus Operator CRDs when Authentik ServiceMonitor/rules are enabled.
- Valid Authentik outpost tokens already created for each enabled outpost.

The chart currently assumes platform-specific domains, Vault paths,
namespaces, and ReferenceGrant consumers. It is not portable without reviewing
the local templates.

## Important values

### Platform values

| Value | Meaning |
| --- | --- |
| `env` | Environment included in resource names and labels. |
| `cluster.name`, `cluster.domain` | Cluster identity and Kubernetes service DNS suffix. |
| `datacenter`, `region` | Form LDAP/RADIUS DNS names and peer identity. |
| `hub` | Selects credential producer (`User` + `PushSecret`) or consumer (`ExternalSecret`) behavior. |
| `gateway.name`, `gateway.namespace` | Parent Gateway used by the Authentik HTTPRoute. |
| `peers` | Additional Envoy backends, each with `cluster` and IP `endpoint`. |
| `authentik` | Values passed to the upstream Authentik chart plus local outpost settings. |
| `openldap.enabled` | Enables the legacy OpenLDAP proxy; disabled by default. |

### Authentik

The upstream subchart consumes `authentik.authentik` for application
configuration and `authentik.global`, `server`, `worker`, and related
deployment settings. Current defaults:

- use an external PostgreSQL host;
- load database credentials and `AUTHENTIK_SECRET_KEY` from
  `aaa-authentik-database`;
- load email credentials from `authentik-core`;
- run two server replicas with a PDB;
- enable server metrics, ServiceMonitor, and Prometheus rules;
- enable LDAP, RADIUS, and proxy outposts.

The ApplicationSet mounts `myloginspace-default-certificates` into Authentik
workers. Authentik discovers certificates by the directory containing
`tls.crt` and `tls.key`; the mount directory is cluster-specific, with an
established `tls` exception for the DC1 Talos cluster.

### Outposts

| Values | Resources and ports |
| --- | --- |
| `authentik.ldap.enabled`, `replicas` | LDAP outpost Deployment, token ExternalSecret, and Service exposing TCP/UDP 389, 636, and metrics 9300. |
| `authentik.radius.enabled`, `replicas` | RADIUS outpost Deployment and Service exposing TCP/UDP 1812 and metrics 9300. |
| `authentik.proxy.enabled`, `replicas` | Proxy outpost Deployment, token ExternalSecret, Service on port 80, and `/outpost.goauthentik.io` HTTPRoute. |

Outposts connect to the local Authentik server over cluster DNS with
`AUTHENTIK_INSECURE=true`; the traffic remains inside the cluster service
network. Their tokens determine outpost identity and authorization.

Current template coupling requires special care:

- the RADIUS credential ExternalSecret is conditional on
  `authentik.ldap.enabled`, not `authentik.radius.enabled`;
- the proxy Service is conditional on `authentik.radius.enabled`, while its
  Deployment and route are conditional on `authentik.proxy.enabled`.

Until those conditions are corrected, changing the feature flags
independently can produce a Deployment without its credentials or Service.
Always inspect the rendered resource set.

### Multi-cluster routing

Each `peers[]` item renders an Envoy Gateway `Backend` named
`aaa-server-<cluster>` pointing to `<endpoint>:80`. The main HTTPRoute includes
all peer Backends at weight 1 alongside the local Authentik Service.

Example:

```yaml
peers:
  - cluster: core-home1-talos-prod
    endpoint: 192.0.2.20
```

Peer endpoints must be reachable from the Gateway data plane and must serve
the same Authentik deployment/state. Verify database sharing, signing
material, session behavior, certificate handling, health checks, and failure
behavior before adding a peer.

### Legacy OpenLDAP

`openldap.enabled` creates a ConfigMap and a single-replica Deployment running
a platform-specific OpenLDAP image. It proxies the hardcoded
`ldaps://ldap.mylogin.space:636` directory and mounts the configured TLS
Secret. No Service is created by these templates. This path is disabled by
default and should be treated as legacy rather than a general OpenLDAP chart.

## Gateway and authorization policy

`aaa-authentik` attaches to the configured shared Gateway and serves
`idp.mylogin.space`. A BackendTrafficPolicy configures active readiness checks
against `/-/health/ready/` and request timeouts. A SecurityPolicy applies CORS
rules.

The ReferenceGrant permits SecurityPolicies from a fixed set of namespaces to
reference the Authentik server and proxy Services. Adding a namespace expands
which workloads may delegate authentication to AAA; review it as an
authorization boundary.

The HTTPRoute hostname, Gateway section name, CORS origin, Vault paths, and
some namespaces/domains are currently hardcoded. The
`gateway.sectionName` value is present but the Route currently uses a fixed
section name.

## Rendering and validation

Update dependencies only when intentionally changing the locked Authentik
version:

```sh
helm dependency build AAA
```

Render defaults:

```sh
helm lint AAA
helm template aaa AAA --namespace core-prod > /tmp/aaa.yaml
```

To reproduce a cluster, copy its `hub`, `cluster`, `datacenter`, `region`, and
other injected values from `Apps/AAA/AAA.yaml` into a temporary values file.
The Lovely merge also supplies Authentik service annotations, labels,
PostgreSQL settings, and worker TLS mounts.

Before syncing, inspect:

- which cluster is the only hub;
- every Secret producer, target name, store, and Vault property;
- PostgreSQL hostname and database credentials;
- the optional PostgreSQL read replica used by the YXL hub instance, following
  Authentik's [PostgreSQL read-replica configuration](https://docs.goauthentik.io/install-config/configuration/#read-replicas);

Adding or removing the read replica requires restarting the Authentik server
and worker pods. Verify the rendered replica host and the
`aaa-authentik-read-replica` ConfigMap before reconciliation, then confirm read
traffic reaches the replica while writes continue to use the primary. Replica
database credentials come directly from the existing
`aaa-authentik-database` Secret; the ConfigMap contains only the non-secret
replica hostname.
- Authentik server/worker images, replicas, PDB, probes, and resources;
- enabled outpost Deployments, matching Secrets and Services;
- Route parent references, peer endpoints, timeouts, and policy targets;
- TLS Secret names and worker mount paths; and
- CRD/API compatibility for Authentik, External Secrets, Gateway/Envoy, and
  Crossplane resources.

After reconciliation:

```sh
kubectl -n core-prod get pods,pdb,svc,httproute
kubectl -n core-prod get externalsecret,pushsecret
kubectl -n core-prod get backend,backendtrafficpolicy,securitypolicy
kubectl -n core-prod describe externalsecret authentik-database-prod-sync
kubectl -n core-prod logs deploy/aaa-authentik-server
kubectl -n core-prod logs deploy/aaa-authentik-worker
```

Names may vary with the Helm release. First check ExternalSecret readiness and
PostgreSQL connectivity, then Authentik migrations/server readiness, worker
health, outpost token validity, Gateway routing, and finally external DNS.

## Change safety and recovery

- AAA is a shared login dependency. Preserve an Authentik admin or break-glass
  account before changing database credentials, secret keys, OAuth signing
  certificates, routes, or authorization policy.
- Changing `AUTHENTIK_SECRET_KEY`, the database, or signing material can
  invalidate sessions or make encrypted state unusable.
- Verify email and service credentials after a hub change or Vault rotation.
- Roll server replicas gradually and confirm worker migration completion
  before declaring an upgrade healthy.
- Test LDAP, LDAPS, RADIUS, proxy outpost, browser login, token issuance, and
  an application callback independently.
- Removing a peer should not remove the last healthy identity backend; adding
  one should not route users to an unready or inconsistent instance.
- The ApplicationSet preserves resources on generated Application deletion.
  Inspect Argo CD and Kubernetes ownership before expecting deletion to clean
  up Secrets, database state, or identity objects.

Record the running Authentik version, database backup/recovery point, healthy
replicas, ExternalSecret status, and a tested login path before upgrades.
