# Media Streaming

This Helm rendering unit deploys [Jellyfin](https://jellyfin.org/docs/),
[Stash](https://docs.stashapp.cc/), their persistent storage, Services, and
public Gateway API routes through the
[`bjw-s/common` library chart](https://github.com/bjw-s-labs/helm-charts/tree/main/charts/library/common).
It also deploys [Jellystat](https://github.com/CyferShepard/Jellystat), a
Jellyfin statistics dashboard, at `jellystat.mylogin.space`. The container is
pinned to the upstream `1.1.11` release tag documented in the
[Jellystat container package](https://github.com/CyferShepard/Jellystat/pkgs/container/jellystat).
`Apps/Media/Streaming.yaml` owns the Argo CD ApplicationSet, currently selects
only `core-home1-talos-prod`, injects the `augy` media tenant, and deploys the
release into `core-media`.

Jellyfin's transcode workspace is a dedicated Longhorn PVC using the
[Longhorn StorageClass parameters](https://longhorn.io/docs/latest/references/storage-class-parameters/)
`diskSelector: 'ssd'` and `numberOfReplicas: '1'`. It is mounted at
`/cache` and is deleted with the PVC/StorageClass lifecycle; transcoded media
is disposable and is not a backup substitute. The StorageClass uses Longhorn's
`Delete` reclaim policy for dynamically provisioned volume cleanup. Jellyfin's
[container documentation](https://jellyfin.org/docs/general/installation/container/)
defines `/cache` as the cache volume, and `JELLYFIN_CACHE_DIR` is set
explicitly so transcoding uses it.

The chart enables Jellyfin's built-in `/metrics` endpoint in the persisted
`system.xml` and creates a Prometheus Operator
[ServiceMonitor](https://prometheus-operator.dev/docs/platform/operator/)
labelled for the repository's Mimir Prometheus selection. The endpoint is not
published as a separate route, but the existing public Jellyfin route forwards
requests to the same Service; restrict `/metrics` at the gateway or network
boundary if it must not be internet-accessible. Verify the ServiceMonitor is
selected by the target Prometheus and that `/metrics` returns a 200 response
from the in-cluster Jellyfin Service after reconciliation.

The Jellyfin container uses the documented [`/health` endpoint](https://jellyfin.org/docs/general/post-install/networking/advanced/monitoring/)
for startup, readiness, and liveness probes. The endpoint checks HTTP and
database connectivity and returns `200 OK` when healthy. Startup allows up to
five minutes for migrations; readiness and liveness then use shorter periodic
checks. Because Jellyfin's health endpoint is not reliable during startup,
readiness and liveness are held behind the startup probe.

The Stash container uses Stash's unauthenticated [`/healthz` heartbeat route](https://github.com/stashapp/stash/blob/develop/internal/api/server.go#L116)
for startup, readiness, and liveness probes. This verifies that the Stash HTTP
server is running without requiring an API key; it does not validate library
indexing or media-processing state. Startup allows up to five minutes for
initialization, with readiness and liveness using shorter periodic checks.

The public Jellyfin HTTPRoute returns a gateway-level `404` for `/metrics` and
`/health` using Envoy Gateway's [`HTTPRouteFilter` direct response](https://gateway.envoyproxy.io/latest/tasks/traffic/direct-response/).
The in-cluster ServiceMonitor and container probes continue to use those paths.

Jellystat uses the repository's [`User` claim](../../Operations/SSO/User/README.md)
to provision a dedicated PostgreSQL role and database on the site-local
PostgreSQL service (`psql-local.<cluster>.<datacenter>.<region>.mylogin.space`)
using the site-local Crossplane providers. Its connection Secret is written in
`core-media` and consumed by the workload; the JWT secret is sourced from the
same generated Secret. Backups are persisted in a dedicated PVC at
`/app/backend/backup-data`. The Jellystat route is protected by the shared
Authentik Envoy external authorization policy and the configured
`authentik.accessGroups` group (`Private Stash` in the current values).

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
WebSocket upgrade through the public hosts. Verify the public Jellyfin
`/metrics` and `/health` paths return `404`, while the in-cluster Service still
serves `/health` and `/metrics`. Check Envoy access logs and route status
alongside the application behavior; pod readiness alone is not enough.

Rolling back the timeout fields restores Envoy's inherited timeout behavior.
Rolling back `appProtocol` removes the explicit WebSocket upstream selection.
Neither rollback changes persisted media or application configuration, but it
can interrupt active streams and upgraded connections when reconciliation
updates Envoy.
