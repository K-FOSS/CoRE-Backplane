# Kafka

This chart deploys the [Strimzi Kafka Operator](https://strimzi.io/docs/operators/0.45.2/deploying.html)
and a single-broker Kafka cluster named `core-kafka`. The operator dependency is
pinned to Strimzi `0.45.2`, the final Strimzi release line that supports
ZooKeeper-based Kafka clusters. A future migration to KRaft must follow the
[Strimzi KRaft migration procedure](https://strimzi.io/docs/operators/0.45.2/deploying.html#assembly-migrating-to-kraft-str).

The owning [Kafka ApplicationSet](../../Apps/EventStream/Kafka.yaml) deploys
this chart to the `core-home1-talos-prod` cluster in the `core-prod` namespace
through the `argocd-lovely-plugin`. The chart's Kafka custom resource is held
until sync wave `10`, after the operator and its CRDs are installed.

Kafka and ZooKeeper each use a 10 GiB persistent claim with
`deleteClaim: false`; deleting the Argo application preserves resources and
does not intentionally remove those claims. Verify the Strimzi operator and
the `core-kafka` custom resource after reconciliation:

```sh
kubectl -n core-prod get deployment,strimzipodset,kafka,zookeeper
kubectl -n core-prod describe kafka core-kafka
```
