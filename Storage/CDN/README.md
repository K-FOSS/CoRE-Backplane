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
expected bucket is served. `preserveResourcesOnDeletion` remains enabled, so
removing a cluster or site from the matrix removes its generated Application
but deliberately leaves previously managed Kubernetes resources behind; delete
those resources separately only after confirming they are no longer needed.
