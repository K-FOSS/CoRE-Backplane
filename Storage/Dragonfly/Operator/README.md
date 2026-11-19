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
Argo CD applies the result. The local Helm chart contributes an availability
alert based on kube-state-metrics; the remote Kustomize source installs the
operator and its CRDs.

## Monitoring

[`OperatorAvailability.yaml`](templates/OperatorAvailability.yaml) alerts when
the controller Deployment has unavailable replicas for 10 minutes. Alloy's
`alloy-rules` component synchronizes the `PrometheusRule` into Mimir on
clusters with a reachable Mimir service. It uses the existing
`kube-state-metrics` stream, so the rule does not create another scrape path.

The current upstream operator manifest exposes controller process metrics
through an HTTPS `kube-rbac-proxy` Service. Alloy does not currently have a
token mounted for that Service's RBAC authorization. A direct operator metrics
scrape therefore needs a narrowly scoped collector identity or another
authenticated scrape path. The Dragonfly data-plane metrics and dashboard are
owned by the [CoRE instance chart](../CoRE/README.md#metrics-and-dashboard).

## Upgrade and supply-chain considerations

The remote resource tracks the upstream `main` branch. Its content can change
without a commit to CoRE Backplane, so two renders of the same repository
revision may differ. Before reconciliation, inspect the fetched manifest,
operator image, CRDs, RBAC and namespace behavior. See the upstream
[Dragonfly Operator repository](https://github.com/dragonflydb/dragonfly-operator)
and its [monitoring guide](https://www.dragonflydb.io/docs/managing-dragonfly/operator/prometheus-guide).

Pin the remote resource to an immutable release/tag or commit when a stable
operator version is required. Validate CRD compatibility and the Dragonfly
custom resources before upgrades.
