# Argo CD chart

This directory installs the Argo CD control plane used to reconcile CoRE
Backplane. It combines the upstream `argo-cd` chart, the
`capi2argo-cluster-operator` chart, local Gateway API and External Secrets
resources, Authentik OIDC provisioning, and a Kustomize patch that adds the
Lovely config-management plugin to the repository server.

This is a self-management path: an existing Argo CD instance applies an
Application that upgrades Argo CD itself. Treat rendering, secret
availability, repository-server changes, and rollback access as control-plane
operations.

## Fleet bootstrap and ownership

Three manifests under `Apps/Infra/ArgoCD` form the fleet-level entry point:

- [`ArgoCDProject.yaml`](../Apps/Infra/ArgoCD/ArgoCDProject.yaml) creates the
  permissive `core` AppProject used by platform Applications.
- [`ArgoCDApplications.yaml`](../Apps/Infra/ArgoCD/ArgoCDApplications.yaml)
  deploys the recursive `Apps/` directory to selected infrastructure clusters.
- [`ArogCDProd.yaml`](../Apps/Infra/ArgoCD/ArogCDProd.yaml) deploys this chart
  to selected bare-metal infrastructure clusters and injects cluster-specific
  sizing, DNS, Gateway, Redis, and service-discovery values.

The production ApplicationSet targets `HEAD`, uses the Lovely plugin, enables
server-side apply, and preserves resources when generated Applications are
deleted. Its merged values are authoritative; [`values.yaml`](values.yaml)
contains common defaults rather than the complete production configuration.

## Render pipeline

Lovely processes both Helm and Kustomize inputs:

```text
Chart.yaml + values.yaml + LOVELY_HELM_MERGE
  -> upstream Argo CD and cluster-registration subcharts
  -> local templates
  -> kustomization.yaml + LOVELY_KUSTOMIZE_MERGE
  -> repo-server Lovely sidecar and argocd-secret type patch
```

[`argocd-lovely-plugin.yaml`](argocd-lovely-plugin.yaml) is a strategic merge
patch for `argocd-repo-server`. It adds a `lovely-plugin` sidecar, a
memory-backed temporary volume, and access to the repo-server plugin sockets.
The sidecar reads Vault configuration from `argocd-vault-config`.

The ApplicationSet also changes `argocd-secret` to Crossplane's connection
secret type because the Authentik Terraform Workspace writes its connection
details into that Secret.

## Components

| Component | Responsibility |
| --- | --- |
| Application controller | Reconciles Applications; configured with three replicas and cluster-cache tuning by default. |
| Repository server | Generates manifests and hosts the Lovely sidecar; configured with three replicas and bounded in-memory work volumes. |
| API server | Serves the UI/API through Gateway API HTTPRoute and GRPCRoute resources. |
| ApplicationSet controller | Generates fleet Applications; applications in any namespace are enabled. |
| Notifications controller | Enabled by the upstream chart values. |
| External Redis | Dragonfly endpoint injected by the ApplicationSet; in-chart Redis and Redis HA are disabled. |
| CAPI-to-Argo cluster operator | Registers Cluster API-managed clusters with Argo CD. |
| Authentik Workspace | Creates the Argo CD OAuth provider/application and writes OIDC outputs to `argocd-secret`. |
| Lovely plugin | Renders Helm/Kustomize content and resolves Vault-backed placeholders. |

Dex and OpenShift integration are disabled. Argo CD's local admin account is
currently enabled, while Authentik is the configured OIDC provider.

## Secret and identity chain

The chart depends on three separate credential flows:

1. `argocd-redis` reads `Storage/DragonFly/CoRE/Creds` from the
   `corevault-rootsecrets` ClusterSecretStore and creates
   `argocd-redis-password`.
2. `argocdvault-secret-sync` reads the Vault token and creates
   `argocd-vault-config`, which is loaded by the Lovely sidecar.
3. When `authentik.autoconfigure` is true, a Crossplane Terraform Workspace
   uses the configured Authentik provider, creates the OAuth provider and
   application, and writes `OIDC_CLIENT_ID`, `OIDC_CLIENT_SECRET`,
   `OIDC_ISSUER_URL`, and related outputs to `argocd-secret`.

The upstream Argo CD chart expands `$OIDC_*` references in `oidc.config` from
keys in `argocd-secret`. A healthy Argo CD workload therefore does not prove
that OIDC, Redis, or plugin generation is healthy; check each Secret producer
and consumer separately.

Required external APIs and controllers include External Secrets, the
`corevault-rootsecrets` ClusterSecretStore, Crossplane's Terraform provider
and its Authentik ProviderConfig, Gateway API, Envoy Gateway policy CRDs,
ExternalDNS/Gateway infrastructure, and the CAPI cluster-registration CRDs.

## Important values

### Platform values

