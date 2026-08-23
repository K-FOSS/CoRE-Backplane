# Development stack

This chart deploys CoRE's shared software-development services. It combines
large upstream charts for GitLab, Harbor, Forgejo, Artifact Hub, Renovate, and
Hoppscotch with local resources for Eclipse Che, MQTTX, CRD documentation,
identity provisioning, Vault-backed secrets, Gateway API routes, and
Crossplane Terraform automation.

This is a platform-specific integration chart, not a portable collection of
upstream defaults. It assumes CoRE's domains, shared PostgreSQL, object
storage, cache services, Authentik/LDAP, Vault hierarchy, Gateway, and
Crossplane APIs.

## Fleet ownership

[`Apps/Development/DevelopmentStack.yaml`](../Apps/Development/DevelopmentStack.yaml)
is the fleet entry point. It selects production clusters and injects
cluster-specific feature flags and endpoints through the Lovely plugin. The
checked-in [`values.yaml`](values.yaml) provides common configuration and
standalone defaults; the ApplicationSet merge determines what actually runs
on each cluster.

Current fleet intent:

| Cluster | GitLab | Harbor | Forgejo | Che | Artifact Hub | CRD docs | MQTTX |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `core-dc1-talos-prod` | Off | On | On | Off | Off | Off | Off |
| `core-home1-talos-prod` | On | On | On | On | Off | Off | Off |
| `dc1-k3s-node1` | On | Off | Off | Off | Off | Off | Off |

Hoppscotch and Renovate are not overridden by the ApplicationSet. Their
checked-in values therefore apply: Hoppscotch is enabled and Renovate is
disabled. The ApplicationSet sets `hub: false` for every current target, so
hub-only credential producers do not render.

Generated Applications use server-side apply, respect configured ignore
differences, retain three revisions, and are preserved when removed from the
ApplicationSet. Do not assume removing a target or component flag deletes its
stateful data.

## Render pipeline

Lovely merges Helm and Kustomize inputs:

```text
Chart.yaml + values.yaml + LOVELY_HELM_MERGE
  -> enabled upstream subcharts
  -> local templates and BJW-S common resources
  -> kustomization.yaml + LOVELY_KUSTOMIZE_MERGE
  -> final manifests
```

The Kustomize merge currently patches the Hoppscotch Service and Deployment:
it fixes the target port, container port, startup probe, revision history, and
token/origin environment variables. A Helm-only render does not include these
production patches.

## Components

| Component | Enable value | Responsibility |
| --- | --- | --- |
| GitLab CE | `gitlab.enabled` | Git hosting, projects, CI application services, Gitaly/Praefect, KAS, and toolbox operations. |
| Harbor | `harbor.enabled` | OCI registry, external object storage/database/cache integration, LDAP authentication, and public pull-through caches. |
| Forgejo | `forgejo.enabled` | Site-local lightweight Git hosting backed by local PostgreSQL, Dragonfly, and persistent repository storage. |
| Eclipse Che | `che.enabled` | Browser IDE and per-user DevWorkspaces backed by persistent storage. |
| Artifact Hub | `artifact-hub.enabled` | Internal artifact/catalog service with external PostgreSQL and OIDC. |
| Hoppscotch | `hoppscotch.enabled` | API development client exposed at `rest.writemy.codes`. |
| Renovate | `renovate.enabled` | Scheduled dependency update discovery against GitLab. |
| MQTTX | `mqttx.enabled` | Lightweight MQTT web client generated through the BJW-S common chart. |
| CRD docs | `crddocs.enabled` | CRD documentation workload and optional identity. |

The upstream chart dependencies are declared in [`Chart.yaml`](Chart.yaml).
GitLab, Harbor, Forgejo, Artifact Hub, Renovate, and Hoppscotch are conditional
dependencies; the BJW-S common chart is always required.

## Shared prerequisites

- Argo CD with the Lovely config-management plugin.
- External Secrets with `mainvault-core` and `corevault-rootsecrets`
  ClusterSecretStores; PushSecret support is required for hub workflows.
