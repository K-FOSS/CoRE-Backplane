# CoRE-Backplane Observability/Traces Stack

This stack deploys Grafana Tempo in microservices mode with one shared,
federated Garage S3 backend and Cilium-global gateway and memberlist Services.
It is owned by the
[`core-observability-traces` ApplicationSet](../../Apps/Observability/Traces.yaml)
and follows the same active-site/remote-site model as
[Logs](../Logs/README.md) and [Metrics](../Metrics/README.md). The pinned
[Grafana Community `tempo-distributed` chart 2.26.2](https://github.com/grafana-community/helm-charts/tree/tempo-distributed-2.26.2/charts/tempo-distributed)
provides Tempo 2.10.7 in microservices mode; its [microservices deployment documentation](https://grafana.com/docs/tempo/latest/set-up-for-tracing/setup-tempo/deploy/kubernetes/helm-chart/)
and [storage configuration reference](https://grafana.com/docs/tempo/latest/configuration/#storage)
describe the upstream behavior.

## Ownership, targets, and site selection

The ApplicationSet selects bare-metal production clusters for the `core` tenant
and merges a site profile by cluster name:

- YXL and Home1 run the Tempo distributor, ingesters, queriers, query frontend,
  metrics-generator, and gateway. Both sites access the same `tempo-traces`
  bucket through their site-local endpoint for the federated YXL Garage
  backend. YXL alone runs the compactor. The [Tempo metrics-generator](https://grafana.com/docs/tempo/latest/metrics-from-traces/metrics-generator/)
  runs the `local-blocks` and `span-metrics` processors so TraceQL metrics
  queries such as `rate()` and Grafana Traces Drilldown have an active
  generator ring.
- Both sites publish the same `tempo-core` gateway and
  `tempo-core-gossip-ring-global` memberlist Service identities. Local affinity
  selects the site-local gateway while synchronized EndpointSlices retain the
  other site as a failover path. The fixed `core-observability-tempo`
  memberlist cluster label keeps both releases in one active-data ring.

Switching the active site is an ApplicationSet profile change. Review the
selected replicas, Garage/S3 backend, Cilium affinity, and downstream collector
path together before reconciliation.

## Storage and credentials

The `User` claim provisions the `tempo-traces` bucket and writes the stable
`tempo-core` connection Secret plus `tempo-core-s3-creds`. Each site uses a
Garage service account scoped to the same YXL-owned `tempo-traces` bucket and
its site-local endpoint for that federated Garage backend. YXL owns bucket
creation; YVR uses the `observability-garage-yxl-credentials` reference and its
local S3 listener on port `3900` without creating another bucket. The YVR
connection uses HTTP within the cluster. Tempo expands the
`S3_ENDPOINT`, `S3_ACCESS_KEY`, and `S3_SECRET_ACCESS_KEY` environment variables at runtime;
secret values are never stored in Git. The ApplicationSet escapes the leading
`$` so Argo CD preserves these references for Tempo instead of expanding them
during manifest generation. The Garage profile enables Tempo's path-style S3
addressing because the bucket is reached through the shared cluster-domain TLS
endpoint; the provider-backed recovery profile retains virtual-hosted
addressing.

Tempo trace blocks remain authoritative in S3; the chart's local WAL and
working directories are ephemeral in this profile. This deployment remains on
the Tempo 2 ingester and compactor architecture. Tempo 3 requires a reviewed
Kafka deployment, topic sizing, credentials, and failure-domain design before
it can replace this profile.

The gateway and fixed-name memberlist Services are global for site-level query
and failover. Both releases use the same memberlist cluster label and join the
same global headless Service. Tempo ingesters advertise their current region
and use replication factor `1`, so a recent trace query may cross the inter-site
link to the active owner without synchronously copying the same spans into a
remote ingester.
`tempo-traces` in federated Garage is the cross-site durability layer. A future
Tempo 3/Kafka profile may use the shared
EventStream for ingest durability, but that is a separate reviewed migration
and is not implied by the current Tempo 2 chart. Tempo compactor ownership is
YXL-only by default; YVR is promoted only after the YXL coordinator is fenced.

Gateway host anti-affinity is preferred rather than required. This keeps the
three replicas eligible for rolling surge placement. A required
`DoNotSchedule` topology-spread constraint enforces one replica per active-site
host in steady state, preventing a routable node failure from concentrating
the global Service endpoints on one host.

## Routing and telemetry flow

Collectors export OTLP/gRPC to
`tempo-core.core-<environment>.svc.<cluster-domain>:4317` and send the derived
tenant in `X-Scope-OrgID`. The global Service selects the local Tempo gateway
when active and synchronized remote endpoints otherwise. The public
`traces.mylogin.space` HTTPRoute targets that same Service on port `3200` and
is protected by an Envoy Gateway JWT SecurityPolicy requiring the `Traces`
group.

## Operations and verification

The production route is JWT protected at `traces.mylogin.space` through K8GB.
Each site also serves it at `traces.gslb.mylogin.space`; only that site route
carries the `wan-mode: 'public'` label and ExternalDNS hostname annotations.
The K8GB `Gslb` owns the global record. See the [K8GB resource reference](https://www.k8gb.io/latest/resource_ref/),
[K8GB dynamic zones](https://www.k8gb.io/latest/dynamic_zones/), and
[ExternalDNS Gateway API source](https://github.com/kubernetes-sigs/external-dns/tree/master/provider/kubernetes-sources).

The route uses an Envoy Gateway `BackendTrafficPolicy` that prefers local-zone
Tempo gateway endpoints, actively checks `/ready`, and passively ejects
endpoints returning repeated 5xx responses before falling back to
Cilium-synchronized remote endpoints. The existing JWT SecurityPolicy remains
required. K8GB's current `roundRobin` strategy is unchanged because K8GB does
not provide zone-local DNS selection without GeoIP/EDNS0 configuration.

Build and validate locally with:

```bash
helm dependency build Observability/Traces
helm lint Observability/Traces --strict
helm template traces Observability/Traces --namespace core-prod \
  --set 'tempo-distributed.enabled=true'
```

After reconciliation, verify the `tempo-core` Service has the expected local
or synchronized EndpointSlices, all active Tempo components including the
metrics-generator are Ready, the metrics-generator ring is populated, the
`User` claim and generated S3 Secrets are Ready, and the `tempo-traces` bucket
is available. Then send an OTLP trace through Alloy, confirm it is written to
Garage/S3, query it through the protected route, exercise a TraceQL metrics
query, and test the active-site affinity and remote-site failover path.

Removing the chart does not by itself prove that the external S3 bucket,
credentials, or stored traces were deleted. Inspect the `User` composition,
provider resources, finalizers, and bucket deletion policy before cleanup.
