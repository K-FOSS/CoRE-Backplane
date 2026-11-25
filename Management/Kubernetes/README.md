# K-FOSS/CoRE-Backplane Kubernetes Management

This chart deploys Headlamp `0.46.0` together with Inspektor Gadget for cluster
management, debugging, and introspection. The Headlamp dependency is pinned in
[`Chart.yaml`](Chart.yaml); see the [Headlamp 0.46.0 release notes](https://github.com/kubernetes-sigs/headlamp/releases/tag/0.46.0)
and [upstream Helm chart](https://github.com/kubernetes-sigs/headlamp/tree/headlamp-helm-0.46.0/charts/headlamp)
for the supported chart and application behavior. The Headlamp image is pinned
to its upstream OCI digest in [`values.yaml`](values.yaml).

## Fleet deployment

The chart is owned by the
[`core-backplane-management-k8s` ApplicationSet](../../Apps/Management/Headlamp.yaml)
in the `argocd` namespace. Production changes should be made through this Git
path and reconciled with Argo CD rather than applying the chart directly.

The ApplicationSet uses Argo CD's
[cluster generator](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-Cluster/)
and selects every registered cluster with this label:

```text
mylogin.space/tenant=core.mylogin.space
```

There is no environment, site, or compute-type filter. Adding that tenant
label to an Argo CD cluster Secret therefore opts the cluster into this
management stack. Removing the label stops the ApplicationSet from generating
its Application.

For every selected cluster, the ApplicationSet creates an Application named:

```text
<argocd-cluster-name>-management-k8s
```

The generated Application:

- belongs to the Argo CD `core` project;
- reads `Management/Kubernetes` from
  the canonical YVR Forgejo repository
  `https://slop.writemy.codes/CoRE/CoRE-Backplane.git` at the moving `HEAD`
  revision;
- renders through the
  [`argocd-lovely-plugin`](https://github.com/crumbhole/lovely-vault-plugin#readme)
  [repository](https://github.com/crumbhole/lovely-vault-plugin) as an Argo CD
  [config-management plugin](https://argo-cd.readthedocs.io/en/stable/operator-manual/config-management-plugins/);
- deploys to the selected cluster's API server;
- derives the destination namespace as `core-<environment>`; and
- enables `RespectIgnoreDifferences=true` during sync.

The ApplicationSet does not configure automated sync,
`preserveResourcesOnDeletion`, `CreateNamespace`, or server-side apply. A
generated Application must be synced through the repository's normal Argo CD
workflow. Before changing cluster selection or deleting the ApplicationSet,
inspect Argo CD's deletion propagation and all downstream resources; this
ApplicationSet does not promise to preserve Headlamp, the Gadget DaemonSet, or
the Terraform Workspace when a generated Application is removed.

### Injected values

Cluster metadata is read from the registered Argo CD cluster and passed to
Lovely through `LOVELY_HELM_MERGE`:

| ApplicationSet source | Merged chart value | Usage in this chart |
| --- | --- | --- |
| Argo CD cluster name | `cluster.name` | Public hostname and Authentik names/client ID. |
| `cluster.kubernetes.io/domain` | `cluster.domain` | Used to form Headlamp's in-cluster Alloy OTLP endpoint. |
| `resolvemy.host/env` | `env` | Determines the destination namespace as well; not currently used by a chart template. |
| `resolvemy.host/dc` | `datacenter` | Public hostname and Authentik naming/grouping. |
| `topology.kubernetes.io/region` | `region` | Authentik provider name, application slug, and client ID. |
| Cluster domain and environment | `headlamp.env` | Enables OTLP/gRPC tracing to `alloy-otlp.core-prod.svc.<cluster-domain>:4317`, with service name/version and 10% sampling. |

The generator also reads `topology.kubernetes.io/zone`, but does not include it
in `LOVELY_HELM_MERGE`; changing the zone label currently has no effect on this
chart. Argo CD
[Go template](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/GoTemplate/)
evaluation uses `missingkey=error`, so every selected cluster must carry all
labels referenced by the generator even when a value is not ultimately
consumed by a template.

The effective deployment flow is:

```text
registered Argo CD cluster labels
  -> core-backplane-management-k8s ApplicationSet
  -> generated <cluster>-management-k8s Application
  -> argocd-lovely-plugin plus LOVELY_HELM_MERGE
  -> this parent Helm chart and pinned dependencies
  -> Headlamp, Inspektor Gadget, Authentik Workspace, route, and RBAC
  -> downstream Terraform/Authentik reconciliation
```

Inspektor Gadget runs its daemon on every Linux node. Its OCI-based tools are
started on demand through the Headlamp plugin or `kubectl gadget`, while
long-running tools are declared under `gadget.config.gadgetConfigMaps`.

The deployment currently runs two continuous Gadget instances on all eligible
nodes: `trace_oomkill` records out-of-memory kill events, and `trace_tcp`
records TCP connect, accept, and close events. Both OCI images are pinned to
the deployed Inspektor Gadget `v0.54.1` release and are verified by the Gadget
operator's configured image-verification policy.

Lovely passes the Helm output through the local `kustomization.yaml`. The
Kustomize patches select resources labeled
`app.kubernetes.io/part-of=inspektor-gadget` and rewrite the Gadget namespaced
resources, plus the Gadget ClusterRoleBinding's service-account subject, from
the Application destination namespace to the dedicated `gadget` namespace.
Headlamp and the other parent-chart resources remain in `core-<environment>`.

The `gadget` Namespace enables Kubernetes
[Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/)
with the `privileged` policy at the `enforce` level, which is required for the
node-inspection DaemonSet. It is annotated with Argo CD sync wave `-1`; Gadget
and the other unannotated resources use the default wave `0`. Argo CD therefore
creates the namespace in an earlier
[sync wave](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
before it applies resources assigned to that namespace.

The KubeVirt plugin uses the Headlamp chart's plugin-manager sidecar. It pins
the plugin-manager CLI to `0.1.1` and the [official Node image](https://github.com/nodejs/docker-node)
to an image digest. The
manager fetches the pinned Artifact Hub package version and verifies its
archive checksum before installing it into the shared plugin volume.
`config.watchPlugins` is enabled so the plugin is visible without recreating
the Headlamp pod. The pod uses `fsGroup: 101` so the non-root plugin manager
and Inspektor Gadget init container can write to that shared volume. The
Inspektor Gadget plugin remains installed from its digest-pinned container
image because its init container rewrites the `/externalproxy` endpoint used
by the in-cluster plugin. See the pinned
[Headlamp chart plugin-manager
implementation](https://github.com/kubernetes-sigs/headlamp/blob/headlamp-helm-0.46.0/charts/headlamp/templates/deployment.yaml)
and [plugin-manager documentation](https://headlamp.dev/docs/latest/installation/plugins/).

- [Inspektor Gadget plugin README](https://github.com/inspektor-gadget/headlamp-plugin#readme)
  ([repository](https://github.com/inspektor-gadget/headlamp-plugin)) — pinned
  to `0.1.0-beta.3`, the latest published version, with its published image
  digest.
- [KubeVirt plugin README](https://github.com/naval-group/headlamp-kubevirt#readme)
  ([repository](https://github.com/naval-group/headlamp-kubevirt),
  [v0.3.1 release](https://github.com/naval-group/headlamp-kubevirt/releases/tag/v0.3.1)) — updated
  to `0.3.1` for VM lifecycle, console, and KubeVirt resource views. Its
  release notes currently list support through KubeVirt v1.9; validate the
  plugin against the deployed v1.10 API before relying on version-specific
  feature-gate or VM actions.

The public Headlamp HTTPRoute uses Envoy Gateway's v1.10
[OIDC SecurityPolicy](https://gateway.envoyproxy.io/v1.10/tasks/security/oidc/)
with the Authentik provider created by this chart. The policy forwards the raw
ID token in `X-Forwarded-Id-Token`; Headlamp's
[identity-aware proxy mode](https://headlamp.dev/docs/v0.46.0/installation/in-cluster/identity-aware-proxy/)
uses that token for Kubernetes API requests and skips its login screen. The
route overwrites `X-Forwarded-User` with a fixed authenticated label because
Envoy Gateway does not expose OIDC identity claims as backend headers. This
label identifies the proxy-authenticated UI session; Kubernetes RBAC still
uses the individual forwarded ID token.

The `headlamp-gateway-only` NetworkPolicy admits the Headlamp port only from
Envoy proxy pods for the `main-gw` Gateway. This restriction is required because
Headlamp trusts its proxy headers. The chart also publishes the same generated
client secret under Envoy Gateway's required `client-secret` key in the
existing `core-headlamp-oidc` connection Secret. Both this policy and the
Headlamp chart consume that Secret without copying credential values into
manifests.

The HTTPRoute bounds regular requests to 60 seconds, with 30 seconds for each
backend request. Its WebSocket rule disables those whole-response deadlines so
interactive sessions can remain connected; the Headlamp Service declares
`kubernetes.io/ws` for upstream upgrade handling. It does not configure
automatic retries because Headlamp sends mutating Kubernetes operations and
replaying a request after an ambiguous backend failure could duplicate an
operation. See Envoy Gateway's [HTTP timeout](https://gateway.envoyproxy.io/v1.10/tasks/traffic/http-timeouts/)
and [retry](https://gateway.envoyproxy.io/v1.10/tasks/traffic/retry/)
documentation.

Headlamp pods carry the `logs: 'loki-myloginspace'` label so node-local Alloy
collects their container logs through the shared [Loki pipeline](../../Observability/Logs/README.md).
The [Collectors stack](../../Observability/Collectors/README.md) enables pod-log
collection only on its configured clusters; the label does not enable the
collector or grant it access to other workloads.

### Headlamp tracing

The ApplicationSet enables Headlamp backend tracing with
`HEADLAMP_CONFIG_TRACING_ENABLED`, names the service `headlamp`, sets version
`v0.46.0`, and samples 10% of traces. Headlamp sends OTLP/gRPC to the cluster's
`alloy-otlp` Service; central Alloy adds Kubernetes resource attributes and the
`core` tenant header before exporting to Tempo. The endpoint uses the cluster
domain supplied by the ApplicationSet. See Headlamp's
[telemetry guide](https://headlamp.dev/docs/latest/development/telemetry/),
[pinned v0.46.0 telemetry configuration](https://github.com/kubernetes-sigs/headlamp/blob/v0.46.0/backend/pkg/config/config.go),
and the [Collectors trace pipeline](../../Observability/Collectors/README.md).

## Automated Authentik application

The chart creates and maintains Headlamp's Authentik OAuth2/OIDC application
automatically. No client ID or client secret is stored in this repository.
Instead, the chart renders an Upbound Terraform `Workspace` containing an
inline Authentik module. The Workspace reconciler applies that module and
writes its sensitive outputs to a Kubernetes Secret consumed by Headlamp.

### Prerequisites

Before installing this chart, the cluster and Authentik instance must provide:

- the `tf.upbound.io/v1beta1` `Workspace` CRD and its controller;
- a Terraform `ProviderConfig` named `authentik`, configured to reach the
  intended Authentik instance;
- Authentik authorization and invalidation flows with the slugs used by the
  template;
- an Authentik certificate/key pair named `tls` for signing OIDC tokens;
- the managed `openid`, `profile`, `email`, and `offline_access` scope
  mappings;
- the `corevault-rootsecrets` ClusterSecretStore with permission to write the
  Headlamp client ID path; and
- every Authentik group listed in `oauth.groups`; and
- the Gateway API CRDs and the Gateway referenced by the `gateway` values.

The Workspace, generated Secret, and Headlamp release must share the Helm
release namespace. The Workspace refers to the cluster-scoped ProviderConfig
by name.

### Reconciliation process

1. Helm renders `templates/HeadlampAuthentik.yaml` as a Workspace named
   `headlamp-sso`.
2. The Terraform Workspace controller loads the `authentik` ProviderConfig and
   applies the inline module.
3. The module looks up the configured Authentik flows, scope mappings,
   certificate, and access groups.
4. Terraform generates a 128-character client secret and creates an Authentik
   OAuth2 provider. The provider uses a regex redirect URI matching the public
   Headlamp URL.
5. Terraform creates the `Headlamp` Authentik application and links it to the
   OAuth2 provider.
6. For each entry in `oauth.groups`, Terraform creates an application
   entitlement and binds that group to both the entitlement and application.
7. The controller publishes the sensitive Terraform outputs to the
   `core-headlamp-oidc` Secret in the release namespace.
8. The Headlamp subchart reads that existing Secret through
   `headlamp.config.oidc.externalSecret`; `hasScopes: true` tells the 0.46.0
   chart to pass the generated `OIDC_SCOPES` key to Headlamp. Headlamp does not
   generate or own the credentials.
9. `templates/HTTPRoute.yaml` exposes Headlamp through the configured Gateway.
   After login, the OIDC group claim is evaluated by Kubernetes RBAC.
10. `templates/HeadlampOIDCPushSecret.yaml` publishes `OIDC_CLIENT_ID` and
    the Workspace-generated `OIDC_ISSUER_URL` to CoreVault at
    `Operations/Clusters/OIDC/Headlamp/<cluster-name>` for the Talos Cluster
    Composition. The client secret remains in the application cluster's
    `core-headlamp-oidc` Secret.

The target path uses the cluster name injected by the
[`core-backplane-management-k8s` ApplicationSet](../../Apps/Management/Headlamp.yaml).
For the production Talos clusters it is
`Operations/Clusters/OIDC/Headlamp/core-dc1-talos-prod` or
`Operations/Clusters/OIDC/Headlamp/core-home1-talos-prod`. This PushSecret
publishes the client ID and issuer URL, but does not export the client secret.

The generated Secret contains these output keys:

| Key | Purpose |
| --- | --- |
| `OIDC_CLIENT_ID` | Authentik OAuth2 client identifier. |
| `OIDC_CLIENT_SECRET` | Terraform-generated client secret. |
| `OIDC_ISSUER_URL` | Authentik discovery/issuer URL for this application. |
| `OIDC_SCOPES` | Space-delimited scopes requested by Headlamp. |

### Authentik and routing values

| Value | Effect |
| --- | --- |
| `cluster.name` | Included in the client ID, provider name, issuer slug, and public hostname. |
| `datacenter` | Included in Authentik naming, grouping, and the public hostname. |
| `region` | Included in the Authentik provider name, client ID, and application slug. |
| `oauth.indexKey` | Prefix for the client ID and application/issuer slug. |
| `oauth.scopes` | Value written to `OIDC_SCOPES`. Keep it aligned with the managed mappings in the template. |
| `oauth.refreshTokenValidity` | Authentik OAuth2 refresh-token lifetime, using Authentik duration syntax; production is configured for `days=3`. |
| `oauth.groups` | Existing Authentik groups granted access to the application. |
| `oauth.authentik.urlBase` | External Authentik base URL used to construct the issuer URL. |
| `gateway.*` | Parent Gateway and listener used by the Headlamp HTTPRoute. |

With the default values, the identifiers and endpoints are:

- client ID and application slug: `headlamp-yxl-dc1-k8s`;
- issuer URL:
  `https://idp.mylogin.space/application/o/headlamp-yxl-dc1-k8s/`;
- redirect URI pattern:
  `https://headlamp.k8s.dc1.resolvemy.host/.*`; and
- public Headlamp hostname: `headlamp.k8s.dc1.resolvemy.host`.

The hostname in the OAuth2 redirect pattern and HTTPRoute is currently fixed
to the `resolvemy.host` zone by the templates. `cluster.domain` is not used for
the public Headlamp URL.

### Chart templates

| Template | Resources and responsibility |
| --- | --- |
| `templates/HeadlampAuthentik.yaml` | Creates the Terraform Workspace, Authentik provider/application/entitlements, and OIDC connection Secret outputs. |
| `templates/HTTPRoute.yaml` | Routes the public Headlamp hostname to the Headlamp Service through the configured Gateway listener. |
| `templates/SecurityPolicy.yaml` | Requires Authentik OIDC for the Headlamp HTTPRoute and forwards its ID token. |
| `templates/NetworkPolicy.yaml` | Restricts Headlamp ingress to Envoy proxy pods so proxy identity headers cannot be spoofed from other pods. |
| `templates/TempRole.yaml` | Grants the Kubernetes group `Server Admins` the `cluster-admin` ClusterRole. |
| Headlamp dependency | Deploys Headlamp and consumes `core-headlamp-oidc`; also installs the configured UI plugins. |
| Gadget dependency | Deploys the Inspektor Gadget node daemon used by its Headlamp plugin; Kustomize places its namespaced resources in `gadget`. |
| `namespace.yaml` and `kustomization.yaml` | Create the privileged-enforce `gadget` namespace at sync wave `-1` and rewrite Gadget resource namespaces and its ClusterRoleBinding subject. |

`TempRole.yaml` currently contains the literal group name `Server Admins`; it
does not iterate over `oauth.groups`. If that access group changes, update both
the value and the RBAC template. The Headlamp subchart also creates its own
service-account ClusterRoleBinding as configured in `values.yaml`.

### Operations and troubleshooting

Render changes before deployment and inspect the generated Workspace module:

```sh
helm dependency update .
helm lint .
helm template <release> . --namespace <namespace>
kustomize build .
```

The standalone `kustomize build` validates the checked-in Kustomize layer. To
inspect its namespace rewrites, render the complete Lovely unit in Argo CD or
run the same Helm-to-Kustomize pipeline configured for the Lovely plugin; a
plain `helm template` does not apply the Kustomize patches.

After deployment, use the Workspace conditions and controller events as the
source of truth for reconciliation:

```sh
kubectl describe workspace headlamp-sso -n <namespace>
kubectl get secret core-headlamp-oidc -n <namespace>
kubectl describe httproute headlamp -n <namespace>
kubectl get namespace gadget --show-labels
kubectl get daemonset,serviceaccount,role,rolebinding -n gadget
```

Do not print or commit the Secret contents. If the Workspace is not ready,
check that all referenced Authentik objects exist with the exact names/slugs
listed above and that the `authentik` ProviderConfig can authenticate. If OIDC
login succeeds but Kubernetes requests are forbidden, check the token's group
claim and the `server-admins-clusterrolebinding` subject independently of the
Authentik application bindings.
