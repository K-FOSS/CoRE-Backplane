# Music

This chart deploys Lidarr to the `core-media` namespace for the media tenant
selected by `Apps/Media/Music.yaml`. The ApplicationSet currently selects the
`core-home1-talos-prod` infrastructure cluster and injects tenant `augy` through
the [Lovely Helm merge layer](https://github.com/crumbhole/lovely-vault-plugin#readme).
The chart uses the bjw-s-labs
[Common Library](https://bjw-s-labs.github.io/helm-charts/docs/) to generate its
workload, storage, service, and route resources.

## Access and identity

The public `music.mylogin.space` `HTTPRoute` forwards to Lidarr and is protected
by an Envoy Gateway `SecurityPolicy`. Envoy sends authorization checks to the
shared Authentik proxy outpost; the Crossplane Terraform `Workspace` creates a
single-application forward-auth provider, a Lidarr application, and bindings for
the `Media Consumers` group. See Authentik's
[single-application forward-auth documentation](https://docs.goauthentik.io/add-secure-apps/providers/proxy/forward_auth/)
and the Authentik Terraform provider's
[`authentik_provider_proxy` documentation](https://registry.terraform.io/providers/goauthentik/authentik/2025.10.1/docs/resources/provider_proxy),
and Envoy Gateway's
[external authorization documentation](https://gateway.envoyproxy.io/v1.8/tasks/security/ext-auth/).

The Lidarr pod and process use UID and GID `911`. `PUID`, `PGID`, and `TZ` are
set to `911`, `911`, and `America/Vancouver`, respectively, following the
[hotio Lidarr image configuration](https://hotio.dev/containers/lidarr/).
Current values select the mutable `pr-plugins` image tag, so a new upstream
image can be deployed without a Git change.
The `augy-media` and `augy-downloads` claims must allow this identity to access
their mounted content.

## Reconciliation and verification

Argo CD renders this directory with the injected tenant and reconciles the
Deployment, Service, `HTTPRoute`, `SecurityPolicy`, and Terraform `Workspace`.
The Workspace then reconciles the Authentik provider, application, entitlement,
and group bindings. Verify all of the following after sync:

```sh
kubectl -n core-media get deploy,service,httproute,securitypolicy,workspace
kubectl -n core-media get httproute -o yaml
kubectl -n core-media get securitypolicy -o yaml
kubectl -n core-media get workspace -o yaml
```

Confirm that the route and policy report accepted/attached conditions, the
Workspace reports successful reconciliation, an unauthorized request redirects
through Authentik, a `Media Consumers` member can open Lidarr, and Lidarr can
read and write its config, media, and download paths. Resource readiness alone
does not prove that authentication or storage permissions work.

## Rollback and removal

Revert the route, policy, Workspace, and values together to remove proxy
protection. Removing the Workspace can delete externally managed Authentik
objects according to the provider's deletion policy, so inspect its conditions
and deletion behavior before syncing a removal. The ApplicationSet preserves
application resources on deletion; removing the ApplicationSet is therefore not
proof that either Kubernetes or Authentik resources were deleted.
