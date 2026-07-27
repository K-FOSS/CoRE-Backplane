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
