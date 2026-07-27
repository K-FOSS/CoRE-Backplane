# Multicluster Services base deployment

This Lovely directory imports the Open Cluster Management cluster-manager
Kustomization from the upstream `main` branch. No direct ApplicationSet owner
was found.

The remote mutable URL can change without a CoRE commit. Pin a release or
commit before production use. Review cluster-wide RBAC, CRDs, namespaces and
compatibility with `Operations/MultiClusters` and `Base/Spoke`.
