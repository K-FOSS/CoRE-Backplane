# CoRE-Backplane Observability/Metrics Stack

This chart deploys [Grafana Mimir](https://grafana.com/docs/mimir/latest/) in
the upstream microservices mode using the pinned
[`mimir-distributed` chart](https://github.com/grafana/helm-charts/tree/main/charts/mimir-distributed).
The compatibility bridge and Service remain rendered through the
[`bjw-s common library`](https://github.com/bjw-s-labs/helm-charts/tree/main/charts/library/common).
See the [Observability overview](../README.md).

## Ownership, targets and rendering

The [`core-observability-metrics` ApplicationSet](../../Apps/Observability/Metrics.yaml)
targets `core-dc1-talos-prod` (YXL) and `core-home1-talos-prod` (YVR) and injects
site identity. YXL enables the distributed implementation, while YVR keeps the
remote bridge and recovery identity without local Mimir pods. Distributors,
ingesters, queriers, query frontends, query schedulers, store-gateways,
compactor, ruler, Alertmanager and the NGINX gateway run as separate upstream
chart workloads. Three YXL ingesters receive Prometheus remote write, keep
WAL/head working data on persistent [Longhorn-backed](https://longhorn.io/docs/latest/)
claims, and ship blocks to site-local S3. Three queriers and three query
frontends execute PromQL; two query schedulers coordinate the read path. The
stable `core-mimir` Service selects the distributed NGINX gateway so existing
collectors and the bridge keep their endpoint. The blocks backend remains S3;
local claims hold working state and synchronized indexes.
This follows Mimir's
[query-frontend data flow](https://grafana.com/docs/mimir/latest/references/architecture/components/query-frontend/)
and documented [query-scheduler ring discovery](https://grafana.com/docs/mimir/latest/references/architecture/components/query-scheduler/),
and uses its documented [`-target` component selection](https://grafana.com/docs/mimir/latest/configure/about-configurations/).
Both sites retain their S3 `User` claims and stable connection Secrets.
YXL renders the HTTPRoute and Envoy SecurityPolicy. When `mimirEnabled` is
false, the distributed chart is disabled while the recovery identity remains.

## Storage and credentials

The distributed chart's `ingester`, `store_gateway`, and `compactor` persistence
values use Longhorn claims with `Retain` policies. The legacy
`mimir.dataVolume` and `mimir.tmpVolume` values remain for the disabled
single-binary compatibility path and independently support
`type: 'emptyDir'` or `type: 'persistentVolumeClaim'`. For node-local disk,
use `emptyDir` with an empty `medium`; for tmpfs memory, use `emptyDir` with
`medium: 'Memory'`. PVC mode requires `accessMode`, `size`, and
`storageClass` and creates one claim per StatefulSet replica. If either volume
uses PVC mode, both Mimir workloads render as StatefulSets so RWO claims remain
per-replica; otherwise they render as Deployments with `emptyDir` volumes.

The main Mimir and querier workloads use [Reloader's targeted Secret annotation](https://github.com/stakater/Reloader#how-to-use-reloader)
to roll when either generated S3 Secret changes. `*-s3-creds` provides the
access key, secret key, and session token; `*-creds` provides the bucket name.
Reloader changes only the affected pod templates, and each three-replica
workload's rolling strategy, readiness probe, and PodDisruptionBudget keep
serving replicas available during credential rotation. The target cluster must run Reloader;
the operations configuration ApplicationSet provides it on both selected
Talos production clusters.

### DC1 distributed configuration and ruler

The distributed profile preserves the operator's live DC1 configuration from
2026-10-04. Dragonfly caches are disabled; result-cache TTLs remain configured
for a future cache rollout. S3 HTTP pools allow 200 idle connections globally
and per host. The distributed profile uses upstream multitenancy defaults,
no blocks storage prefix, and the upstream ship-concurrency default. These
settings differ from the retained, disabled single-binary profile.

The ruler mounts the exporter-owned rulefiles ConfigMap at `/rules/core` and
uses `ruler_storage.backend: local` with directory `/rules`. Tenant `core`
therefore reads that ConfigMap. The writable ruler working directory is
`/data`, separate from the read-only rule input. Compactor and Alertmanager
also use their chart-mounted `/data` paths. See the upstream
[ruler local-storage layout](https://grafana.com/docs/mimir/latest/references/architecture/components/ruler/#local-storage):
local rules cannot be edited through the ruler configuration API. Update the
exporter's rule source instead. The inactive `mimir-ruler` S3 setting remains
for compatibility but is not the active rule source.

Before reconciliation, compare the rendered `core-mimir-config` and ruler
volume mounts with DC1. Reverting to the single-binary storage prefix or tenant
settings changes which existing objects and series are visible; it is not a
transparent rollback. Retain existing buckets and PVCs.

## Routing and query flow

Production renders the global-query and bridge Service roles through the
bjw-s common library. `core-mimir` is the primary Mimir Service and a
[Cilium global service with
EndpointSlice synchronization](https://docs.cilium.io/en/stable/network/clustermesh/global-services/#synchronizing-kubernetes-endpointslice)
configured by the ApplicationSet. YXL exports the local Mimir backends with
local affinity and sharing enabled. Home1 declares the same global Service
identity with remote affinity and sharing disabled. Its common-chart Service
has a deliberately non-matching selector, so only Cilium-synchronized remote
EndpointSlices back it. The YXL HTTPRoute also uses this Service as its direct
backend. `core-mimir-proxy` selects the bridge Pods on both
sites, and each bridge sends filtered requests to `core-mimir`; using a
separate bridge Service prevents a proxy loop.
Cilium correlates global Services by namespace and name, while Lovely may
derive a different Helm release name for each generated Argo CD Application.
The memberlist gossip Service remains YXL-local and is not part of ClusterMesh.
This depends on Cluster Mesh connectivity and
`clustermesh.enableEndpointSliceSynchronization`, which the Network Base
deployment enables.

Both sites also render a two-replica `core-mimir-proxy` Deployment and matching
ClusterIP Service, along with the NGINX ConfigMap, through
the bjw-s common library. Headlamp's KubeVirt plugin endpoint is
`/api/v1/namespaces/core-prod/services/core-mimir-proxy:8080/proxy/`.
The Kubernetes API server proxies to a locally visible proxy Pod; the proxy
then uses [NGINX `proxy_pass` without a URI](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_pass)
to map the bridge-root Prometheus API to Mimir's `/prometheus` prefix on the
namespace-local `http://core-mimir:8080` global Service reference. For example,
bridge `/api/v1/query` becomes Mimir `/prometheus/api/v1/query`, and bridge `/`
becomes Mimir `/prometheus/`. The legacy bridge `/prometheus/...` form remains
accepted during migration. No Kubernetes
cluster-domain suffix is generated. The proxy forwards `X-Scope-OrgID`,
removes the incoming `Authorization` header, and serves `/-/healthy` locally
without contacting YXL. Kubernetes readiness and liveness probes use this
endpoint; `/healthz` remains available as a compatibility alias.
It uses the maintained
[`nginxinc/nginx-unprivileged` image](https://github.com/nginx/docker-nginx-unprivileged)
pinned by version and multi-architecture digest, an unprivileged listener, a
read-only root filesystem, and a size-limited `/tmp` `emptyDir`.

Before a Home1 query leaves the bridge Pod, a pinned
[`prom-label-proxy` instance](https://github.com/prometheus-community/prom-label-proxy)
parses the request and enforces `cluster=<cluster.name>`. The value comes from
the ApplicationSet's cluster identity, not from caller-controlled parameters.
Label APIs are enabled so discovery
requests are scoped along with PromQL queries, and a request containing a
conflicting matcher fails instead of silently replacing its scope. NGINX
sets `X-Org-ID: core` before forwarding the unprefixed path to the loopback-only
filter listener; `prom-label-proxy` uses that header to enforce
`org_id="core"` in PromQL and label API selectors. NGINX also preserves the
existing `X-Scope-OrgID` tenant header for Mimir. NGINX forwards the request to
the filter before it contacts `core-mimir`; the filter adds Mimir's
`/prometheus` prefix through its upstream URL. When
`mimirBridge.queryFilter` is disabled, NGINX adds the same prefix before
forwarding directly.

## Configuration

The chart itself has neutral defaults for Service naming and annotations,
object-storage endpoints, tenant/rule identity, Gateway routes, and JWT policy.
The ApplicationSet owns the production Cilium, DNS, Gateway,
identity-provider, tenant, and site values. The optional CoRE S3-user
integration retains its fixed `mylogin.space/v1alpha1` API, `LDAPService`
group, provider naming convention, and Mimir bucket defaults in the template.
OIDC integration is disabled by default and requires all provider-specific
values; missing secret or identity references fail rendering rather than
deploying placeholders.

The production integrations use [Cilium Global
Services](https://docs.cilium.io/en/stable/network/clustermesh/global-services/),
[Gateway API HTTPRoute](https://gateway-api.sigs.k8s.io/api-types/httproute/),
[Envoy Gateway SecurityPolicy](https://gateway.envoyproxy.io/docs/api/extension_types/#securitypolicy),
and a site-owned S3 `User` API. OIDC provisioning, when enabled, uses the
[Authentik Terraform provider](https://registry.terraform.io/providers/goauthentik/authentik/latest/docs)
through a [Crossplane Terraform
Workspace](https://github.com/crossplane-contrib/provider-terraform/blob/main/docs/Usage.md),
then publishes selected credentials with [External Secrets
PushSecret](https://external-secrets.io/latest/api/pushsecret/).

YXL is intentionally constrained to 500,000 samples/s, a 1,550,000-sample burst,
12-hour retention, and one concurrent block upload. Rate limiting rejects
excess samples; it does not reduce the collectors' Kubernetes watches or
guarantee an immediate drop in sender network retries. Retention is enforced
asynchronously by the compactor and does not immediately delete existing
objects.

Mimir is the destination of the monitoring data, not the origin of the high
Kubernetes API traffic. See [Collectors](../Collectors/README.md) for the API
watch fan-out and [Exporters](../Exporters/README.md) for the highest-volume
metric sources.

## Operations and verification

Verify distributor accepted/rejected samples, active series, ingester WAL/head
size, block upload duration, compactor deletion markers, S3 throughput, and an
end-to-end query in Grafana. In YXL, verify `core-mimir` selects the Mimir Pods
and is exported by Cilium. In Home1, verify its backends are remote. On both
sites, verify both proxy Pods are ready, `/-/healthy` remains available during a
YXL outage,
and the Headlamp endpoint returns a Mimir query response with the
expected tenant. Also confirm proxy logs do not expose credentials. After
rotating each YXL S3 Secret, verify that Mimir rolls one pod at a time, all
replacement pods become ready, and block uploads and queries continue without
authentication errors. Render both site profiles before merging. Roll back
through Git/Argo CD. Disabling the bridge removes the local `core-mimir-proxy`
Service and breaks the Headlamp endpoint; removing the global-service
annotations stops new remote backend synchronization. Increasing retention
does not restore blocks already deleted, and lowering rate limits creates
intentional monitoring gaps.


## YVR to YXL cutover and recovery

The October 2026 cutover starts a fresh metrics store in YXL using its existing
site identity, site-local S3 endpoint and new Longhorn claims. It does not copy
YVR blocks, WAL/head data, ruler objects or Alertmanager state. The previously
scaled-to-zero YVR StatefulSets must remain stopped. Both sites keep their
bridge; only YXL exports local Mimir backends through the global Service.

Keep the YVR `User` claim and its connection Secrets managed in Git. Its
existing Longhorn claims have `Retain` policies on StatefulSet deletion and
scale-down. Do not prune these claims, delete the identity or remove S3 buckets
as part of this cutover. The [SSO User Composition](../../Operations/SSO/User)
owns the provider resources; its S3 bucket and policy resources use orphan
deletion policies. Verify downstream conditions and actual S3 access rather
than relying on the claim's Ready condition.

The YXL blocks bucket comes from the YXL identity's `username` Secret key,
without a blocks prefix in distributed mode. The legacy single-binary
profile used `blocks` and separate `mimir-alertmanager` and `mimir-ruler` buckets. See [Mimir object storage configuration](https://grafana.com/docs/mimir/latest/configure/configure-object-storage-backend/).
YVR history remains available only through a deliberate recovery or migration;
queries against the fresh YXL backend do not include it. Existing YXL objects,
if present from an earlier deployment, are not deleted by this change.

Reconcile the owning ApplicationSet, then YXL metrics, verify S3 access and
ready ingesters/queriers, and reconcile YVR metrics without pruning retained
resources. Verify remote-write acceptance and queries through both site
bridges. For rollback, stop YXL writers through Git and Argo CD before enabling
YVR workloads and reversing global Service affinity/sharing. Retained volumes
and buckets are recovery inputs, not proof of a tested recovery.
