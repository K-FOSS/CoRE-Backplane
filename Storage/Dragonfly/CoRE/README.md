# CoRE-Backplane Storage/Dragonfly/CoRE Stack

This chart deploys the site-local shared Dragonfly service with TLS and
PVC-backed snapshots. The [Dragonfly ApplicationSet](../../../Apps/Storage/Dragonfly/CoRE.yaml)
owns its targets; see the [Storage overview](../../README.md) for the parent stack.

## Ownership and failover

The YVR fleet target `core-home1-talos-prod` runs three replicas and receives
the same `load=testing:NoSchedule` toleration used by the PostgreSQL fleet,
allowing the Dragonfly replicas to schedule on HPC2. This is a toleration rather
than a node selector, so Kubernetes may still place replicas on other eligible
nodes. A hostname topology spread preference distributes YVR replicas across
eligible nodes when capacity permits. YXL and other targets remain at two
replicas without that toleration or spread preference.

The [operator's primary Service](https://github.com/dragonflydb/dragonfly-operator/blob/v1.8.0/README.md)
selects the pod labeled `role: master`. Argo CD, Grafana, and Mastodon use its
site-local hostname, so new connections reach a promoted replica after the
operator updates that label. They cannot write directly to a replica before
promotion. Existing TCP connections can fail during promotion; application
clients must reconnect and retry. The operator's
[`enableReplicationReadinessGate`](https://github.com/dragonflydb/dragonfly-operator/issues/465)
keeps a replica unready until replication is established. The former fixed
300-second custom readiness delay is removed so rollout progress follows actual
replication state rather than an additional timer.

Before reconciling this chart, verify the live Dragonfly spec and all replica
roles, readiness, placement, and Service EndpointSlices. In YVR on 2026-11-19,
the live instance still had two replicas while this ApplicationSet requested
three; its Argo CD application was OutOfSync. Allow the third replica to reach
stable replication before proceeding with another rollout. After promotion,
check Service endpoints and Argo CD, Grafana, and Mastodon Redis errors. A
snapshot load or full synchronization can still interrupt clients, so zero
interruption is not guaranteed by replica count alone.

## Persistence and configuration

Dragonfly creates snapshots every 30 minutes in a per-replica `ssd-storage`
PVC mounted at `/data`; the chart default is `30Gi`. The optional `tiering` PVC
is a separate performance/data-tier volume and is disabled by default. See the [Dragonfly operator snapshot and
PVC documentation](https://github.com/dragonflydb/dragonfly-operator) and the [Dragonfly SSD tiering
overview](https://www.dragonflydb.io/blog/a-preview-of-dragonfly-ssd-tiering)
for the upstream behavior.

The `dragonfly-core` instance serves authenticated, TLS-enabled Redis clients
on port `6379` and a TLS-enabled Memcached-compatible listener on port `11211`
for Mimir's disposable query caches. The Mimir listener is not assigned a
logical Redis database; it uses Mimir's cache-key namespaces on the shared
Dragonfly process. The core chart's NetworkPolicy allows both ports.
PGPool does not share this service; the PostgreSQL chart owns a separate,
ephemeral Dragonfly instance with its Memcached-compatible listener enabled.
The core chart's NetworkPolicy continues to preserve existing port 6379 access.
See the [Dragonfly configuration reference](https://github.com/dragonflydb/dragonfly#configuration)
and [Dragonfly Operator repository](https://github.com/dragonflydb/dragonfly-operator).

## Logical database allocations

Each site-local `dragonfly-core` instance is configured with 256 logical Redis
databases. The allocations below apply independently to every site instance;
they are not global database numbers across clusters.

| Database | Current consumers | Purpose and ownership |
| --- | --- | --- |
| `0` | Argo CD, n8n, Grafana Live, Harbor core | Shared default database used by clients that do not expose a database selector. Harbor 1.18.2 requires its core database to remain `0`; do not allocate other new consumers here. |
| `25` | Rspamd | Dedicated mail filtering state. Owned by `Business/Mail` and allocated independently on every Mail target. |
| `51` | Kamailio TOPOS | Dedicated SIP topology state. Owned by [`Business/AVoIP`](https://slop.writemy.codes/CoRE/CoRE-Business/src/branch/main/AVoIP) and allocated independently on every AVoIP target. |
| `52` | Kamailio internal TOPOS | Dedicated topology state for the private Kamailio instance at each AVoIP site where that role is enabled. Owned by [`Business/AVoIP`](https://github.com/K-FOSS/CoRE-Backplane/blob/main/Apps/Business/AVoIP.yaml). |
| `53` | Kamailio internal WebSocket TOPOS | Dedicated topology state for the three-replica YVR internal WebSocket Kamailio instance. Owned by [`Business/AVoIP`](https://slop.writemy.codes/CoRE/CoRE-Business/src/branch/main/AVoIP). |
| `54` | Kamailio internal HA pilot TOPOS | Dedicated topology state for the three-replica YVR internal HA pilot, isolated from the active internal SBC and WebSocket edge. Owned by [`Business/AVoIP`](https://slop.writemy.codes/CoRE/CoRE-Backplane/src/branch/main/Apps/Business/AVoIP.yaml). |
| `70` | Harbor job service | Dedicated Harbor asynchronous job queue. Owned by `Development`. |
| `71` | Harbor registry | Dedicated Harbor registry metadata cache. Owned by `Development`. |
| `72` | Harbor Trivy adapter | Reserved for Harbor vulnerability-scanner cache if Trivy is enabled. Owned by `Development`. |
| `73` | Harbor | Dedicated Harbor miscellaneous application cache. Owned by `Development`. |
| `74` | Harbor cache layer | Dedicated Harbor cache layer. Owned by `Development`. |
| `80` | NetBox task workers | Dedicated NetBox RQ task queue. Owned by `Network/IPAM`. |
| `81` | NetBox web and workers | Dedicated NetBox application cache. Owned by `Network/IPAM`. |
| `90` | Forgejo queue | Dedicated Forgejo background-job queue. Owned by `Development`. |
| `91` | Forgejo cache | Dedicated Forgejo application cache. Owned by `Development`. |
| `92` | Forgejo sessions | Dedicated Forgejo session store. Owned by `Development`. |
| `132` | Grafana | Dedicated Grafana remote cache. Owned by `Observability/Dashboards`; Grafana Live remains on DB `0`. |
| `133` | Immich Photos | Dedicated Immich job queue and cache. Owned by `Media/Photos`. |
| `150` | OpenWebUI cache | Dedicated OpenWebUI application cache. Owned by [`Business/AI`](https://slop.writemy.codes/CoRE/CoRE-Business/src/branch/main/AI). |
| `151` | OpenWebUI websocket manager | Dedicated OpenWebUI websocket-manager state. Owned by [`Business/AI`](https://slop.writemy.codes/CoRE/CoRE-Business/src/branch/main/AI). |
| `152` | SnapOtter | Dedicated SnapOtter/BullMQ queues and processing state. Owned by [`Business/Conversions`](https://slop.writemy.codes/CoRE/CoRE-Business/src/branch/main/Tools/Conversions). |
| `153` | Dawarich | Dedicated Dawarich queues and processing state. Owned by [`Business/Personal/History`](https://slop.writemy.codes/CoRE/CoRE-Business/src/branch/main/Personal/History). |
| `154` | CoTURN | Dedicated CoTURN allocation/status state. Owned by [`Network/NATPuncher`](https://slop.writemy.codes/CoRE/CoRE-Backplane/src/branch/main/Network/NATPuncher). |
| `189` | n8n | Dedicated n8n external Redis state. Owned by [`Business/Automation`](https://slop.writemy.codes/CoRE/CoRE-Business/src/branch/main/Automation). |

The [Sharing chart](https://slop.writemy.codes/CoRE/CoRE-Business/src/branch/main/Tools/Sharing)
uses logical database `2` on a separate, chart-owned Dragonfly instance. It is
not part of the shared `dragonfly-core` allocation table above; the dedicated
instance provides independent credentials and lifecycle for Kutt and Zipline.

Numeric databases prevent accidental key collisions but are not a security or
resource-isolation boundary: all consumers still share the Dragonfly process,
password, memory limit, persistence, and failure domain. Allocate a documented,
unused database number for every new client that supports selection. Use a
separate Dragonfly instance when a workload needs independent credentials,
capacity, lifecycle, or recovery behavior.

CoTURN uses database `154` for its Redis status/statistics store. It connects to
the site-local TLS endpoint with the `dragonfly-core-password` Secret; the
password is injected at container startup and is never stored in the rendered
ConfigMap. See the [CoTURN Redis configuration reference](https://github.com/coturn/coturn/blob/master/examples/etc/turnserver.conf)
and [Dragonfly TLS documentation](https://www.dragonflydb.io/docs/managing-dragonfly/configuring-tls)
for the upstream connection behavior.

The Crossplane `User` claim still creates the site-local bucket and a long-lived
MinIO service account for the chart's S3 integration. The SSO User Composition publishes its
`AccessKey`/`SecretAccessKey` to `dragonfly-core-s3-service-account-creds`,
which is retained for that integration. Snapshots are now stored on the PVC,
so the PVC lifecycle and capacity are part of snapshot recovery. This avoids
the seven-day temporary credential path, so operators must coordinate
service-account key rotation.
The chart's ExternalSecret and PushSecret resources handle the Dragonfly
password; a Terraform provider configuration is generated for integration.

Each instance publishes its password to the site-specific Vault path
`Storage/DragonFly/CoRE/<region>/<datacenter>/<cluster>/Creds`. Consumers must
use the path and DNS endpoint for their own target cluster. The former shared
`Storage/DragonFly/CoRE/Creds` path is a compatibility alias published only by
the YVR/Home instance (`region=yvr`, `datacenter=home1`). No other site writes
that path, preventing multiple Dragonfly passwords from racing for the legacy
key.

It depends on the Dragonfly Operator/CRDs, S3, Vault/External Secrets,
Crossplane, certificates and network reachability.

## Metrics and dashboard

The chart publishes a `PodMonitor` for pods labeled `app: dragonfly-core` and
scrapes their `admin` port at `/metrics` every 30 seconds. This is Dragonfly's
native Prometheus endpoint; the clustered Alloy PodMonitor pipeline forwards
the samples to Mimir. The Dragonfly dashboard is the upstream operator
[Grafana dashboard](https://github.com/dragonflydb/dragonfly-operator/blob/v1.8.0/monitoring/grafana-dashboard.json),
pinned to the operator release tag and imported by the Grafana dashboard
syncer into `Infrastructure`. See the upstream [Prometheus integration
guide](https://www.dragonflydb.io/docs/managing-dragonfly/operator/prometheus-guide)
and [operator monitoring assets](https://github.com/dragonflydb/dragonfly-operator/tree/v1.8.0/monitoring).

The current operator manifest exposes its controller metrics through an HTTPS
`kube-rbac-proxy` Service. Alloy does not currently have a token mounted for
that service's RBAC authorization, so this change does not create an operator
ServiceMonitor that would fail authorization. Operator process metrics require
a narrowly scoped collector identity or an equivalent authenticated scrape
path before they can be enabled safely.

Validate replica health, TLS, PVC write/read and capacity, credential rotation,
cache/data recovery and client behavior during one-replica failure. PVC-backed
snapshots are not an independent site backup; define a volume-level backup or
restore procedure before treating them as durable recovery copies.
