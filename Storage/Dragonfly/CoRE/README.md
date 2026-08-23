# Dragonfly CoRE chart

This chart deploys a Dragonfly distribution/cache service with two replicas,
TLS, S3-backed persistent content and generated credentials. It is owned by
`Apps/Storage/Dragonfly/CoRE.yaml`.

The `dragonfly-core` instance serves authenticated, TLS-enabled Redis clients.
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


Numeric databases prevent accidental key collisions but are not a security or
resource-isolation boundary: all consumers still share the Dragonfly process,
password, memory limit, persistence, and failure domain. Allocate a documented,
unused database number for every new client that supports selection. Use a
separate Dragonfly instance when a workload needs independent credentials,
capacity, lifecycle, or recovery behavior.

Crossplane user resources create S3 access; ExternalSecret and PushSecret
resources synchronize credentials; a Terraform provider configuration is
generated for integration.

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