- The `mylogin.space/v1alpha1` User API and its database/S3/identity
  compositions.
- Gateway API and the shared `main-gw` Gateway.
- ExternalDNS and the platform's public/private service-label controllers.
- External PostgreSQL, object storage, and cache endpoints referenced by the
  enabled products.
- Authentik OIDC and LDAP providers with matching client/outpost credentials.
- Crossplane's Terraform provider and Harbor provider support for Harbor
  post-configuration.
- Prometheus Operator CRDs where upstream ServiceMonitors are enabled.
- Eclipse Che Operator, DevWorkspace Operator, suitable StorageClasses, and
  the `eclipse-che` namespace when Che is enabled.

Several local templates hardcode production domains, namespaces, Vault paths,
Gateway names, and service names. Changing top-level `domain` or `gateway`
values does not replace every hardcoded reference; inspect the final render.

## Top-level values

| Value | Meaning |
| --- | --- |
| `hub` | Selects hub-only identity generation and secret publication. |
| `env` | Environment suffix/label used by local resources. |
| `domain` | Base development domain, notably used by Che. |
| `cluster.name`, `cluster.domain` | Cluster identity and service DNS suffix. |
| `datacenter`, `region` | Build cluster-qualified DNS names. |
| `gateway` | Intended shared Gateway configuration; some templates currently use fixed values instead. |
| `artifact-hub`, `gitlab`, `harbor`, `forgejo`, `renovate`, `hoppscotch` | Values passed to the corresponding upstream charts. |
| `che`, `mqttx`, `crddocs` | Feature flags for local templates. |

Feature flags control both their conditional dependency and most associated
local resources. Render the disabled case before assuming it is empty; local
resources and Kustomize patches can have separate conditions or name
assumptions.

## GitLab

GitLab uses the upstream GitLab chart in Community Edition mode. Its bundled
ingress, cert-manager, PostgreSQL, cache chart, registry, Prometheus, and
runner are disabled in favor of platform services or intentionally disabled
features.

### External dependencies

- PostgreSQL uses `psql-int.mylogin.space`, with configured replica/load
  balancing hosts and the `gitlab-user` password Secret.
- The GitLab application cache points to the configured external cache host.
- LDAP authentication uses Authentik LDAP and credentials from `gitlab-user`.
- OIDC configuration is rendered into `gitlab-oidc-prod`.
- SMTP uses the shared mail service and credentials from `gitlab-user`.
- KAS, Rails, Workhorse, Shell, runner cache, backups, and S3 connection
  details come from dedicated Kubernetes Secrets.
- Gitaly is enabled and Praefect is configured for repository coordination
  with its own database identity.

The local `User` resources request the GitLab database identity, LDAP service
membership, and S3 buckets. ExternalSecrets map Vault data into the exact
Secret formats required by the upstream chart.

| Secret | Purpose |
| --- | --- |
| `gitlab-user` | Database, LDAP, and SMTP service identity generated by the User composition. |
| `gl-praefect-creds` | Praefect database credentials. |
| `gitlab-oidc-prod` | Authentik OpenID Connect provider configuration. |
| `gitlab-prod-rails-secret` | Rails encryption/signing material. |
| `gitlab-kas-prod` | KAS shared secret. |
| `gitlab-workhorse-prod` | Workhorse shared secret. |
| `gitlab-shell-prod` | GitLab Shell shared secret. |
| `gitlab-s3-prod` | S3 connection configuration. |
| `gitlab-s3-backups-prod` | Toolbox backup client configuration. |
| `gitlab-s3-runner` | Runner cache S3 credentials. |

The GitLab HTTPRoute exposes the configured web hostname through Gateway API.
Review its hostname, backend Service/port, timeout, and TLS termination
together with `gitlab.global.hosts`.

### GitLab change safety

GitLab upgrades can run database migrations and coordinate Rails, Sidekiq,
Gitaly, and Praefect state. Before upgrading:

