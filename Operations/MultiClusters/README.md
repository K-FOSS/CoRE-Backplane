# Multicluster management deployment

This deployment combines Clusterpedia with Open Cluster Management resources:
ClusterManager, ManagedClusters, cluster sets/bindings, add-ons and
registration RBAC.

No direct ApplicationSet owner was found. Treat it as inactive, manual or
transitional until ownership is confirmed.

The checked-in values contain deployment-specific API endpoints and literal
database defaults. Replace them with secret references before use. Registration
tokens and cluster credentials grant broad access and require rotation,
least-privilege storage and deliberate deletion behavior.

Validate manager/agent health, cluster registration, aggregation consistency,
RBAC and behavior during hub loss.
