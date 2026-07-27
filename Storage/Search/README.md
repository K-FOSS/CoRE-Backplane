# Search chart

This chart packages the OpenSearch Operator dependency. The OpenObserve
dependency is currently commented out.

## Deployment status

No direct ApplicationSet reference was found. Treat the chart as inactive,
experimental or manually deployed until ownership is confirmed.

Before enabling it, define the OpenSearch cluster resources, storage classes,
failure-domain placement, security/TLS, users, snapshot repository, retention,
capacity and upgrade compatibility. Installing the operator alone does not
create a durable search cluster or establish backups.