1. Confirm a recent database backup and repository backup.
2. Read the upstream chart and GitLab version upgrade paths.
3. Verify PostgreSQL/Praefect compatibility and connectivity.
4. Check all ExternalSecrets and generated User resources.
5. Render migration hooks, replica changes, PDBs, and resource requests.
6. Test web login, clone over HTTPS/SSH, push, job execution, KAS, and backup
   restore after reconciliation.

Do not rotate Rails, Workhorse, Shell, KAS, or OIDC signing material as an
incidental chart cleanup.

## Harbor

Harbor uses an external PostgreSQL database, external cache service, and
S3-compatible image/chart storage. It is exposed through the
`registry.<cluster>.<datacenter>.<region>.writemy.codes` HTTPRoute, whose rules
direct Docker API and token paths to Harbor core and ordinary UI paths to the
portal.

The ApplicationSet injects per-cluster `psql-local`, Dragonfly, S3, LDAP, and
public endpoints plus a cluster-qualified Helm release name. Every enabled
site has its own `harbor-<cluster>` PostgreSQL role and database.

### Harbor credentials and post-configuration

Local ExternalSecrets create Harbor's general, core, registry, job-service,
S3, and Redis configuration credentials. Every enabled site creates a
`harbor-user` claim with PostgreSQL enabled; the claim provisions the local
role/database and writes the stable namespace-local `harbor-user` Secret. The
former hub PushSecret and non-hub shared credential pull are no longer part of
the Harbor lifecycle. Existing `Harbor/User` and `Harbor/Database` values in
Vault are not deleted by this change; retire them separately only after every
site-local claim and rollback path has been verified.

