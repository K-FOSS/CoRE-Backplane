# Storage CDN chart

This chart exposes selected S3 buckets through HTTP using the `s3-proxy`
dependency. It is owned by `Apps/Storage/CDN.yaml`.

It includes bucket routes, Vault-backed access credentials and a service-level
objective resource. The SLO is rendered only when `slo.enabled` is `true`; the
owning ApplicationSet enables it for `core-home1-talos-prod` and disables it
for the other declared clusters. The current dependency alias is `idle`;
inspect injected values and enabled state before assuming every configured
bucket is active.

Dependencies include reachable S3 endpoints, bucket users/policies,
Vault/External Secrets, Gateway API, DNS/TLS and observability CRDs.

Validate authorization, object cache semantics, content type/range requests,
large objects, private-object denial, upstream failure behavior and SLO
metrics. Never expose a private bucket merely by adding an HTTP route.
