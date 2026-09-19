# Dragonfly CoRE chart

This chart deploys a Dragonfly distribution/cache service with two replicas,
TLS, S3-backed persistent content and a long-lived S3 service-account
credential. It is owned by
`Apps/Storage/Dragonfly/CoRE.yaml`.

Dragonfly keeps scheduled snapshots in site-local S3 and uses a per-replica
`ssd-storage` PVC for SSD tiering. The PVC is a performance/data-tier volume,
not a replacement for the S3 backup path. See the [Dragonfly SSD tiering
overview](https://www.dragonflydb.io/blog/a-preview-of-dragonfly-ssd-tiering)
and [Dragonfly Operator repository](https://github.com/dragonflydb/dragonfly-operator)
for the upstream behavior.

Updated replicas must remain Ready for 300 seconds before the operator can
advance the rollout. This is implemented with the Dragonfly custom readiness
probe and replication-readiness gate because the operator CRD does not expose
a native rollout-delay field. A pod restart resets this readiness timer.

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
| `150` | OpenWebUI cache | Dedicated OpenWebUI application cache. Owned by [`Business/AI`](https://github.com/K-FOSS/CoRE-Business/tree/main/AI). |
| `151` | OpenWebUI websocket manager | Dedicated OpenWebUI websocket-manager state. Owned by [`Business/AI`](https://github.com/K-FOSS/CoRE-Business/tree/main/AI). |
| `152` | SnapOtter | Dedicated SnapOtter/BullMQ queues and processing state. Owned by [`Business/Conversions`](https://github.com/K-FOSS/CoRE-Business/tree/main/Tools/Conversions). |
| `189` | n8n | Dedicated n8n external Redis state. Owned by [`Business/Automation`](https://github.com/K-FOSS/CoRE-Business/tree/main/Automation). |


Numeric databases prevent accidental key collisions but are not a security or
resource-isolation boundary: all consumers still share the Dragonfly process,
password, memory limit, persistence, and failure domain. Allocate a documented,
unused database number for every new client that supports selection. Use a
separate Dragonfly instance when a workload needs independent credentials,
capacity, lifecycle, or recovery behavior.

The Crossplane `User` claim creates the site-local bucket and a long-lived
MinIO service account. The SSO User Composition publishes its
`AccessKey`/`SecretAccessKey` to `dragonfly-core-s3-service-account-creds`,
which Dragonfly uses for its S3 snapshots. This avoids the seven-day temporary
credential path, so operators must coordinate service-account key rotation.
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

Validate replica health, TLS, S3 read/write, credential rotation, cache/data
recovery and client behavior during one-replica failure. Clarify which content
is authoritative in S3 and which state is disposable cache before defining a
restore procedure.
