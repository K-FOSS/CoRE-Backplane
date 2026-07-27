# Database Operator chart

This chart installs the Zalando PostgreSQL Operator and Percona XtraDB Cluster
Operator. It also contains manifests for the Percona MongoDB operator path and
PostgreSQL operator configuration/secrets. It is owned by
`Apps/Storage/DBOperator.yaml`.

Operators and CRDs must be established before database clusters. Review CRD
conversion/storage versions, watched namespaces, RBAC, admission webhooks and
operator/database compatibility before upgrades.

An operator upgrade can reconcile every managed database. Render and test
upgrades against a non-critical cluster first, preserve database-native
backups, and monitor reconciliation, leader election and database disruption.
Do not remove CRDs while managed database custom resources still exist.
