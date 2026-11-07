# CoRE database charts

The `Databases` directory contains database operators and the PostgreSQL,
MySQL and MongoDB clusters used by CoRE services.

| Chart | Purpose | Fleet entry point |
| --- | --- | --- |
| [Operator](Operator/README.md) | Zalando PostgreSQL and Percona database operators. | `Apps/Storage/DBOperator.yaml` |
| [PSQL](PSQL/README.md) | Patroni/PostgreSQL, PGPool, pgAdmin and generated users. | `Apps/Storage/PSQL.yaml` |
| [MySQL](MySQL/README.md) | Percona XtraDB Cluster and integrations. | `Apps/Storage/Database/MySQL.yaml` |
| [MongoDB](MongoDB/README.md) | Percona MongoDB cluster, LDAP/TLS and S3 backup integration. | `Apps/Storage/Database/MongoDB.yaml` |

## Shared model

ApplicationSets inject cluster, site and environment values. Operators manage
database lifecycle; Crossplane user APIs generate identities; ExternalSecret
and PushSecret resources synchronize credentials with Vault. Database charts
also depend on storage classes, TLS, DNS/networking and S3 backup targets.

Argo CD `Synced` means only that the operator custom resource matches Git. A
database is healthy only when quorum/replication, storage, backups and client
transactions are healthy.

## Backup target plan

The current database backup path remains S3-compatible MinIO. PostgreSQL's
Zalando logical-backup sidecar is configured with the shared
`s3.mylogin.space` endpoint, and the MySQL and MongoDB stacks retain their
existing S3 backup resources. Longhorn volume backups are configured by the
[Storage Base stack](../Storage/Base/README.md), which currently supplies
site-local and peer S3 targets. These are current implementation details, not
proof that a recent backup can be restored; verify backup objects and perform
an isolated restore for each database and failure domain.

The target architecture is to make backup destination selection an explicit
site policy for PostgreSQL, MySQL, and Longhorn. Each workload should be able
to select among:

- a site-local Garage cluster for fast local recovery;
- Cloudflare R2 for an independent off-site copy; and
- the replicated site-global Garage cluster for cross-site recovery.

The site-local Garage tier and the replicated Garage tier are separate
storage systems. A database backup written to the replicated tier must use a
dedicated bucket and `mylogin.space/User` service identity; it must not rely on
the shared observability buckets. Future local-tier protection may compress or
archive backups into the replicated Garage tier or R2, but that transfer path
is not implemented yet.

The existing site-local MinIO path is currently broken in YXL and must not be
treated as a healthy fallback. Repair and validate that path, or migrate the
affected target to Garage/R2, before changing the default destination. The
future implementation must preserve independent credentials, bucket/prefix
names per workload and site, retention/lifecycle policy, encryption, restore
ordering, and a tested route for recovering when either the local site or the
replicated Garage control plane is unavailable. Do not switch production
backup targets as part of the Lab/Storage Garage rollout.

Relevant upstream references are the [Zalando Postgres Operator logical backup
documentation](https://postgres-operator.readthedocs.io/en/latest/administrator/backup_restore/),
[Percona XtraDB Cluster backup documentation](https://docs.percona.com/percona-operator-for-mysql/pxc-backup.html),
[Longhorn backup and restore documentation](https://longhorn.io/docs/1.12.1/snapshots-and-backups/backup-and-restore/),
[Garage’s S3 API documentation](https://garagehq.deuxfleurs.fr/documentation/reference-manual/s3/),
and [Cloudflare R2 S3 API compatibility](https://developers.cloudflare.com/r2/api/s3/api/).

## Change safety

Before a database change:

1. Confirm the selected clusters and the active primary/replica topology.
2. Take and verify a recent native backup.
3. Check storage capacity, disruption budgets and failure-domain placement.
4. Review operator compatibility and upgrade sequencing.
5. Verify whether any restore resource will render.
6. Change one database/failure domain at a time where practical.
7. Validate writes, reads, failover, TLS/LDAP and backups afterward.

Never enable a restore merely to test rendering. Restore objects are
executable data operations and must identify an intentionally selected backup.