Harbor uses the target site's TLS-enabled `dragonfly-core` endpoint. Its
logical allocations are recorded in
[`Storage/Dragonfly/CoRE/README.md`](../Storage/Dragonfly/CoRE/README.md).
Harbor chart 1.18.2 cannot render `redis.external.existingSecret` offline
because it uses Helm `lookup`. The `harbor-redis-config` ExternalSecret and
ApplicationSet Kustomize patches therefore supply runtime URLs and the job
service config from a Secret, without putting the password in rendered
ConfigMaps. See the upstream [Harbor chart source](https://github.com/goharbor/harbor-helm/tree/v1.18.2)
and [high-availability guidance](https://github.com/goharbor/harbor-helm/blob/v1.18.2/docs/High%20Availability.md).

A Terraform `ProviderConfig` uses the Harbor admin credential. Two Workspaces
then:

- set Harbor authentication to Authentik LDAP; and
- create public proxy-cache projects for Docker Hub, GHCR, registry.k8s.io,
  GCR, and Quay.

Terraform state is stored in Kubernetes Secrets. Confirm ProviderConfig
readiness and Workspace state before changing provider versions, registry
names, or authentication mode.

### Harbor change safety

- Back up the Harbor database and verify S3 versioning/retention before an
  upgrade.
- Keep the admin credential, internal component secrets, and object-storage
  keys stable.
- Test login, push, pull, deletion/garbage collection, vulnerability scanning,
  and every proxy cache.
- Confirm `externalURL` and Gateway routing; an incorrect token-service URL
  breaks registry clients even when the portal loads.
- Coordinate changes across both enabled Harbor clusters to avoid
  inconsistent public routing or replication behavior.
- Changing the desired database endpoint does not copy the existing Harbor
  database. Before reconciliation, quiesce writes, back up and restore the
  existing database into each intended `psql-local` database, then validate
  schema migrations and object-store consistency. Roll back to the former
  endpoint only while its database remains a valid point-in-time source.

## Forgejo

Forgejo is deployed independently at both infrastructure sites through the
official [Forgejo Helm chart](https://code.forgejo.org/forgejo-helm/forgejo-helm/src/tag/v16.2.2)
and a digest-pinned Forgejo 14.0.4 rootless image. Each site uses
`forgejo.<cluster>.<datacenter>.<region>.writemy.codes`, one replica, and a
retained 50 GiB persistent volume for repositories and application data.
External SSH routing is not configured; HTTPS clone and web traffic use the
Gateway API HTTPRoute.

The site-local `forgejo-user` claim provisions the matching PostgreSQL role
and database on `psql-local` and publishes the password in the stable
`forgejo-user` Secret. Queue, cache, and session state use Dragonfly databases
`90`, `91`, and `92`; Kubernetes expands the namespace-local Dragonfly password
into Forgejo's runtime environment before `app.ini` is generated. A
CreatedOnce External Secrets password generator creates the local break-glass
`forgejo-admin` Secret. Consult Forgejo's [database preparation guide](https://forgejo.org/docs/latest/admin/installation/database-preparation/)
and [configuration reference](https://forgejo.org/docs/latest/admin/config-cheat-sheet/).

The PostgreSQL database and persistent repository volume form one recovery
unit. Back them up consistently; Dragonfly queue/cache/session data is
disposable, but losing queued work can interrupt asynchronous operations.
Removing the `User` claim or Application does not prove the orphaned database
or retained PVC was deleted. Verify the claim/composite, provider resources,
database grants, PVC, HTTPRoute, login, repository creation, HTTPS clone,
push, issue updates, and background jobs after reconciliation.

## Eclipse Che

The local Che templates create a `CheCluster` named `devspaces`, Gateway API
route, GitHub/GitLab SCM OAuth Secrets, autoscalers for Che components, and a
profile ConfigMap for a user workspace namespace.

Key behavior:

- workspaces use a per-user PVC strategy and persist the user home directory;
- namespaces are auto-provisioned as `<username>-che`;
- the default editor is Che Code with the configured universal developer
  image pulled through Harbor;
- running workspaces idle after 12 hours and inactive workspaces after 6
  hours;
- each user may run four workspaces, with no configured total-workspace cap;
- startup may take up to 30 minutes;
- workspace containers are currently configured with privileged security
  context; and
- access is limited to the Authentik `Developers` group.

Che depends on a wildcard/appropriate TLS Secret, the configured Authentik
client, SCM OAuth clients, the Che/DevWorkspace operators, cluster capacity,
and dynamic storage. Validate the `CheCluster` status before troubleshooting
generated Deployments.

The profile ConfigMap is currently fixed to namespace `kjones-che` and exposes
an alias that reads Argo CD's initial admin password. Treat this as
operator-specific and security-sensitive; it is not a general profile for all
users.

Before a Che change, test OIDC login, workspace creation, PVC attachment,
image pull, SCM authorization, editor startup, idling, restart, and deletion.
Avoid changing workspace storage strategy without a migration plan.

## Artifact Hub

Artifact Hub is backed by external PostgreSQL and uses Authentik OIDC. A local
`User` requests its database/service identity and a PushSecret publishes the
generated connection details to Vault. The upstream scanner is disabled,
while tracking and database migration remain part of the deployment.

The Artifact Hub route and application configuration currently use
`artifacthub.int.mylogin.space`. Cookie/CSRF example defaults in
`values.yaml` are unsafe for production unless replaced by Lovely/Vault
material. Do not enable Artifact Hub until those keys, OIDC credentials,
database credentials, Docker credentials, and SMTP settings are verified.

Artifact Hub is disabled on all current fleet targets.

## Hoppscotch

Hoppscotch is enabled by checked-in defaults and exposed at
`rest.writemy.codes`. An ExternalSecret reads JWT, database encryption,
session, and GitHub OAuth values from Vault. The ApplicationSet's Kustomize
patch changes its runtime port and supplies access/refresh token validity,
allowed origin, and subpath settings.

Because the patch targets names derived from the cluster-specific Helm release,
validate that both patch targets match before syncing. Test API/UI loading,
authentication callbacks, database migrations, WebSocket behavior, and
secret rotation.

## Renovate, MQTTX, and CRD docs

Renovate is disabled by default. When enabled, its ExternalSecret creates a
GitLab configuration from `corevault-rootsecrets`. The checked-in Renovate
configuration has `dryRun: true`, `printConfig: true`, autodiscovery enabled,
and no explicit repository list. Review logs for credential or repository
metadata exposure before enabling `printConfig`.

MQTTX is a simple web Deployment and ClusterIP Service using a moving
`latest` image tag. Pin the tag before treating it as reproducible.

CRD docs creates a documentation workload through the BJW-S common chart.
When both `crddocs.enabled` and `crddocs.hub` are true, it also creates a
platform User resource. Both MQTTX and CRD docs are disabled by current fleet
overrides.

## Rendering and validation

The dependency charts are not committed under `Development/charts`. Build
them before local Helm validation:

```sh
helm dependency build Development
helm lint Development
helm template development Development \
  --namespace core-prod > /tmp/development.yaml
```

Dependency constraints using `>=` are not reproducible without a committed
lock file. Inspect the selected versions after building dependencies and avoid
updating them accidentally during unrelated work.

A Helm-only render is incomplete for production because it omits the
ApplicationSet's Kustomize merge. To reproduce a target cluster:

1. Copy its feature flags and cluster metadata from
   `Apps/Development/DevelopmentStack.yaml`.
2. Include the injected Harbor and Forgejo database, Dragonfly, route, and
   fullname overrides, plus Harbor's S3 endpoint.
3. Apply the Hoppscotch Kustomize patches to the Helm output.
4. Compare the resulting resource names with the patch targets and Secret
   references.

Useful manifest checks:

```sh
yq 'select(.kind == "ExternalSecret" or .kind == "PushSecret" or
  .kind == "User") | [.kind, .metadata.namespace, .metadata.name]' \
  /tmp/development.yaml
yq 'select(.kind == "HTTPRoute") |
  {name: .metadata.name, namespace: .metadata.namespace,
   parents: .spec.parentRefs, hosts: .spec.hostnames}' \
  /tmp/development.yaml
yq 'select(.kind == "StatefulSet" or .kind == "Deployment") |
  [.kind, .metadata.name, .spec.replicas]' /tmp/development.yaml
```

After reconciliation:

```sh
kubectl -n core-prod get pods,pdb,jobs
kubectl -n core-prod get externalsecret,pushsecret
kubectl -n core-prod get user
kubectl -n core-prod get httproute
kubectl -n core-prod get workspace,providerconfig
kubectl -n eclipse-che get checluster,devworkspace
```

Use the actual Application destination namespace and release-derived names
for each cluster.

## Troubleshooting order

For a failed component:

1. Check whether its final merged feature flag is enabled.
2. Check Lovely manifest-generation and Kustomize patch errors.
3. Check CRDs and operators required by local custom resources.
4. Check User/ExternalSecret/PushSecret readiness without printing secret
   data.
5. Check database, object storage, cache, LDAP/OIDC, DNS, and Gateway
   reachability.
6. Check migration or initialization Jobs.
7. Check workload scheduling, PVCs, probes, and application logs.
8. Test the internal Service before the public route.

This order separates desired-state generation failures from secret,
infrastructure, migration, workload, and ingress failures.

## General change safety

- GitLab and Harbor contain durable, shared data. A successful Helm render
  does not validate database migrations, repository/object integrity, or
  restore procedures.
- Back up databases and object storage, and test restoration before major
  upgrades.
- Avoid changing shared identity, encryption, signing, or component secrets
  during routine version bumps.
- Verify the fleet matrix so a feature is not unintentionally enabled on every
  selected cluster by a checked-in default.
- Review every public hostname, service label, and Gateway parent; development
  tools often expose source code, credentials, build artifacts, or privileged
  workspaces.
- Preserve administrator and `kubectl` recovery paths while changing OIDC,
  LDAP, Gateway routes, or Crossplane-managed credentials.
- Check upstream chart release notes for each enabled dependency independently.
  This umbrella chart can upgrade products with unrelated migration and
  rollback constraints.
