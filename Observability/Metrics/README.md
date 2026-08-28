# Mimir metrics store

This chart deploys [Grafana Mimir](https://grafana.com/docs/mimir/latest/) in
a split monolithic mode using the
[`bjw-s common library`](https://github.com/bjw-s-labs/helm-charts/tree/main/charts/library/common).
The pinned
[`mimir-distributed` chart](https://github.com/grafana/helm-charts/tree/main/charts/mimir-distributed)
is retained as an optional dependency but is disabled for every currently
selected cluster.

The [`core-observability-metrics` ApplicationSet](../../Apps/Observability/Metrics.yaml)
targets `core-dc1-talos-prod` (YXL) and `core-home1-talos-prod` (YVR) and injects
site identity. YXL enables the monolithic implementation, and both sites
enable the Mimir bridge described below. Three YXL main Mimir replicas receive
Prometheus remote write, keep WAL/head working data on persistent local
volumes, and ship blocks to site-local S3. Each main and querier replica is a
StatefulSet pod with separate `ReadWriteOnce` [Longhorn-backed](https://longhorn.io/docs/latest/) claims for
`/data` and `/tmp`; claims are retained when replicas are scaled down or the
StatefulSets are deleted. Three separate querier replicas execute PromQL. The
main replicas retain the query frontend and query scheduler,
so `core-mimir` remains the entry point for both reads and writes; the scheduler
dispatches read work to the querier StatefulSet. All three components discover
the schedulers through the existing memberlist-backed query-scheduler ring.
The blocks backend is explicitly configured as S3; the local claims hold TSDB
working state and synchronized block indexes rather than being the durable
blocks store.
This follows Mimir's
[query-frontend data flow](https://grafana.com/docs/mimir/latest/references/architecture/components/query-frontend/)
and documented [query-scheduler ring discovery](https://grafana.com/docs/mimir/latest/references/architecture/components/query-scheduler/),
and uses its documented [`-target` component selection](https://grafana.com/docs/mimir/latest/configure/about-configurations/).
The YXL rendering also creates the S3 `User`,
HTTPRoute, and Envoy SecurityPolicy.

The `mimir.dataVolume` and `mimir.tmpVolume` values independently support
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

Mimir's query frontend and queriers use the site-local `dragonfly-core`
Memcached-compatible listener for query-result, label, cardinality, index,
chunk, and block-metadata caches. Mimir's OSS cache backends are Memcached, so
the Dragonfly instance exposes port `11211` in addition to its existing
authenticated Redis/TLS port `6379`; the cache connection is TLS-protected and
uses the container system trust store for the public certificate. If the
Dragonfly certificate issuer changes to a private CA, set `mimir.cache.tls.caSecretName`
to a Secret containing the configured `caSecretKey`. Cache contents are disposable and do
not replace Mimir's S3 blocks. This shares the Dragonfly process and memory
limit with other site-local consumers; if cache pressure affects durable
application state, move Mimir to a dedicated Dragonfly instance.
See the [Mimir configuration parameters](https://grafana.com/docs/mimir/latest/configure/configuration-parameters/)
for the supported Memcached cache backends and label-result TTL settings.

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
forwards the unprefixed path to the loopback-only filter listener before it
contacts `core-mimir`; the filter adds Mimir's `/prometheus` prefix through its
upstream URL. When `mimirBridge.queryFilter` is disabled, NGINX adds the same
prefix before forwarding directly.

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

YXL is intentionally constrained to 100,000 samples/s, a 200,000-sample burst,
12-hour retention, and one concurrent block upload. Rate limiting rejects
excess samples; it does not reduce the collectors' Kubernetes watches or
guarantee an immediate drop in sender network retries. Retention is enforced
asynchronously by the compactor and does not immediately delete existing
objects.

Mimir is the destination of the monitoring data, not the origin of the high
Kubernetes API traffic. See [Collectors](../Collectors/README.md) for the API
watch fan-out and [Exporters](../Exporters/README.md) for the highest-volume
metric sources.

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
