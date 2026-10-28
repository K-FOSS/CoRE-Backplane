# RabbitMQ Cluster Operator

The owning [RabbitMQ operator ApplicationSet](../../../Apps/EventStream/RabbitMQOperator.yaml)
deploys the [Bitnami RabbitMQ Cluster Operator chart](https://github.com/bitnami/charts/tree/main/bitnami/rabbitmq-cluster-operator)
to every production Home1 cluster selected by these labels:
`mylogin.space/tenant=core.mylogin.space`, `resolvemy.host/env=prod`, and
`resolvemy.host/dc=home1`. It installs into `core-prod` and watches all
namespaces so the sibling [RabbitMQ ApplicationSet](../../../Apps/EventStream/RabbitMQ.yaml)
can create the `RabbitmqCluster` there.

The chart is pinned to `4.4.34`, which packages RabbitMQ Cluster Operator
`2.16.1`. Its four Bitnami images use the `bitnamilegacy` repositories because
the matching tags are no longer available under `bitnami`. The legacy
repositories are [archived and receive no further updates](https://hub.docker.com/u/bitnamilegacy),
so these image overrides restore availability as a short-term compatibility
measure; plan migration to maintained upstream images. The RabbitMQ operator
[release guidance](https://github.com/rabbitmq/cluster-operator/releases)
warns that upgrading the controller can roll RabbitMQ StatefulSets. The chart’s
[upgrade notes](https://github.com/bitnami/charts/blob/main/bitnami/rabbitmq-cluster-operator/README.md#upgrading)
warn that CRDs are not upgraded by Helm; review the CRD upgrade procedure and
back up RabbitMQ before changing the chart or controller version.

Deployment flow: Git -> Argo CD ApplicationSet -> Lovely renderer -> Helm
dependency -> operator CRDs/RBAC/deployment -> `RabbitmqCluster` in
`EventStream/RabbitMQ/Main`. Verify the ApplicationSet generated an application
named `core-home1-talos-prod-rabbitmq-operator`, then inspect the operator
deployment, CRDs, and RabbitMQ cluster conditions in `core-prod`.
