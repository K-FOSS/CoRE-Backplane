# MongoDB chart

This chart deploys a Percona Server for MongoDB cluster and its CoRE
integrations. It is owned by `Apps/Storage/Database/MongoDB.yaml`.

## Components

- Percona `psmdb-db` dependency and replica-set configuration.
- Three-member `rs0` replica set by default, with one member per Kubernetes
  node and a one-member disruption budget for quorum-preserving maintenance.
- TLS and LDAP authentication configuration.
- Crossplane/Terraform provider integration.
- Generated database/S3 user and Vault secret synchronization.
- S3 backup configuration and scheduled backup.
- An optional restore resource.

The generated MongoDB service identity is a namespaced `User` claim whose
Authentik display name and username include the target cluster. This keeps the
LDAP identity cluster-scoped in the shared Authentik directory while retaining
the standard `User.mylogin.space/v1alpha1` claim lifecycle. The owning
ApplicationSet injects the cluster name; standalone chart renders fall back to
the Helm release name. The claim Secret is pushed to and read from the
cluster-specific Vault path `MongoDB/<cluster>/Credentials`, which supplies
the LDAP query user and password used by MongoDB. The Crossplane provider still
uses the separate operator administrator Secret for role management.

## Dependencies

- Percona MongoDB Operator and CRDs.
- A suitable replicated storage class.
- Vault/External Secrets and Crossplane user APIs.
- LDAP/Authentik identity services and TLS material.
- Reachable S3 backup storage and credentials.

## Restore warning

`templates/MongoDB/Restore.yaml` contains deployment-specific backup names and
paths and is disabled by default. Treat it as executable recovery configuration.
Confirm that rendering is intentionally enabled and update the exact backup
destination before any restore. A stale restore manifest can replace or
conflict with current data.

The active Home1 cluster currently uses the `core-home1-talos-prod-rs0`
headless Service and has three ready `rs0` members on `hpc3`, `srv2`, and
`srv3`. Consumers should use that replica-set Service name plus
`replicaSet=rs0`; do not pin a client to one pod. The owning ApplicationSet
injects `replsetSize` per target cluster. Home1 and DC1 are configured for
three members, while `values.yaml` keeps the quorum-safe default at three.

Validate replica-set health, elections, TLS/LDAP login, application reads and
writes, backup completion and an isolated restore test. The Percona status may
retain an error condition after a transient reconciliation timeout even while
`rs0` reports three ready members; investigate both conditions before declaring
the service healthy.
