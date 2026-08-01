# Resource operations deployment

This deployment installs Goldilocks and Descheduler and exposes Goldilocks
through Authentik/Gateway policy. It is owned by
`Apps/Infra/Resources.yaml`.

Each selected infrastructure cluster creates its own Terraform
[`authentik_provider_proxy` and `authentik_application` resources](https://registry.terraform.io/providers/goauthentik/authentik/2025.10.1/docs)
through a Crossplane `Workspace`. The application is filed under the
`<datacenter>-<cluster>` Authentik group and grants access to the existing
`Server Admins` group. The generated provider host and application slug include
the cluster identity, so reconciliation remains scoped to that cluster. The
ApplicationSet supplies `cluster.domain` for in-cluster DNS and separately sets
the public `domain` to `resolvemy.host` for the Goldilocks route and Authentik
proxy provider. The proxy provider name is scoped by environment, region, and
cluster, while the application display name remains `Goldilocks`.

The Goldilocks `HTTPRoute` is protected by an Envoy Gateway
[`SecurityPolicy` external-authorization check](https://gateway.envoyproxy.io/v1.8/tasks/security/ext-auth/)
against the shared Authentik proxy service in `core-prod`. Source-IP consistent
hashing keeps a client on the same proxy replica so Authentik's local
authorization/session cache can be reused. Successful authorization responses
forward Authentik identity, authorization, redirect, and cookie headers to
Goldilocks.

Goldilocks/VPA recommendations are advisory unless another process applies
them. Descheduler can evict workloads across the cluster. Review policies,
eviction limits, PDBs, priority classes, local storage and maintenance windows
before enabling new strategies.

Verify the Terraform `Workspace` is `Ready`, then confirm the Authentik proxy
provider, application grouping, entitlement, and policy bindings. Verify the
`SecurityPolicy` is accepted and attached to the Goldilocks `HTTPRoute`, and
test both an authorized `Server Admins` session and an unauthorized session
through the public hostname. Removing the release removes the Kubernetes
workspace and policy; allow the Terraform workspace deletion to finish so its
Authentik resources are destroyed before forcing finalizer removal.

Validate recommendations against observed workload behavior and canary
descheduling on non-critical workloads before fleet rollout.
