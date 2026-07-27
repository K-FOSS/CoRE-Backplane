# Dragonfly Operator deployment

This deployment directory is targeted by
`Apps/Storage/Dragonfly/Operator.yaml` and rendered by
`argocd-lovely-plugin`.

## Resource source

The local Helm chart is intentionally minimal. The operator is installed by
the adjacent `kustomization.yaml`, which imports:

```text
https://raw.githubusercontent.com/dragonflydb/dragonfly-operator/main/manifests/dragonfly-operator.yaml
```

Lovely discovers and combines the directory's Helm and Kustomize inputs before
Argo CD applies the result. An empty `templates/` directory therefore does not
mean this deployment produces no resources.

## Upgrade and supply-chain considerations

The remote resource tracks the upstream `main` branch. Its content can change
without a commit to CoRE Backplane, so two renders of the same repository
revision may differ. Before reconciliation, inspect the fetched manifest,
operator image, CRDs, RBAC and namespace behavior.

Pin the remote resource to an immutable release/tag or commit when a stable
operator version is required. Validate CRD compatibility and the Dragonfly
custom resources before upgrades.
