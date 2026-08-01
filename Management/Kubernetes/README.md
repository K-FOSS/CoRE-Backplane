# K-FOSS/CoRE-Backplane Kubernetes Management

This chart deploys Headlamp together with Inspektor Gadget for cluster
management, debugging, and introspection.

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
  `https://github.com/K-FOSS/CoRE-Backplane.git` at the moving `HEAD`
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
| `cluster.kubernetes.io/domain` | `cluster.domain` | Recorded as cluster metadata; not currently used by a template. |
| `resolvemy.host/env` | `env` | Determines the destination namespace as well; not currently used by a chart template. |
| `resolvemy.host/dc` | `datacenter` | Public hostname and Authentik naming/grouping. |
| `topology.kubernetes.io/region` | `region` | Authentik provider name, application slug, and client ID. |

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
started on demand through the Headlamp plugin or `kubectl gadget`; no tracing
tools run continuously by default. Long-running tools can be declared under
`gadget.config.gadgetConfigMaps`.

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

The chart also installs these Headlamp plugins:

- [Inspektor Gadget plugin README](https://github.com/inspektor-gadget/headlamp-plugin#readme)
  ([repository](https://github.com/inspektor-gadget/headlamp-plugin)) — runs and
  visualizes Inspektor Gadget tools from Headlamp.
- [KubeVirt plugin README](https://github.com/buttahtoast/headlamp-plugins/blob/main/kubevirt/README.md)
  ([repository](https://github.com/buttahtoast/headlamp-plugins/tree/main/kubevirt)) —
  adds Headlamp views and controls for KubeVirt resources.

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
   `headlamp.config.oidc.externalSecret`; Headlamp does not generate or own the
   credentials.
9. `templates/HTTPRoute.yaml` exposes Headlamp through the configured Gateway.
   After login, the OIDC group claim is evaluated by Kubernetes RBAC.

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
