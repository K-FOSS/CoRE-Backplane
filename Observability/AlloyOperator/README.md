# CoRE-Backplane Observability/AlloyOperator Stack

This stack installs the [Grafana Alloy Operator](https://github.com/grafana/alloy-operator)
for the clusters that run the shared [Collectors](../Collectors/) stack. The
operator owns the lifecycle of future `collectors.grafana.com/v1alpha1`
`Alloy` resources; the existing collectors remain Helm-managed until they are
deliberately migrated.

## Ownership and targets

The [Alloy Operator ApplicationSet](../../Apps/Observability/AlloyOperator.yaml)
targets the same production bare-metal clusters as Collectors and installs
into that cluster's `core-prod` namespace. The pinned 0.9.4
[`alloy-operator` Helm chart](https://github.com/grafana/helm-charts/tree/main/charts/alloy-operator)
creates its CRD, operator Deployment, ServiceAccount, and cluster-scoped RBAC.

## Configuration and operations

The operator runs two replicas with leader election. It is configured to watch
all namespaces, while the operator itself runs in `core-prod`; this allows
future Alloy instances to be placed beside their owning telemetry workload.
The [Grafana Alloy Operator README](https://github.com/grafana/alloy-operator/blob/main/README.md)
describes the `Alloy` custom resource and its supported lifecycle.

Verify the installation with:

```sh
kubectl -n core-prod get deployment,pods -l app.kubernetes.io/name=alloy-operator
kubectl get crd alloy.collectors.grafana.com
kubectl -n core-prod get alloy
```

Do not create an `Alloy` resource for the existing Helm-managed collectors
without first planning ownership transfer; two controllers must not manage
the same Alloy workload.
