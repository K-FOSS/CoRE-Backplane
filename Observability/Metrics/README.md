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
site identity. Both sites enable the distributed implementation and use their
local Garage S3 endpoint. The global `core-mimir` Service keeps client traffic
site-local where possible, while the global memberlist Service joins both
Mimir rings into one logical active-active ring. Distributors,
ingesters, queriers, query frontends, query schedulers, store-gateways,
compactor, ruler, Alertmanager and the NGINX gateway run as separate upstream
chart workloads. Three YXL ingesters receive Prometheus remote write, keep
WAL/head working data on persistent [Longhorn-backed](https://longhorn.io/docs/latest/)
claims, and ship blocks to site-local S3. Three queriers and three query
frontends execute PromQL; two query schedulers coordinate the read path. The
stable `core-mimir` Service selects the distributed NGINX gateway so existing
collectors and the bridge keep their endpoint. The blocks backend remains S3;
local claims hold working state and synchronized indexes. The distributed
ingesters use a soft hostname topology spread constraint and a preferred pod
anti-affinity rule, so new pods favor separate nodes but can share a node when
capacity or node eligibility prevents spreading. Existing pods are not moved
by these scheduling preferences until they are recreated. The distributed
configuration explicitly sets `blocks_storage.backend: s3` and its bucket name
alongside the shared S3 client. With MinIO selected, the Mimir `User` claim
provisions the `mimir-blocks`, `mimir-alertmanager`, and `mimir-ruler` MinIO
buckets. Alertmanager and ruler each use their named S3 bucket.
This follows Mimir's
[query-frontend data flow](https://grafana.com/docs/mimir/latest/references/architecture/components/query-frontend/)
and documented [query-scheduler ring discovery](https://grafana.com/docs/mimir/latest/references/architecture/components/query-scheduler/),
and uses its documented [`-target` component selection](https://grafana.com/docs/mimir/latest/configure/about-configurations/).
Both sites retain their S3 `User` claims and stable connection Secrets. Garage
mode uses the operator-managed GarageKey below; the existing MinIO-specific
User S3 claim and resources remain provisioned but are unused by the Garage
client.
YXL renders the HTTPRoute and Envoy SecurityPolicy. When `mimirEnabled` is
false, the distributed chart is disabled while the recovery identity remains.

## Distributed tracing

Every active Mimir component exports OTLP traces to the site-local
[Alloy collector](../Collectors/README.md) over HTTP on port `4318`. Mimir uses
the documented
[OpenTelemetry tracing environment variables](https://grafana.com/docs/mimir/latest/configure/configure-tracing/)
with parent-based 10 percent trace-ID sampling and W3C Trace Context plus
baggage propagation. Parent sampling decisions are retained across Mimir's
internal requests; new root traces are sampled at the configured ratio. Alloy
adds the cluster tenant header and forwards the spans through the global Tempo
Service described by the [Traces stack](../Traces/README.md).

## Garage object storage

For YVR, the `User` claim uses the YXL Garage credentials handle to create
`mimir-garage-s3`, while Mimir writes through the local
`observability-garage` S3 listener on port `3900` with HTTP enabled. YXL
continues to use the TLS gateway. YVR does not create duplicate buckets.

Each active site's Metrics chart owns or reconciles Garage buckets `mimir-blocks`, `mimir-alertmanager`,
and `mimir-ruler`, plus a GarageKey scoped to those buckets. The operator
creates the S3 credential Secret `mimir-garage-s3`; Mimir reads its access and
secret keys from that Secret and uses the HTTPS endpoint
`observability-garage-s3.core-prod.svc.<cluster-domain>:443`. Envoy Gateway
terminates TLS with a valid cert-manager certificate from
[Network/TLS Certificates](../../Network/TLS/Certificates/README.md) and
routes traffic to Garage's HTTP S3 listener. Garage itself is owned by the
[Garage Operator stack](../../Storage/S3/Operators/Garage/README.md) and the
[Observability/Common cluster chart](../Common/README.md). Reconcile those
applications before Metrics so the Garage CRDs and cluster exist first.

YXL and YVR select `mimir.storage.backend: 'garage'` and use the local Garage
buckets. Historical blocks and Alertmanager objects in MinIO are not copied or
read by the new backend; they remain in MinIO with the existing MinIO `User`
claim, buckets, and credentials for possible recovery. This change does not
delete those resources. The GarageKey has only read/write rights to the two
Mimir buckets and cannot administer the Garage cluster. Mimir's MinIO
`User`-based LDAP credential workflow remains provisioned but is unused by the
Garage client; the operator supplies its separate static GarageKey.

## Storage and credentials

The distributed chart's `ingester` and `compactor` persistence values use the
`longhorn` StorageClass. The store-gateway retains its existing
`core-fast-rwx` claim template; despite the legacy name, that class is a
Longhorn XFS RWO class. All workload claims use retention policies. This keeps
the store-gateway index cache on a block volume; Grafana
documents that Mimir components using local disk require POSIX block storage
and do not support network filesystems in its
[hardware requirements](https://grafana.com/docs/mimir/latest/set-up/hardware-requirements/).
The owning Application ignores the store-gateway StatefulSet's immutable
`volumeClaimTemplates` field while respecting differences during sync. This
preserves the API-defaulted live claim template and allows ordinary pod-template
rollouts without replacing retained PVCs.
The legacy
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
settings differ from the retained, disabled single-binary profile. The S3
layout follows Grafana's [distributed chart production configuration
guide](https://grafana.com/docs/helm-charts/mimir-distributed/latest/run-production-environment-with-helm/#configure-mimir-to-use-object-storage).

The ruler and Alertmanager use the S3 backend with separate `mimir-ruler` and
`mimir-alertmanager` buckets. Their `/data/ruler` and `/data/alertmanager`
paths are local working directories; durable rule definitions and Alertmanager
state are stored in S3. The Mimir configuration API is therefore authoritative
for ruler rules rather than the exporter-owned rulefiles ConfigMap. See the
upstream [ruler storage documentation](https://grafana.com/docs/mimir/latest/references/architecture/components/ruler/)
and [object-storage configuration](https://grafana.com/docs/mimir/latest/configure/configure-object-storage-backend/).

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
sites, and each bridge sends shared-tenant requests to `core-mimir`; using a
separate bridge Service prevents a proxy loop.
Cilium correlates global Services by namespace and name, while Lovely may
derive a different Helm release name for each generated Argo CD Application.
The `core-mimir-gossip-global` Service is part of ClusterMesh and is used by
all Mimir components for memberlist discovery and HA-tracker state. Mimir's
replication factor remains three, so a series is replicated across the shared
ring rather than being confined to the site that received its write.
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
cluster-domain suffix is generated. The proxy sets `X-Scope-OrgID: core` for
the fixed tenant expected by this bridge, removes the incoming
`Authorization` header, and serves `/-/healthy` locally
without contacting YXL. Kubernetes readiness and liveness probes use this
endpoint; `/healthz` remains available as a compatibility alias.
It uses the maintained
[`nginxinc/nginx-unprivileged` image](https://github.com/nginx/docker-nginx-unprivileged)
pinned by version and multi-architecture digest, an unprivileged listener, a
read-only root filesystem, and a size-limited `/tmp` `emptyDir`.

Before a query leaves the bridge Pod, one pinned
[`prom-label-proxy` instance](https://github.com/prometheus-community/prom-label-proxy)
enforces `cluster=<cluster.name>`, whose value comes from the ApplicationSet's
cluster identity, not caller-controlled parameters. Label APIs are enabled so
discovery requests are scoped along with PromQL queries, and conflicting
matchers fail instead of silently replacing the enforced cluster scope. The
proxy no longer filters on the `org_id` label. NGINX injects the required
Mimir `X-Scope-OrgID: core` tenant header, including for clients that do not
send one, then forwards the unprefixed path through the cluster filter. That
filter adds Mimir's `/prometheus` prefix through its upstream URL. When
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

### Active-active ring, token persistence and write quorum

The production distributed profile is the classic Mimir architecture: there is
no `ingest_storage` or Kafka configuration, and the ingester hash ring is used
for both series sharding and ingester discovery. The six ingesters therefore
intentionally share one logical ring through the memberlist KV store. In this
architecture each ingester should own tokens; `ACTIVE` alone is not evidence
that it can receive writes. With replication factor three, a write requires a
quorum of two ingesters. See Grafana's [classic ingester and replication
model](https://grafana.com/docs/mimir/latest/references/architecture/components/ingester/)
and [configuration parameter reference](https://grafana.com/docs/mimir/latest/configure/configuration-parameters/).

The ring identity is qualified with the cluster name and StatefulSet pod name
through the ingester CLI flags in the owning ApplicationSet. The token file is
also qualified with those values. This preserves the existing PVCs and WALs,
but prevents a token file created for the former site-colliding identity from
being reused by a new site-qualified identity. The old `/data/tokens` files are
left untouched for rollback/recovery; they must not be deleted without a
planned ring migration. Grafana documents that a non-empty
`tokens-file-path` restores tokens at startup, while an empty path disables
token persistence; this deployment deliberately keeps persistence enabled.

The confirmed failure was a ring with six registered identities but only one
512-token owner. The other five instances had zero tokens, so the distributor
could select only one live replica and Alloy received HTTP 500 responses. After
the qualified token paths rolled out, the ring reported token ownership across
multiple ingesters and Alloy's errors changed from quorum failures to transient
cross-site request deadlines. The distributor downstream timeout is now 10s to
accommodate the approximately 80ms inter-site path and WAL/compaction work.

Zone-aware ring replication remains disabled. The current topology has no
ingesters in YVR and fewer than three eligible failure zones for the configured
replication factor, so enabling it causes Mimir to reject writes that require
replicas in distinct zones. Memberlist remains the shared discovery and KV
transport. Enable zone-aware rings only after the topology provides the
required ingester zones and quorum; see Grafana's [Mimir zone-awareness configuration](https://grafana.com/docs/mimir/latest/configure/configuration-parameters/)
for the component-specific settings.

### Ring and ingestion verification

Use the distributor's `/ingester/ring` and `/metrics` endpoints, not only pod
readiness, when validating ingestion. The following checks are read-only and
should be run against both site contexts:

```bash
kubectl --context <site-context> -n core-prod get pods \
  -l app.kubernetes.io/component=ingester -o wide
kubectl --context <site-context> -n core-prod logs \
  -l app.kubernetes.io/component=distributor --since=10m | \
  rg 'httpCode=500|at least 2 live|context deadline exceeded'
```

The ring should show six expected site-qualified members, no `UNHEALTHY`
members, and token ownership on every active ingester. Monitor
`cortex_ring_members{name="ingester",state=...}` and
`cortex_ring_tokens_total{name="ingester"}` together with distributor push
errors, ingester WAL replay duration, and the
`cortex_request_duration_seconds_count` series for the ingester Push RPC.
An `ACTIVE` member with zero tokens or repeated cross-site Push RPC failures is
an alert condition even when Kubernetes reports the pod ready.

### Architecture assessment and recovery

Option A, the current shared ring, is supported and is the smallest change for
active-active querying, but classic Mimir performs synchronous replicated
writes. A WAN partition or a site with insufficient healthy ingesters can lose
the two-of-three write quorum; an `ACTIVE` ring member does not remove that
constraint. The 80 ms RTT and 100 Mb/s uplink also make cross-site Push and
memberlist traffic operationally significant. The distributor downstream
timeout is 30s for the YVR-to-YXL-only write path. Keep this topology only while
the inter-site path is monitored and the write-error budget is acceptable.

Option B—independent site-local Mimir installations—provides the cleanest site
failure isolation but requires a supported global query/federation layer and a
deliberate historical-data and HA-deduplication plan. It is not a drop-in
replacement for the current shared tenant and should be designed separately.

Option C—site-local ingestion with a shared long-term-storage/query design—can
reduce synchronous WAN write pressure, but it requires validating the exact
Mimir architecture and object-store consistency model before migration. It is
not enabled by this repair. The recommended near-term posture is to retain
Option A, validate it under a controlled single-ingester restart, and plan
Option B or C if WAN partitions or sustained Push deadlines continue.

Rollback of this repair is limited to reverting the Git commit and allowing a
controlled distributor/ingester rollout. Do not remove the site-qualified
token files, delete PVCs, or force ring-member removal as a rollback step. The
old `/data/tokens` files and Garage objects remain available for a separately
planned recovery or migration.

For a non-destructive validation, query the same tenant through the local
`core-mimir` Service from each site, then repeat after one ingester restart in
only one site. Do not delete PVCs or clear the old token files. Site-wide
failure and WAN-partition simulations require a separately approved change
window because classic Mimir replication needs two of three ingester writes to
complete.

When enabled by the production ApplicationSet, the chart exposes the JWT
protected API at `metrics.gslb.mylogin.space` on each site and creates a K8GB
`Gslb` for the global `metrics.mylogin.space` address. ExternalDNS metadata is
present only on the site HTTPRoute; K8GB owns the global record. See the
[K8GB resource reference](https://www.k8gb.io/latest/resource_ref/),
[K8GB dynamic zones](https://www.k8gb.io/latest/dynamic_zones/), and
[ExternalDNS Gateway API source](https://github.com/kubernetes-sigs/external-dns/tree/master/provider/kubernetes-sources).

Verify distributor accepted/rejected samples, active series, ingester WAL/head
size, block upload duration, compactor deletion markers, S3 throughput, and an
end-to-end query in Grafana. In YXL, verify `core-mimir` selects the Mimir Pods
and is exported by Cilium. In Home1, verify its backends are remote. On both
sites, verify both proxy Pods are ready, `/-/healthy` remains available during a
YXL outage,
and the Headlamp endpoint returns a Mimir query response with the
expected tenant. Also confirm proxy logs do not expose credentials. After the
Garage monitoring resources reconcile, verify the bundled dashboard shows
`mimir-blocks` bytes and object count, each Garage node's physical data-disk
available/total bytes, and S3/block read-write rates. Bucket-specific free
space is defined only when a GarageBucket quota is configured; these Mimir
buckets are unlimited and share the cluster's physical capacity with other
observability buckets. When rotating each YXL S3 Secret, verify that Mimir
rolls one pod at a time, all
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
