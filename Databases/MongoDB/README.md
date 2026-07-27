# MongoDB chart

This chart deploys a Percona Server for MongoDB cluster and its CoRE
integrations. It is owned by `Apps/Storage/Database/MongoDB.yaml`.

## Components

- Percona `psmdb-db` dependency and replica-set configuration.
- TLS and LDAP authentication configuration.
- Crossplane/Terraform provider integration.
- Generated database/S3 user and Vault secret synchronization.
- S3 backup configuration and scheduled backup.
- An optional restore resource.

## Dependencies

- Percona MongoDB Operator and CRDs.
- A suitable replicated storage class.
- Vault/External Secrets and Crossplane user APIs.
- LDAP/Authentik identity services and TLS material.
- Reachable S3 backup storage and credentials.

## Restore warning

`templates/MongoDB/Restore.yaml` contains deployment-specific backup names and
paths. Treat it as executable recovery configuration. Confirm that rendering
is gated as intended and update the exact backup destination before any
restore. A stale restore manifest can replace or conflict with current data.

Validate replica-set health, elections, TLS/LDAP login, application reads and
writes, backup completion and an isolated restore test.
