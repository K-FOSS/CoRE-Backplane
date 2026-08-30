# RabbitMQ Cluster Operator

The owning [RabbitMQ operator ApplicationSet](../../../Apps/EventStream/RabbitMQOperator.yaml)
deploys the [Bitnami RabbitMQ Cluster Operator chart](https://github.com/bitnami/charts/tree/main/bitnami/rabbitmq-cluster-operator)
to every production Home1 cluster selected by these labels:
`mylogin.space/tenant=core.mylogin.space`, `resolvemy.host/env=prod`, and
`resolvemy.host/dc=home1`. It installs into `core-prod` and watches all
namespaces so the sibling [RabbitMQ ApplicationSet](../../../Apps/EventStream/RabbitMQ.yaml)
can create the `RabbitmqCluster` there.

The chart is pinned to `4.4.34`, which packages RabbitMQ Cluster Operator
`2.16.1`. The chart’s [upgrade notes](https://github.com/bitnami/charts/blob/main/bitnami/rabbitmq-cluster-operator/README.md#upgrading)
warn that CRDs are not upgraded by Helm; review the CRD upgrade procedure and
back up RabbitMQ before changing the chart version. The upstream operator also
warns that operator upgrades can roll RabbitMQ StatefulSets; observe the
cluster before and after reconciliation.

Deployment flow: Git -> Argo CD ApplicationSet -> Lovely renderer -> Helm
dependency -> operator CRDs/RBAC/deployment -> `RabbitmqCluster` in
`EventStream/RabbitMQ/Main`. Verify the ApplicationSet generated an application
named `core-home1-talos-prod-rabbitmq-operator`, then inspect the operator
deployment, CRDs, and RabbitMQ cluster conditions in `core-prod`.
