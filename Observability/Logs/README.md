# CoRE-Backplane Observability/Logs Stack

This chart deploys the shared Grafana Loki log store and the CoRE
Backplane resources that connect it to object storage, Authentik, and the
shared Envoy Gateway. It is reconciled by the
[`core-observability-logs` ApplicationSet](../../Apps/Observability/Logs.yaml)
into the `core-prod` namespace of the selected infrastructure clusters. See the
[observability stack overview](../README.md) for its collectors and consumers.

## Current deployment

DC1/YXL runs Loki in `SingleBinary` mode with three replicas. Home1/YVR keeps
the same `loki-core` Service with zero local Loki replicas and consumes DC1
backends through Cilium ClusterMesh. The chart uses the upstream
Grafana Loki chart at the version pinned in [`Chart.yaml`](Chart.yaml), while
[`values.yaml`](values.yaml) contains only deployment-specific overrides.

The single Loki process uses TSDB schema v13 and stores chunks and ruler data
in the cluster-local S3 service. Local persistent storage remains enabled by
the upstream chart for working data. The default retention period is 31 days;
streams matching `{env="testing"}` are retained for 24 hours. The compactor is
responsible for enforcing retention.

The implementation is based on the component-specific
[pinned Grafana Loki Helm chart README](https://github.com/grafana/loki/blob/helm-loki-6.46.0/production/helm/loki/README.md)
and [chart source](https://github.com/grafana/loki/tree/helm-loki-6.46.0/production/helm/loki)
and [Loki documentation](https://grafana.com/docs/loki/latest/).

The ApplicationSet currently selects `core-dc1-talos-prod` and
`core-home1-talos-prod`. It injects the cluster name, cluster domain,
datacentre, region, deployment mode, replica count, stable Service identity,
and global-service annotations through
`LOVELY_HELM_MERGE`. Those fleet-specific values should be changed in the
ApplicationSet rather than duplicated in this chart.

## Data and request flow

```text
workload and platform logs
  -> Grafana Alloy / Vector collectors
  -> namespace-local loki-core global Service
  -> DC1 Loki push API and single-binary processes
  -> DC1 S3 buckets

Grafana or an authenticated client
  -> Envoy Gateway
  -> HTTPRoute
  -> JWT SecurityPolicy
  -> Loki query API
```

### Global Service ownership

The ApplicationSet configures the existing `core-prod/loki-core` Service using
the pinned chart's `loki.singleBinary.service.annotations` values. Both sites
declare `service.cilium.io/global: 'true'` and
`service.cilium.io/global-sync-endpoint-slices: 'true'`, following the
[Metrics global-Service pattern](../Metrics/README.md). The chart already
owns the required Service, so no duplicate handwritten Service is introduced.

| Site | Loki replicas | Affinity | Shared backends |
| --- | --- | --- | --- |
| DC1/YXL | 3 | `local` | `true` |
| Home1/YVR | 0 | `remote` | `false` |

[Cilium Global Services](https://docs.cilium.io/en/stable/network/clustermesh/global-services/)
match Services by namespace and name, independently of the Helm release name.
Home1's upstream Service selector remains controller-owned but has no local
Pods to select. Its remote
[EndpointSlices are synchronized by Cilium](https://docs.cilium.io/en/stable/network/clustermesh/global-services/#synchronizing-kubernetes-endpointslice),
including for Envoy Gateway backend discovery. The memberlist and headless
Services stay local; this does not join the two sites into one Loki ring or
replicate object storage. Keep global annotations on the single-binary client
Service only, rather than on `loki.loki.serviceAnnotations`, which also affects
other Services. Loki 6.46.0 also copies the single-binary annotations to
`loki-headless`; the Lovely renderer applies
[`kustomization.yaml`](kustomization.yaml) after Helm to remove the inherited
annotations from that pinned chart's headless Service. There are no other
headless annotations configured; review this patch before adding any and
against the upstream templates when upgrading the dependency. The render unit
is Helm plus Kustomize, rather than Helm alone.

The pinned chart's
[`singleBinaryReplicas` helper](https://github.com/grafana/loki/blob/helm-loki-6.46.0/production/helm/loki/templates/single-binary/_helpers-single-binary.tpl)
renders one replica even when `singleBinary.replicas` is zero. The ApplicationSet
therefore also injects a Kustomize `replicas` transformer through
[`LOVELY_KUSTOMIZE_MERGE`](https://github.com/crumbhole/argocd-lovely-plugin#kustomize),
applying the same fleet replica count after Helm. This prevents Home1 from
starting an unintended independent Loki backend.

The [collector ApplicationSet](../../Apps/Observability/Collectors.yaml) sends
infrastructure logs to
`http://loki-core.core-prod.svc.<clusterDomain>:3100/loki/api/v1/push`.
Home1 writes therefore reach DC1 through ClusterMesh. The legacy
`dc1-k3s-node1` collector has no local global Service and deliberately retains
the mutable DC1 Service IP `10.44.0.196`; reassess that literal when replacing
the Service or retiring the legacy cluster.

The surrounding observability components are documented in the
[observability stack guide](../README.md). Collector configuration lives in
[`Observability/Collectors`](../Collectors/), and dashboards and interactive
queries are provided by [`Observability/Dashboards`](../Dashboards/).

## Resources owned by this chart

In addition to the upstream Loki resources, the parent chart creates:

| Template | Responsibility |
| --- | --- |
| [`LokiUser.yaml`](templates/LokiUser.yaml) | Creates the S3 identity, credentials, and the `loki-rules-temp` and `loki-admin` buckets through the platform `User` API. |
| [`AuthentikLoki.yaml`](templates/AuthentikLoki.yaml) | Creates the Authentik OAuth2 provider, application, group bindings, and client connection secret through a Terraform Workspace. |
| [`HTTPRoutes.yaml`](templates/HTTPRoutes.yaml) | Publishes the cluster-specific Loki endpoint through the shared Gateway. |
| [`SecurityPolicy.yaml`](templates/SecurityPolicy.yaml) | Validates Grafana or Loki JWTs and permits members of the configured log-access groups. |

The `User` resource writes two Secrets into the release namespace:

| Secret | Consumer | Purpose |
| --- | --- | --- |
| `loki-core` | Loki | S3 connection metadata and the dynamically assigned chunks bucket. |
| `loki-core-s3-creds` | Loki | S3 access key, secret key, and session token. |

The Authentik Workspace writes OAuth client outputs to `loki-core-sso`.
Secret values are generated by controllers and are not stored in this
repository.

## External access and authorization

The public hostname follows this pattern:

```text
logs.<cluster>.<datacentre>.<region>.<externalDomain>
```

The HTTPRoute attaches to the configured Gateway and forwards requests to the
Loki service on port 3100. The Envoy `SecurityPolicy` accepts tokens from the
Grafana provider and from the cluster-specific Loki Authentik provider. Access
is denied by default and allowed only when the token contains a group listed
under `oauth.allowedGroups` (currently `Logs`). The `orgID` claim is forwarded
as `X-Scope-OrgID`.

Loki's own multi-tenant authentication is disabled; the gateway is therefore
the security boundary for external access. Do not expose the Loki Service
directly outside the cluster.

## Important values

| Value | Meaning |
| --- | --- |
| `cluster.name`, `datacenter`, `region` | Cluster identity used in resource names, provider selection, and the public hostname. |
| `cluster.domain` | Internal Kubernetes DNS domain injected by the fleet ApplicationSet. |
| `externalDomain` | Base domain used for the public Loki endpoint. |
| `gateway.*` | Shared Gateway parent reference and listener. |
| `oauth.groups` | Authentik groups bound to the generated application. |
| `oauth.allowedGroups` | Groups accepted by the Envoy authorization policy. |
| `loki.deploymentMode` | Upstream Loki topology; currently `SingleBinary`. |
| `loki.singleBinary.replicas` | Three in DC1, zero in Home1; owned by the ApplicationSet. |
| `loki.singleBinary.service.annotations` | Cilium global-Service sharing, affinity, and EndpointSlice synchronization. |
| `loki.singleBinary.persistence.whenDeleted`, `whenScaled` | `Retain` preserves working-data PVCs across role changes and deletion. |
| `loki.loki.storage` | S3 and bucket configuration interpolated from generated Secrets. |
| `loki.loki.limits_config` | Query and retention policy. |

## Dependencies and prerequisites

The target cluster must provide:

- functioning [Cilium ClusterMesh](https://docs.cilium.io/en/stable/network/clustermesh/)
  and `clustermesh.enableEndpointSliceSynchronization`, enabled by the
  [Network Base stack](../../Network/Base/);
- the Gateway API and an Envoy Gateway matching `gateway.*`;
- Envoy Gateway `SecurityPolicy` CRDs;
- the platform `User` API and its S3 compositions;
- Crossplane's Terraform Workspace API and an `authentik` provider config;
- the regional S3 provider configs named by `LokiUser.yaml`;
- Authentik flows, scope mappings, groups, and the `tls` signing key referenced
  by the Workspace; and
- collectors configured to send logs to this Loki instance.

## Rendering and validation

Fetch the pinned dependency and render with representative fleet values:

```bash
helm dependency build Observability/Logs
helm lint Observability/Logs --strict
helm template logs Observability/Logs \
  --namespace core-prod \
  --set cluster.name=core-dc1-talos-prod \
  --set datacenter=dc1 \
  --set region=yxl
```

These commands check the Helm defaults. For production validation, supply each
Application's parsed `LOVELY_HELM_MERGE`, then add the Helm output as a resource
to a temporary copy of `kustomization.yaml`, merge its injected
`LOVELY_KUSTOMIZE_MERGE`, and run `kustomize build`. A Helm-only Home1 render
still contains one replica because of the upstream helper described above.

Render again with Home1's injected values and zero replicas. Verify the
StatefulSet has three replicas in DC1 and zero in Home1, both `loki-core`
Services carry the four site-specific Cilium annotations,
memberlist/headless Services have no global annotations, and retention is
`Retain` for both deletion and scaling. Check that
the HTTPRoute targets service port 3100, S3 environment variables reference
the generated Secrets, and the Authentik issuer and redirect URI use the same
cluster-specific slug and hostname.

## Operations

Use Argo CD for deployment and inspect both the Application and downstream
controller conditions when reconciliation stalls. A healthy rollout requires
the `User` and Terraform `Workspace` resources to become ready before Loki can
consume their generated Secrets.

For an ingestion failure, check the collector first, then Loki readiness and
the S3 Secrets. For query failures, distinguish gateway authentication errors
from Loki/API errors by checking the HTTPRoute and SecurityPolicy conditions.
Retention changes affect only compactor policy; increasing retention also
increases object-storage use.

Verify `loki-core` has three ready local endpoints in DC1 and synchronized
DC1 endpoints with no local backends in Home1. Check the Cilium-managed
EndpointSlice labels and ready addresses, Loki `/ready`, both HTTPRoute and
SecurityPolicy acceptance, collector write errors, and a Loki query returning
logs labelled with each source cluster. A useful cross-site check is to push a
unique temporary verification stream through Home1's global Service and query
it through DC1. Do not print production log contents or credentials while
verifying ingestion. Confirm unauthenticated public queries are rejected.

Reconcile the Logs and Collectors ApplicationSets selectively in the Apps
parent, then the affected child resources. The global-Service rollout changes
`loki-core`, `loki-headless`, and the `loki-core` StatefulSet in each Logs
Application, plus only the central Alloy ConfigMap in each infrastructure
Collectors Application. These resources have no sync hooks or dependent sync
waves; selective sync avoids applying unrelated pre-existing identity or
collector drift. The legacy collector's rendered destination is unchanged and
needs no child sync. Record the revision and selectors because selective sync
does not add normal Argo CD sync history. Inspect full application drift
separately instead of treating the selected-resource result as fleet health.

## Storage, security, and recovery

DC1 remains the data-bearing site. Home1 depends on DC1 and ClusterMesh for
both writes and queries; global Services do not provide a second data store
or automatic site failover. Previously stored Home1 objects are not migrated
into DC1 by this change. The existing Home1 `User` claim, Authentik Workspace,
connection Secrets, and storage integration remain declared for recovery;
do not prune those resources as part of this role change.

Both single-binary StatefulSets explicitly use
[`Retain` PVC policies](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/#persistentvolumeclaim-retention).
Before scaling down any running site, reconcile retention first and verify
its PVCs no longer have deletion-triggering Pod/StatefulSet owner references.
The rollout of this configuration keeps DC1 at three replicas and Home1 at
its existing live count of zero. Scale-down does not delete S3 objects, and
retained PVCs require a separate cleanup decision.

Roll back with a reviewed Git change and scoped Argo CD sync. Removing global
annotations stops remote discovery and breaks Home1 ingestion and queries.
Restoring Home1 replicas reconnects its separate S3 store; it does not make
both independent stores safe backends for one client Service. Review sharing,
collector destinations, and storage together before changing the serving site.
Internal Loki traffic remains unauthenticated, so access to the global Service
must remain within trusted cluster networks; JWT and group enforcement stays
on the existing public HTTPRoutes.

This remains a `SingleBinary` topology: every replica runs the full Loki
process, despite the three-way pod count. A future move to `SimpleScalable` or
`Distributed` mode requires explicit replica, routing, cache, and
object-storage review; do not change only `loki.deploymentMode`.
