# CoRE-Backplane Observability/Logs Stack

This stack runs the shared Grafana Loki log store in microservices mode and
connects it to the existing S3 identity, Authentik policy, collectors, and
global client Service. The
[`core-observability-logs` ApplicationSet](../../Apps/Observability/Logs.yaml)
owns its deployment. See the [observability overview](../README.md) for its
collectors and consumers.

## Ownership, targets, and rendering

DC1/YXL is the serving and data-bearing site. Home1/YVR renders the same
`core-prod/loki-core` global Service with zero local component replicas and
uses Cilium ClusterMesh to reach DC1. The ApplicationSet injects cluster
identity, site-specific component counts, and Cilium annotations through
`LOVELY_HELM_MERGE`.

The rendering unit includes this parent chart, the pinned
[Loki chart 6.46.0 README](https://github.com/grafana/loki/blob/helm-loki-6.46.0/production/helm/loki/README.md),
its [source](https://github.com/grafana/loki/tree/helm-loki-6.46.0/production/helm/loki),
and [`kustomization.yaml`](kustomization.yaml). Loki's
[microservices mode](https://grafana.com/docs/loki/latest/get-started/deployment-modes/#microservices-mode)
is selected with `deploymentMode: Distributed`.

| Component | DC1 replicas | Home1 replicas | Workload |
| --- | ---: | ---: | --- |
| Gateway | 3 | 0 | Deployment |
| Distributor | 3 | 0 | Deployment |
| Ingester | 3 | 0 | StatefulSet |
| Querier | 3 | 0 | Deployment |
| Query frontend | 2 | 0 | Deployment |
| Query scheduler | 2 | 0 | Deployment |
| Index gateway | 2 | 0 | StatefulSet |
| Compactor | 1 | 0 | StatefulSet |
| Ruler | 1 | 0 | StatefulSet |

The simple-scalable and former single-binary targets remain at zero. Ingester
zone awareness is disabled because this is one site; hostname anti-affinity
spreads the three ingesters across its nodes.

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

Both sites set `service.cilium.io/global` and EndpointSlice synchronization.
DC1 uses local affinity and shares its endpoints; Home1 uses remote affinity
and does not share. This follows the
[Cilium global Service](https://docs.cilium.io/en/stable/network/clustermesh/global-services/)
model. Internal and memberlist Services remain local, so sites do not share a
Loki ring.

## Existing S3 data

The topology change does not create or rename storage identities, buckets,
Secrets, or schema periods. [`LokiUser.yaml`](templates/LokiUser.yaml) keeps
the `loki-s3` claim and regional provider selection.

| Existing object | Purpose |
| --- | --- |
| `loki-core` Secret | S3 endpoint and dynamically assigned chunks bucket |
| `loki-core-s3-creds` Secret | Access key, secret key, and session token |
| dynamic chunks bucket | Chunks and TSDB index |
| `loki-rules-temp` | Ruler data |
| `loki-admin` | Administrative data |

`loki.global.extraEnv` injects the same Secret keys into every microservice,
and `-config.expand-env=true` expands them. The endpoint, region, path-style
addressing, TLS behavior, and credentials are unchanged. The schema remains
TSDB `v13` from `2024-04-01`, prefix `loki_index_`, with a 24-hour period.
Grafana documents TSDB as the
[recommended single-store index](https://grafana.com/docs/loki/latest/operations/storage/tsdb/)
and describes schema continuity in the
[storage schema guide](https://grafana.com/docs/loki/latest/operations/storage/schema/).

Ingester WAL, index-gateway, compactor, and ruler working data use PVCs. The
supported retention policies are `Retain`; former `storage-loki-core-*` PVCs
also remain retained for rollback and need a separate cleanup decision. S3
remains the durable store.

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
`X-Scope-OrgID`. Loki authentication remains disabled, so trusted cluster
networking and Envoy are the access boundaries.

## Validation and operations

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

Inspect the rendered config and workloads. Confirm all Loki processes receive
the five S3 Secret references and expansion flag, internal addresses use the
component Services, stateful PVCs retain, `loki-core` selects gateway pods on
port `3100`, and only it has global annotations.

After reconciliation, verify DC1 replica and ring health, ingestion from both
sites, an existing query spanning pre-migration data, a new uniquely labelled
stream, compactor/ruler S3 access, canary success, Mimir metrics, synchronized
Home1 endpoints, accepted route/policy conditions, and rejection of an
unauthenticated public query. Do not print production logs, generated bucket
names, or credentials.

## Migration and recovery

Chart 6.46.0 cannot run SingleBinary and Distributed targets together. Apply
the final commit in controlled phases: create distributed workloads while
retaining the old StatefulSet, wait for component and ring health, switch the
stable Service selector to gateway pods, then verify new writes and old S3
queries. Prune the old StatefulSet only after these checks, and retain its PVCs
through the observation window.

If validation fails, restore the prior Git revision and point `loki-core` back
to the three ready single-binary pods before removing distributed workloads.
The unchanged S3 configuration, schema, Secrets, and PVCs allow rollback
without copying or rewriting objects. Home1 remains dependent on DC1 and
ClusterMesh; this change does not add a second serving site.
