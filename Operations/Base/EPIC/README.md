# EPIC base deployment

This Lovely directory combines a Contour Helm dependency with remote,
versioned EPIC Marin3r and resource-model manifests through Kustomize.

No direct ApplicationSet owner was found. Confirm whether it is experimental
or indirectly consumed before deployment.

Remote assets install CRDs/controllers with cluster-wide RBAC. Review fetched
content, namespaces, CRD compatibility and ownership. Pinning to release URLs
improves reproducibility, but release artifacts and container images should
still be verified during upgrades.
