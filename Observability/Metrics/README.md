# Mimir metrics store

This chart deploys [Grafana Mimir](https://grafana.com/docs/mimir/latest/) in
horizontally scaled monolithic mode using the
[`bjw-s common library`](https://github.com/bjw-s-labs/helm-charts/tree/main/charts/library/common).
The pinned
[`mimir-distributed` chart](https://github.com/grafana/helm-charts/tree/main/charts/mimir-distributed)
is retained as an optional dependency but is disabled for every currently
selected cluster.

The [`core-observability-metrics` ApplicationSet](../../Apps/Observability/Metrics.yaml)
targets `core-dc1-talos-prod` (YXL) and `core-home1-talos-prod` (YVR) and injects
site identity. YXL enables the monolithic implementation; Home1 enables only
the Mimir bridge described below. Three YXL Mimir replicas receive Prometheus
remote write, keep WAL/head working data in memory-backed `emptyDir`, and ship
blocks to site-local S3. The YXL rendering also creates the S3 `User`,
HTTPRoute, and Envoy SecurityPolicy.

The Mimir Deployment uses [Reloader's targeted Secret annotation](https://github.com/stakater/Reloader#how-to-use-reloader)
to roll when either generated S3 Secret changes. `*-s3-creds` provides the
access key, secret key, and session token; `*-creds` provides the bucket name.
Reloader changes only the Mimir pod template, and the three-replica rolling
strategy, readiness probe, and PodDisruptionBudget keep serving replicas
available during credential rotation. The target cluster must run Reloader;
the operations configuration ApplicationSet provides it on both selected
Talos production clusters.

Production renders both Service roles through the bjw-s common library.
`core-mimir` is the stable site-local client Service: it selects Mimir Pods in
YXL and the bridge Pods in Home1. `core-mimir-global` is a [Cilium global service with
EndpointSlice synchronization](https://docs.cilium.io/en/stable/network/clustermesh/global-services/#synchronizing-kubernetes-endpointslice)
configured by the ApplicationSet. YXL exports the local Mimir backends with
local affinity and sharing enabled. Home1 declares the same global Service
identity with remote affinity and sharing disabled. Its common-chart Service
has a deliberately non-matching selector, so only Cilium-synchronized remote
EndpointSlices back it and the bridge cannot proxy recursively to itself.
Cilium correlates global Services by namespace and name, while Lovely may
derive a different Helm release name for each generated Argo CD Application.
The memberlist gossip Service remains YXL-local and is not part of ClusterMesh.
This depends on Cluster Mesh connectivity and
`clustermesh.enableEndpointSliceSynchronization`, which the Network Base
deployment enables.

Home1 also renders a two-replica `core-mimir-proxy` Deployment and the local
`core-mimir` ClusterIP Service, along with the NGINX ConfigMap, through
the bjw-s common library. This preserves Headlamp's KubeVirt plugin endpoint at
`/api/v1/namespaces/core-prod/services/core-mimir:8080/proxy/prometheus`.
The Kubernetes API server proxies to a locally visible proxy Pod; the proxy
then uses [NGINX `proxy_pass` without a URI](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_pass)
to forward the complete path and query string to the namespace-local
`http://core-mimir-global:8080` Service reference. No Kubernetes
cluster-domain suffix is generated. The proxy forwards `X-Scope-OrgID`,
removes the incoming `Authorization` header, and serves `/healthz` locally
without contacting YXL.
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
forwards to the loopback-only filter listener before it contacts
`core-mimir-global`. NGINX removes Mimir's `/prometheus` prefix so the filter
recognizes the Prometheus API path, and the filter restores that
prefix in its upstream URL. Disabling `mimirBridge.queryFilter` restores direct
bridge forwarding.

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
end-to-end query in Grafana. In YXL, verify `core-mimir-global` selects the
Mimir Pods and is exported by Cilium. In Home1, verify its backends are remote,
both proxy Pods are ready, `/healthz` remains available during a YXL outage,
and the unchanged Headlamp endpoint returns a Mimir query response with the
expected tenant. Also confirm proxy logs do not expose credentials. After
rotating each YXL S3 Secret, verify that Mimir rolls one pod at a time, all
replacement pods become ready, and block uploads and queries continue without
authentication errors. Render both site profiles before merging. Roll back
through Git/Argo CD. Disabling the bridge removes the local `core-mimir`
Service and breaks the Headlamp endpoint; removing the global-service
annotations stops new remote backend synchronization. Increasing retention
does not restore blocks already deleted, and lowering rate limits creates
intentional monitoring gaps.