| Value | Meaning |
| --- | --- |
| `cluster.name`, `cluster.domain` | Cluster identity and service DNS suffix used by local templates. |
| `datacenter`, `region`, `domain` | Construct the public Argo CD callback and service names. |
| `gateway` | Shared Gateway identity. Some local route fields remain hardcoded; inspect rendered routes. |
| `authentik.autoconfigure` | Creates the Authentik OAuth application through a Terraform Workspace. |
| `terraform.authentikProvider` | ProviderConfig used by that Workspace. |
| `tenant.name`, `oidc.indexKey`, `oidc.authentik.urlBase` | Form the Authentik application slug and issuer URL. |
| `argo-cd` | Values passed directly to the upstream Argo CD chart. |

`oidc.groups` and `oidc.scopes` are present as platform values, but the current
local Workspace uses a fixed managed-scope set and the RBAC policy is defined
under `argo-cd.configs.rbac`. Do not assume changing those top-level lists
changes the generated provider or RBAC policy.

### Operationally significant upstream values

- `argo-cd.configs.cm` controls the public URL, OIDC configuration, resource
  tracking, ignored differences, ignored update fields, and exclusions.
- `argo-cd.configs.rbac.policy.csv` grants Argo CD roles to Authentik groups.
  The defaults grant `role:admin` to both Developers and Server Admins.
- `argo-cd.configs.params` controls controller/repo-server concurrency,
  reconciliation, cache behavior, application namespaces, and API-server
  behavior.
- `argo-cd.controller`, `repoServer`, `server`, and `applicationSet` control
  replicas, PodDisruptionBudgets, resources, affinity, metrics, and arguments.
- `argo-cd.externalRedis` is injected by the ApplicationSet and refers to the
  externally synchronized password Secret.

Resource customizations suppress known controller-written or status-only
differences. Every new ignore rule expands the set of drift Argo CD will not
report; review those changes as policy changes, not cosmetic tuning.

## Networking

The upstream chart exposes the Argo CD server through HTTPRoute and GRPCRoute
objects whose hostname and parent Gateway are injected per cluster. The local
`argocd-webhook-route` exposes only `/api/webhook`, and
`BackendTrafficPolicy` enables compression for the main HTTP route.

The local webhook route currently contains fixed Gateway, hostname, and
backend-port values. Verify it against the cluster-specific upstream route
before relying on it. Argo CD runs with `server.insecure: true`, so TLS is
expected to terminate at the Gateway.

## Rendering and validation

Update chart dependencies only when intentionally changing locked dependency
versions:

```sh
helm dependency build ArgoCD
```

Render the Helm layer:

```sh
helm lint ArgoCD
helm template argocd ArgoCD --namespace argocd \
  > /tmp/argocd-helm.yaml
```

A Helm-only render does not apply the Kustomize patch. The closest production
render must also supply the `LOVELY_HELM_MERGE` and
`LOVELY_KUSTOMIZE_MERGE` values from `ArogCDProd.yaml` through the Lovely
plugin. At minimum, inspect:

- container images, replicas, PDBs, resource limits, and affinity;
- the repo-server sidecar, volumes, and `argocd-vault-config` reference;
- Redis endpoint, TLS flags, and password Secret;
- HTTPRoute/GRPCRoute hosts and parent Gateway references;
- OIDC issuer, callback URL, Workspace status, and `argocd-secret` keys;
- RBAC policy, AppProject scope, resource exclusions, and ignore rules; and
- CRDs/API versions required by every rendered custom resource.

After reconciliation:

```sh
kubectl -n argocd get pods,pdb,httproute,grpcroute
kubectl -n argocd get externalsecret
kubectl -n argocd get workspace
kubectl -n argocd get applications,applicationsets
kubectl -n argocd describe deploy argocd-repo-server
```

Use `argocd app get <application>` and controller/repo-server logs to
distinguish reconciliation failures from manifest-generation failures.

## Safe changes and recovery

- Preserve an authenticated `kubectl` path before changing OIDC, RBAC, routes,
  Redis, repository generation, or the Argo CD server.
- Keep the local admin recovery credential available until OIDC login and RBAC
  are verified. Disable local admin only with a tested break-glass procedure.
- A broken Lovely sidecar can prevent every Lovely-managed Application from
  generating manifests. Test representative repositories before rollout.
- A Redis credential/TLS mismatch can affect all controllers at once.
- Respect PDBs and verify spare node capacity before changing replica
  placement.
- Changes to the recursive `Apps/` ApplicationSet or permissive `core`
  AppProject have fleet-wide scope.
- Do not delete the Argo CD Application or namespace as a rollback mechanism.
  Reapply a known-good rendered control plane from outside Argo CD if
  self-management is unable to recover.

Record the current Argo CD version, rendered manifests, healthy replica count,
Application status, and a known-good commit before an upgrade.
