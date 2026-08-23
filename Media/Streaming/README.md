# Media Streaming

This Helm rendering unit deploys [Jellyfin](https://jellyfin.org/docs/),
[Stash](https://docs.stashapp.cc/), their persistent storage, Services, and
public Gateway API routes through the
[`bjw-s/common` library chart](https://github.com/bjw-s-labs/helm-charts/tree/main/charts/library/common).
`Apps/Media/Streaming.yaml` owns the Argo CD ApplicationSet, currently selects
only `core-home1-talos-prod`, injects the `augy` media tenant, and deploys the
release into `core-media`.

## Streaming and WebSockets

Jellyfin is exposed at `stream.mylogin.space`; Stash is exposed at
`accessmyporn.download`. Both Service ports declare the Gateway API
[`kubernetes.io/ws` application protocol](https://gateway-api.sigs.k8s.io/guides/user-guides/backend-protocol/)
so Envoy uses a WebSocket-capable HTTP/1.1 upstream. This is required for the
[Jellyfin WebSocket workflow](https://jellyfin.org/docs/general/post-install/networking/reverse-proxy/#websockets)
and also preserves Stash's upgraded connections.

The shared Envoy Gateway
[`BackendTrafficPolicy`](https://gateway.envoyproxy.io/v1.8/concepts/gateway_api_extensions/backend-traffic-policy/)
targets both generated HTTPRoutes. Its HTTP request, maximum stream, and stream
idle timeouts are all `0s`, which disables those limits so long media responses
and upgraded connections are not terminated by Envoy. Application-side,
client-side, load-balancer, and network idle limits remain independent and can
still end a session.

Stash's route is protected by Authentik and restricted to the `Private Stash`
group; see `Media/AUTHENTIK.md` for ownership, prerequisites, verification, and
removal behavior. Jellyfin retains its existing public access model.

## Verification and rollback

After Argo CD reconciliation, verify both HTTPRoutes are `Accepted`, the
BackendTrafficPolicy is attached to both route names, and both Services render
`appProtocol: kubernetes.io/ws`. Test a Jellyfin playback longer than the prior
proxy timeout, Jellyfin's `/socket` WebSocket, a long Stash stream, and a Stash
WebSocket upgrade through the public hosts. Check Envoy access logs and route
status alongside the application behavior; pod readiness alone is not enough.

Rolling back the timeout fields restores Envoy's inherited timeout behavior.
Rolling back `appProtocol` removes the explicit WebSocket upstream selection.
Neither rollback changes persisted media or application configuration, but it
can interrupt active streams and upgraded connections when reconciliation
updates Envoy.
