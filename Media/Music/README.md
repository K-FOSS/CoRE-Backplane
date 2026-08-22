# Music

This chart deploys Lidarr to the `core-media` namespace for the media tenant
selected by `Apps/Media/Music.yaml`. The ApplicationSet currently selects the
`core-home1-talos-prod` infrastructure cluster and injects tenant `augy` through
the [Lovely Helm merge layer](https://github.com/crumbhole/lovely-vault-plugin#readme).
The chart uses the bjw-s-labs
[Common Library](https://bjw-s-labs.github.io/helm-charts/docs/) to generate its
workloads, storage, services, and route resources.

## YouTube trusted sessions

The chart also deploys the
[BgUtils PO-token provider](https://github.com/Brainicism/bgutil-ytdlp-pot-provider#readme)
as the internal `yt-session` service. Version `1.3.2` and its image digest are
pinned; see the upstream
[1.3.2 release notes](https://github.com/Brainicism/bgutil-ytdlp-pot-provider/releases/tag/1.3.2).
The service generates YouTube proof-of-origin tokens on demand and exposes the
upstream [`/ping` and `/get_pot` HTTP API](https://github.com/Brainicism/bgutil-ytdlp-pot-provider/tree/1.3.2/server#server)
on port `4416`. It has no public `HTTPRoute` and runs as the image's non-root
UID/GID `1000` with a read-only root filesystem and all Linux capabilities
dropped.

Configure Lidarr's compatible YouTube/Tubifarry downloader to use:

```text
http://core-home1-talos-prod-media-music-augy-prod-yt-session:4416
```

The consumer must support the BgUtils HTTP provider protocol; this is not the
API of the deprecated Invidious trusted-session generator. Tokens are cached in
memory and are not persisted. They are tied to YouTube request context and
network reputation, so the provider and Lidarr must continue to reach YouTube
through compatible public egress. No YouTube cookies or generated tokens belong
in Git; supply cookies separately through the existing application workflow if
the downloader requires them.

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
Deployments, Services, `HTTPRoute`, `SecurityPolicy`, and Terraform `Workspace`.
The Workspace then reconciles the Authentik provider, application, entitlement,
and group bindings. Verify all of the following after sync:

```sh
kubectl -n core-media get deploy,service,httproute,securitypolicy,workspace
kubectl -n core-media get deploy -l app.kubernetes.io/controller=yt-session
kubectl -n core-media get service/core-home1-talos-prod-media-music-augy-prod-yt-session
kubectl -n core-media port-forward service/core-home1-talos-prod-media-music-augy-prod-yt-session 4416:4416
curl --fail --show-error http://127.0.0.1:4416/ping
kubectl -n core-media get httproute -o yaml
kubectl -n core-media get securitypolicy -o yaml
kubectl -n core-media get workspace -o yaml
```

Confirm that the route and policy report accepted/attached conditions, the
Workspace reports successful reconciliation, an unauthorized request redirects
through Authentik, a `Media Consumers` member can open Lidarr, and Lidarr can
read and write its config, media, and download paths. Also confirm that `/ping`
reports version `1.3.2` and test the configured YouTube downloader from Lidarr;
provider readiness alone does not prove token generation or YouTube access works.

## Rollback and removal

Revert the route, policy, Workspace, and values together to remove proxy
protection. Removing the Workspace can delete externally managed Authentik
objects according to the provider's deletion policy, so inspect its conditions
and deletion behavior before syncing a removal. The ApplicationSet preserves
application resources on deletion; removing the ApplicationSet is therefore not
proof that either Kubernetes or Authentik resources were deleted.

Disabling `youtubeSessionGenerator.enabled` removes its Deployment and Service.
Because its cache is memory-only, rollback or removal discards cached tokens and
does not delete persistent data. Remove the provider URL from Lidarr before
disabling the service so the downloader does not retain a dead dependency.
