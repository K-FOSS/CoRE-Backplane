# CoRE-Backplane Observability/Logs Stack

This stack runs the shared Grafana Loki log store in microservices mode and
connects it to the existing S3 identity, Authentik policy, collectors, and
global client Service. The
[`core-observability-logs` ApplicationSet](../../Apps/Observability/Logs.yaml)
owns its deployment. See the [observability overview](../README.md) for its
collectors and consumers.

## Ownership, targets, and rendering

DC1/YXL and Home1/YVR now run Loki data-plane workloads. Each site uses its
local Observability Garage S3 service with credentials provisioned through the
`loki-s3` `User` claim. The global `loki-core` client Service and Loki
memberlist Service use local affinity and synchronized EndpointSlices for
failover.
The ApplicationSet injects cluster identity, storage backend, component counts,
and Cilium annotations through `LOVELY_HELM_MERGE`.

The rendering unit includes this parent chart, the pinned
[Loki chart 6.46.0 README](https://github.com/grafana/loki/blob/helm-loki-6.46.0/production/helm/loki/README.md),
its [source](https://github.com/grafana/loki/tree/helm-loki-6.46.0/production/helm/loki),
and [`kustomization.yaml`](kustomization.yaml). Loki's
[microservices mode](https://grafana.com/docs/loki/latest/get-started/deployment-modes/#microservices-mode)
is selected with `deploymentMode: Distributed`.

| Component | DC1 replicas | Home1 replicas | Workload |
| --- | ---: | ---: | --- |
| Gateway | 3 | 3 | Deployment |
| Distributor | 3 | 3 | Deployment |
| Ingester | 3 | 3 | StatefulSet |
| Querier | 3 | 3 | Deployment |
| Query frontend | 3 | 3 | Deployment |
| Query scheduler | 2 | 2 | Deployment |
| Index gateway | 3 | 3 | StatefulSet |
| Compactor | 1 | 1 | StatefulSet |
| Ruler | 1 | 1 | StatefulSet |

The simple-scalable and former single-binary targets remain at zero. Both sites
run the distributed read and write paths with replication factor 2; YVR and
YXL are the two failure domains. Hostname spreading and disruption budgets
protect rollouts and node loss within each site.

## Architecture and global Service

```text
Alloy -> loki-core:3100 -> Loki gateway -> distributor -> ingester -> S3
Grafana -> Envoy/JWT -> loki-core:3100 -> query frontend -> scheduler
        -> querier -> index gateway and S3
```

[`GlobalService.yaml`](templates/GlobalService.yaml) defines `loki-core`
because the upstream distributed gateway is named `loki-core-gateway`. This
small direct Service preserves the existing client DNS name, port `3100`,
Cilium pairing, and ClusterIP while selecting gateway pods. The upstream
gateway routes API paths to their owning components. The public
[`HTTPRoute`](templates/HTTPRoutes.yaml) uses the same stable Service.

Both sites set `service.cilium.io/global` and EndpointSlice synchronization on
the client and memberlist Services. Cilium affinity prefers the local site and
cross-site endpoints provide failover. This is the current implementation,
but it is not the target storage topology: a global memberlist ring makes Loki
replicate hot log data between sites before it reaches Garage. This follows the
[Cilium global Service](https://docs.cilium.io/en/stable/network/clustermesh/global-services/)
model. The memberlist Service is global so both sites share one ring, while
client traffic remains local-preferred. Loki 3.5.7 does not support Mimir's
`memberlist.zone_aware_routing` configuration, so site replication is provided
by the global ring and the replication factor instead.

The target design keeps the client `loki-core` Service global for site-level
failover, but makes the Loki memberlist Service and ring site-local and sets
the local ring replication factor to `1`. Garage remains the shared durability
and cross-site replication layer for `loki-chunks`, `loki-rules-temp`, and
`loki-admin`. This avoids a second copy of each stream in the remote Loki
ingester while preserving query access through the shared bucket namespace.
The rollout must first establish single-site write ownership and compactor
coordination; changing only the replication factor would not be a safe
cross-site migration.

## Observability S3 and Loki credentials

On YXL and YVR, the `loki-s3` claim uses the `garage` backend in the existing
[`User` Composition](../../Operations/SSO/User/README.md). The claim creates
the Garage buckets and a scoped, long-lived Garage key, then publishes its
stable connection Secret as `loki-core` and credentials Secret as
`loki-core-s3-creds`. Loki reads the full `AWS_ENDPOINTS` URL, `AccessKey`, and
`SecretAccessKey` from the credential Secret. No Garage bucket or key CR is
declared directly by this chart. The Garage API is enabled for YXL in the
[User ApplicationSet](../../Apps/Infra/Crossplane/User.yaml), and the Garage
operator and cluster must be ready first.

| Existing object | Purpose |
| --- | --- |
| `loki-core` User connection Secret | Claim connection details, including `S3Hostname` |
| `loki-core-s3-creds` User credential Secret | Scoped `AWS_ENDPOINTS`, `AccessKey`, and `SecretAccessKey` |
| `loki-chunks` Garage bucket | Chunks and TSDB index |
| `loki-rules-temp` Garage bucket | Ruler data |
| `loki-admin` Garage bucket | Administrative data |

The claim grants read/write access only to those three Garage buckets and
disables the username-named bucket. `loki.global.extraEnv` injects the stable
User Secret references for endpoint and credentials into every microservice.
The chunks bucket is fixed to `loki-chunks`; the config uses an empty session
token because Garage service-account keys do not use temporary tokens. Loki
uses region `garage`, HTTPS through the
`observability-garage-s3` route, and path-style addressing. The schema remains
TSDB `v13` from `2024-04-01`, prefix `loki_index_`, with a 24-hour period.

This is a fresh store, matching the Mimir Garage cutover. Existing MinIO
buckets and Loki objects are not copied, queried, or deleted. MinIO resources
created by the previous `User` Composition use orphan retention; inspect them
separately before any later cleanup. The old single-binary PVCs also remain
retained for recovery.

The local Garage endpoint is selected from each cluster's domain, so both Loki
deployments write through site-local Garage while federation maintains the
shared object-storage layout. This is the intended cross-site durability
mechanism; Loki itself must not be treated as the replication layer. Loki's
`S3_ENDPOINT` is sourced from the
credential Secret's `AWS_ENDPOINTS` key, preserving the scheme and endpoint
format generated by the Garage operator.
Grafana documents TSDB as the
[recommended single-store index](https://grafana.com/docs/loki/latest/operations/storage/tsdb/)
and describes schema continuity in the
[storage schema guide](https://grafana.com/docs/loki/latest/operations/storage/schema/).

Ingester WAL, index-gateway, compactor, and ruler working data use PVCs. The
supported retention policies are `Retain`; former `storage-loki-core-*` PVCs
also remain retained for rollback and need a separate cleanup decision. S3
remains the durable store.

Distributed Loki components retain chart-provided PodDisruptionBudgets and
rolling-update limits. Ingesters use the chart's zone-aware StatefulSets and a
long termination grace period; distributors, gateways, queriers, query
frontends, and schedulers run with multiple replicas so reads and writes remain
available during node drains and controlled scale changes. See the upstream
[Loki Helm zone-aware replication guidance](https://grafana.com/docs/loki/latest/setup/install/helm/concepts/)
and [hash-ring guidance](https://grafana.com/docs/loki/latest/get-started/hash-rings/).

## Retention, monitoring, and access

The existing 31-day retention and 24-hour `{env="testing"}` override remain.
One compactor enforces retention and keeps delete requests in S3. Do not run a
second compactor against this store.

Loki Canary runs on every node and the parent chart creates a
[`ServiceMonitor`](templates/ServiceMonitor.yaml) for component metrics. The
clustered Alloy deployment discovers it and writes the metrics to Mimir.
Verify the canary write/read loop and component metrics;
readiness alone does not prove S3 ingestion or querying.

External access uses
`logs.<cluster>.<datacentre>.<region>.<externalDomain>`. The
[`SecurityPolicy`](templates/SecurityPolicy.yaml) validates the configured
Authentik issuers, requires `oauth.allowedGroups`, and forwards `orgID` as
`X-Scope-OrgID`. Loki runs with `auth_enabled: true`, so every API request must
carry a tenant ID in `X-Scope-OrgID`. Kubernetes tenants are derived from the
cluster's `mylogin.space/tenant` label (currently `core.mylogin.space` maps to
`core`); the Alloy writers use that tenant ID. This header selects an isolated
Loki tenant; it is not caller authentication by itself. The public route
continues to rely on Envoy JWT validation and the allowed Authentik groups for
caller authentication and authorization. See Loki's
[multi-tenancy](https://grafana.com/docs/loki/latest/operations/multi-tenancy/)
and [authentication](https://grafana.com/docs/loki/latest/operations/authentication/)
guides.

The chart Canary uses its separate `self-monitoring` tenant when auth is
enabled, as described in the [Loki Canary guide](https://grafana.com/docs/loki/latest/operations/loki-canary/).

Logs written before tenant authentication was enabled were stored in Loki's
single-tenant `fake` tenant because Loki ignored tenant headers in that mode.
They remain in the existing S3 buckets and are not visible to normal `core`
tenant queries. This change does not copy, delete, or expose those historical
objects. Any later migration or historical-query access to `fake` needs a
separate reviewed plan.

## Validation and operations

The production route is JWT protected at `logs.mylogin.space` through K8GB.
Each site also serves it at `logs.gslb.mylogin.space`; only that site route
carries the `wan-mode: 'public'` label and ExternalDNS hostname annotations.
The K8GB `Gslb` owns the global record. See the [K8GB resource reference](https://www.k8gb.io/latest/resource_ref/),
[K8GB dynamic zones](https://www.k8gb.io/latest/dynamic_zones/), and
[ExternalDNS Gateway API source](https://github.com/kubernetes-sigs/external-dns/tree/master/provider/kubernetes-sources).

Resolve the ignored dependency locally and render both fleet roles:

```bash
helm dependency build Observability/Logs
helm lint Observability/Logs --strict
helm template logs Observability/Logs --namespace core-prod
helm template logs Observability/Logs --namespace core-prod \
  --set loki.gateway.replicas=0 --set loki.distributor.replicas=0 \
  --set loki.ingester.replicas=0 --set loki.querier.replicas=0 \
  --set loki.queryFrontend.replicas=0 --set loki.queryScheduler.replicas=0 \
  --set loki.indexGateway.replicas=0 --set loki.compactor.replicas=0 \
  --set loki.ruler.replicas=0
```

Inspect the rendered config and workloads. On YXL, confirm all Loki processes
receive the User Secret references, fixed chunks bucket, and expansion flag;
the User claim must specify the Garage backend and service account. On Home1,
confirm Loki remains disabled and its MinIO claim is unchanged. Internal
addresses must use the component Services, stateful PVCs must retain,
`loki-core` must select gateway pods on port `3100`, and only the intended
global Service has global annotations.

After reconciliation, verify DC1 replica and ring health, ingestion from both
sites into tenant `core`, an existing query within `core`, a new uniquely
labelled stream, compactor/ruler S3 access, Canary success, Mimir metrics,
synchronized Home1 endpoints, accepted route/policy conditions, rejection of
requests without a tenant header, and rejection of an unauthenticated public
query. Historical `fake` data remains stored but outside normal `core`
queries. Do not print production logs, generated bucket names, or credentials.

## Migration and recovery

Chart 6.46.0 cannot run SingleBinary and Distributed targets together. The
rollout follows Grafana's
[SSD-to-Distributed migration guide](https://grafana.com/docs/loki/latest/setup/migrate/ssd-to-distributed/)
through supported transitions:

1. `SingleBinary<->SimpleScalable`: run the existing three single-binary
   replicas alongside the simple-scalable targets. `loki-core` remains on the
   single-binary Service while the S3-backed targets warm up.
2. `SimpleScalable<->Distributed`: after stage one is healthy, remove the
   single-binary target, start all Distributed components beside the scalable
   targets, and point the same `loki-core` Service at the chart gateway.
3. `Distributed`: after checking ingestion and queries through the stable
   Service, scale the simple-scalable targets to zero.

The ingester flushes its WAL on shutdown. The transition requires temporary
capacity for both topologies, which was checked on YXL before rollout. Keep the
old retained single-binary PVCs through the observation window. Verify each
stage before publishing/reconciling the next one; the next stage is not
automatically applied until its health checks pass.

If validation fails, restore the prior Git revision and point `loki-core` back
to the three ready single-binary pods before removing distributed workloads.
That revision uses the existing MinIO `User` claim again. MinIO objects and
retained PVCs are left in place, but the stores are not synchronized: writes
made after cutover remain in Garage and will not appear after rollback. The
Garage buckets have Retain deletion policy; check the User Composition's key
deletion behavior before reverting the claim, and preserve the buckets until
they are no longer needed. Home1 remains dependent on DC1 and ClusterMesh;
this change does not add a second serving site.
