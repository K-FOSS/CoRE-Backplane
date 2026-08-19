# Media forward authentication

The Sonarr (`Media/TV`), Radarr (`Media/Movies`), and SABnzbd (`Media/NZB`)
public routes are protected by Authentik single-application forward auth. Their
owning ApplicationSets are `Apps/Media/TV.yaml`, `Apps/Media/Movies.yaml`, and
`Apps/Media/NZB.yaml`; all currently select the `core-home1-talos-prod` bare
metal infrastructure cluster and deploy into `core-media`.

Each chart creates a Crossplane Terraform
[`Workspace`](https://marketplace.upbound.io/providers/upbound/provider-terraform/v0.20.1)
using the existing `authentik` ProviderConfig. Its inline module creates an
[`authentik_provider_proxy`](https://registry.terraform.io/providers/goauthentik/authentik/2025.10.1/docs/resources/provider_proxy)
in `forward_single` mode, an Authentik application filed under `Media`, a
`media-access` entitlement, and bindings for every configured `accessGroups`
entry. The default and current access group is `Media Consumers`. The proxy's
external host is the corresponding `tv`, `movies`, or `nzb` public hostname.
Authentik's [forward-auth documentation](https://docs.goauthentik.io/add-secure-apps/providers/proxy/forward_auth)
describes why separate providers preserve per-application policy boundaries.

Each chart also attaches a fail-closed Envoy Gateway
[`SecurityPolicy`](https://gateway.envoyproxy.io/v1.8/tasks/security/ext-auth/)
to its generated `HTTPRoute`. Envoy sends the request cookie to the shared
`aaa-myloginspace-proxy` service in `core-prod`, using Authentik's
[`/outpost.goauthentik.io/auth/envoy` endpoint](https://docs.goauthentik.io/add-secure-apps/providers/proxy/server_envoy/).
Successful checks forward Authentik identity, authorization, redirect, and
cookie headers to the application. Source-IP consistent hashing preserves the
proxy outpost's local session cache. The Authentik deployment owns the
cross-namespace `ReferenceGrant` permitting `core-media` SecurityPolicies to
reference only the named shared proxy and Authentik server Services.

## Prerequisites and reconciliation

The target cluster must have the `tf.upbound.io/v1beta1` Workspace and
`gateway.envoyproxy.io/v1alpha1` SecurityPolicy CRDs, the `authentik`
ProviderConfig and its secret-backed credentials, the Authentik authorization
and invalidation flows named in the modules, the `Media Consumers` group, the
shared proxy service, the accepted shared `/outpost.goauthentik.io` route, and
the public Gateway listeners. No Authentik token or application secret is
stored or published by these charts.

Argo CD first applies the rendered Workspace, HTTPRoute, SecurityPolicy, and
ReferenceGrant. Crossplane then reconciles the Authentik provider,
application, entitlement, and bindings. Envoy Gateway accepts the policy only
after its target route and cross-namespace backend reference resolve. Because
`failOpen` is false, an unavailable or unauthorized Authentik check denies
access rather than bypassing authentication.

Verify the Workspace `Ready` condition and inspect its provider logs if
Terraform fails. In Authentik, verify the external host, application grouping,
entitlement, and `Media Consumers` bindings. Then verify the HTTPRoute is
`Accepted`, the SecurityPolicy is attached without resolution errors, an
unauthenticated browser is redirected to Authentik, an authorized Media
Consumer can load the application, and an unauthorized account is denied.
Application pod readiness alone does not validate the access path.

Disabling `authentik.route.enabled` removes the Envoy enforcement and must be
treated as a public access-model change. Disabling `authentik.autoconfigure`
leaves routing enforcement enabled but stops this release from declaring the
Authentik resources; do so only when another owner manages an equivalent
provider and application. Removing a release normally causes its Workspace to
destroy the Authentik resources, but the ApplicationSets preserve resources on
deletion. Confirm Terraform destroy completed before removing finalizers, and
retain emergency cluster access that does not depend on Authentik or public
DNS.
