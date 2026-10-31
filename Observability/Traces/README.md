# CoRE-Backplane Observability/Traces Stack

This stack deploys Grafana Tempo in microservices mode with site-local S3
storage and a Cilium global `tempo-core` Service. It is owned by the
[`core-observability-traces` ApplicationSet](../../Apps/Observability/Traces.yaml)
and follows the same active-site/remote-site model as
[Logs](../Logs/README.md) and [Metrics](../Metrics/README.md). The pinned
[Grafana Community `tempo-distributed` chart](https://github.com/grafana-community/helm-charts/tree/main/charts/tempo-distributed)
provides the Tempo services; its [microservices deployment documentation](https://grafana.com/docs/tempo/latest/set-up-for-tracing/setup-tempo/deploy/kubernetes/helm-chart/)
and [storage configuration reference](https://grafana.com/docs/tempo/latest/configuration/#storage)
describe the upstream behavior.

## Ownership, targets, and site selection

The ApplicationSet selects bare-metal production clusters for the `core` tenant
and merges a site profile by cluster name:

- YXL runs the Tempo distributor, ingesters, queriers, query frontend,
  compactor, and gateway. Its trace bucket uses the shared Garage endpoint.
- Home1 runs no local Tempo pods. It publishes the same `tempo-core` global
  Service as a remote endpoint, so Cilium can select the active site through
  `service.cilium.io/affinity` without changing collector or Grafana addresses.

Switching the active site is an ApplicationSet profile change. Review the
selected replicas, Garage/S3 backend, Cilium affinity, and downstream collector
path together before reconciliation.

## Storage and credentials

The `User` claim provisions the `tempo-traces` bucket and writes the stable
`tempo-core` connection Secret plus `tempo-core-s3-creds`. YXL uses a Garage
service account; the remote profile keeps the provider-backed S3 credential
path available for recovery. Tempo expands the `S3_ENDPOINT`,
`S3_ACCESS_KEY`, and `S3_SECRET_ACCESS_KEY` environment variables at runtime;
secret values are never stored in Git.

Tempo trace blocks remain authoritative in S3; the chart's local WAL and
working directories are ephemeral in this profile. The chart's Tempo 3 Kafka-backed `blockBuilder` and
`liveStore` components are disabled because the observability deployment uses
the established memberlist and ingester microservices path; enabling them
requires a reviewed Kafka endpoint, partition sizing, and credentials.

## Routing and telemetry flow

Collectors export OTLP/gRPC to
`tempo-core.core-<environment>.svc.<cluster-domain>:4317` and send the derived
tenant in `X-Scope-OrgID`. The global Service selects the local Tempo gateway
when active and synchronized remote endpoints otherwise. The public
`traces.mylogin.space` HTTPRoute targets that same Service on port `3200` and
is protected by an Envoy Gateway JWT SecurityPolicy requiring the `Traces`
group.

## Operations and verification

Build and validate locally with:

```bash
helm dependency build Observability/Traces
helm lint Observability/Traces --strict
helm template traces Observability/Traces --namespace core-prod \
  --set 'tempo-distributed.enabled=true'
```

After reconciliation, verify the `tempo-core` Service has the expected local
or synchronized EndpointSlices, all active Tempo components are Ready, the
`User` claim and generated S3 Secrets are Ready, and the `tempo-traces` bucket
is available. Then send an OTLP trace through Alloy, confirm it is written to
Garage/S3, query it through the protected route, and test the active-site
affinity and remote-site failover path.

Removing the chart does not by itself prove that the external S3 bucket,
credentials, or stored traces were deleted. Inspect the `User` composition,
provider resources, finalizers, and bucket deletion policy before cleanup.
