# Storage CDN chart

This chart exposes selected S3 buckets through HTTP using the
[`s3-proxy` chart and source](https://github.com/oxyno-zeta/s3-proxy),
whose application configuration is documented in the
[`s3-proxy` documentation](https://oxyno-zeta.github.io/s3-proxy/). It is owned
by [`Apps/Storage/CDN.yaml`](../../Apps/Storage/CDN.yaml).

It includes bucket routes, Vault-backed access credentials and a service-level
objective resource. The owning ApplicationSet uses a matrix generator to deploy
every entry in its site/bucket list to both declared Talos production clusters.
`dc1-k3s-node1` is not a target. Each site entry supplies the public hostname,
bucket name, External Secrets store reference, and access-key and secret-key
remote paths/properties. Add a new site only after choosing a unique DNS-safe
`site` value because it becomes part of the HTTPRoute, Service, Secret and SLO
names. The existing `idle` site retains the legacy Application name to avoid
replacing its Argo CD ownership record; additional sites also include their
site name in the Application name.

Each proxy mounts its bucket at `/`. The `/**` resource glob applies Basic
authentication and permits `GET` requests for objects at every path depth;
in `s3-proxy` resource globs, `*` matches only one path segment. When a requested
folder contains `index.html`, the proxy serves that object as the folder index.

The proxy Service is a Cilium global service shared by both target clusters.
Its [Cilium service affinity](https://docs.cilium.io/en/stable/network/clustermesh/affinity/)
is `local`, so each cluster sends traffic only to its healthy local proxy
endpoints while any are available, then fails over to healthy endpoints from
the other cluster. EndpointSlice synchronization remains enabled because the
Gateway implementation consumes the Service through Kubernetes discovery.

The SLO is rendered only when `slo.enabled` is `true`; it is enabled for
`core-home1-talos-prod` and disabled for `core-dc1-talos-prod`. The dependency
alias remains `idle`, while `fullnameOverride` gives each rendered proxy a
site-specific name.

Dependencies include reachable S3 endpoints, bucket users/policies,
[External Secrets](https://external-secrets.io/latest/api/externalsecret/),
[Gateway API HTTPRoute](https://gateway-api.sigs.k8s.io/api-types/httproute/),
DNS/TLS and the
[`PrometheusServiceLevel` CRD](https://sloth.dev/usage/kubernetes/). The
ApplicationSet matrix behavior is documented by
[Argo CD's matrix generator documentation](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-Matrix/).

Validate authorization, object cache semantics, content type/range requests,
large objects, private-object denial, upstream failure behavior and SLO
metrics. Never expose a private bucket merely by adding an HTTP route.

After reconciliation, verify every generated Application, ExternalSecret and
proxy deployment, then request each configured URL and confirm that the
expected bucket is served. In each cluster, inspect the Cilium service with
`cilium-dbg service list --clustermesh-affinity` and confirm that local backends
are preferred and remote backends remain active. Test failover by removing all
local proxy endpoints in one cluster through a controlled Git/Argo CD change,
confirming requests continue through the remote cluster, and restoring the
local replicas. Do not test by disrupting ClusterMesh itself, because an
unreachable remote cluster can leave last-known remote backends cached.
`preserveResourcesOnDeletion` remains enabled, so
removing a cluster or site from the matrix removes its generated Application
but deliberately leaves previously managed Kubernetes resources behind; delete
those resources separately only after confirming they are no longer needed.
