# Mimir metrics store

This chart deploys [Grafana Mimir](https://grafana.com/docs/mimir/latest/) in
horizontally scaled monolithic mode using the
[`bjw-s common library`](https://github.com/bjw-s-labs/helm-charts/tree/main/charts/library/common).
The pinned
[`mimir-distributed` chart](https://github.com/grafana/helm-charts/tree/main/charts/mimir-distributed)
is retained as an optional dependency but is disabled for every currently
selected cluster.

The [`core-observability-metrics` ApplicationSet](../../Apps/Observability/Metrics.yaml)
targets `core-dc1-talos-prod` (YXL) and `core-home1-talos-prod` (YVR), injects
site identity, and enables the monolithic implementation. Three Mimir replicas
receive Prometheus remote write, keep WAL/head working data in memory-backed
`emptyDir`, and ship blocks to site-local S3. The chart also creates the S3
`User`, Authentik workspace and Secret synchronization, HTTPRoute, and Envoy
SecurityPolicy.

Production marks the Mimir HTTP Service as a [Cilium global service with EndpointSlice
synchronization](https://docs.cilium.io/en/stable/network/clustermesh/global-services/#synchronizing-kubernetes-endpointslice)
in the ApplicationSet. The Service is explicitly named `core-mimir` in the `core-prod`
namespace in both clusters; this stable identity is required because Cilium
correlates global Services by namespace and name, while Lovely may derive a
different Helm release name for each generated Argo CD Application. Cilium
shares its backends and creates EndpointSlices for remote Mimir replicas.
EndpointSlice-aware push-path controllers can then use the other site's
replicas when local endpoints are unavailable. The memberlist gossip Service
remains cluster-local so the independent site-local Mimir rings and storage
lifecycles are not joined. This depends on Cluster Mesh connectivity and
`clustermesh.enableEndpointSliceSynchronization`, which the Network Base
deployment enables.

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
12-hour retention, and one concurrent block upload. Home1 uses the chart
defaults of 500,000 samples/s, a 1,550,000-sample burst, 24-hour retention, and
20 concurrent uploads. Rate limiting rejects excess samples; it does not reduce
the collectors' Kubernetes watches or guarantee an immediate drop in sender
network retries. Retention is enforced asynchronously by the compactor and
does not immediately delete existing objects.

Mimir is the destination of the monitoring data, not the origin of the high
Kubernetes API traffic. See [Collectors](../Collectors/README.md) for the API
watch fan-out and [Exporters](../Exporters/README.md) for the highest-volume
metric sources.

Verify distributor accepted/rejected samples, active series, ingester WAL/head
size, block upload duration, compactor deletion markers, S3 throughput, and an
end-to-end query in Grafana. Also verify that the Mimir Service has local and
remote EndpointSlices and test remote-write delivery while the local Mimir
endpoints are unavailable. Render both site profiles before merging. Rollback
through Git/Argo CD; removing the global-service annotations stops new remote
EndpointSlice synchronization, while increasing retention does not restore
blocks already deleted and lowering rate limits creates intentional monitoring
gaps.
