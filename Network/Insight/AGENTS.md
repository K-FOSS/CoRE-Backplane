# OpenNMS Insight change guidance

This directory deploys the OpenNMS Horizon core and site-local Minions. Any
change that enables, disables, renames, or changes a Kafka-backed feature must
be reviewed together with the owning Kafka deployment:

- `../../Apps/EventStream/Kafka.yaml` selects and deploys the Kafka rendering
  unit.
- `../../EventStream/Kafka/values.yaml` is the desired-state registry for
  OpenNMS IPC and Twin topics.
- `../../EventStream/Kafka/templates/OpenNMSTopics.yaml` renders those entries
  as Strimzi `KafkaTopic` resources.
- `../../EventStream/Kafka/README.md` documents the current topic and
  reconciliation model.

Kafka automatic topic creation is disabled. Therefore, a change in this chart
is incomplete until every newly required topic is added to the Kafka chart's
`topics` list in the same change. Do not create topics manually in a live
cluster as a substitute for Git desired state.

At minimum, inspect the effective Kafka configuration after all
ApplicationSet-injected values are applied and reconcile the following:

1. Keep the `OpenNMS` instance ID identical between the core and every Minion.
2. For every configured Minion `location`, ensure the corresponding location
   RPC request and Twin response topics are present. The current naming form is
   `OpenNMS.<location>.rpc-request` and
   `OpenNMS.twin.response.<location>`.
3. Preserve the shared request/response and heartbeat topics required by the
   Horizon IPC strategy, including `OpenNMS.rpc-response`,
   `OpenNMS.twin.request`, `OpenNMS.twin.response`, and
   `OpenNMS.Sink.Heartbeat`.
4. If a feature introduces another Kafka producer or consumer (including IPC,
   RPC, Twin, event, telemetry, or plugin traffic), identify its exact topic
   names, partitions, replicas, retention requirements, and ownership, then
   add or update the corresponding `KafkaTopic` entries and any required
   client authorization before changing the client configuration here.
5. When adding or removing a Minion location, update the ApplicationSet and
   Kafka topic registry together. Removing a reference from this chart does
   not prove that the old topic or its data was deleted; review retention and
   deletion behavior explicitly.

Validate the complete rendering units, not only this chart: render or lint
`Network/Insight` with representative ApplicationSet values and
`EventStream/Kafka` with its target cluster values, inspect the resulting
`KafkaTopic` names and labels, and run `git diff --check`. After reconciliation,
verify Strimzi reports each topic ready and that the OpenNMS/Minion clients can
produce and consume without authorization or missing-topic errors. Never print
Kafka OAuth credentials or Secret values during verification.

Use the authoritative [Horizon Kafka topic reference](https://docs.opennms.com/horizon/36/deployment/core/message-broker/kafka-topics.html),
[Horizon Minion IPC overview](https://docs.opennms.com/horizon/36/deployment/minion/introduction.html),
and [Strimzi KafkaTopic documentation](https://strimzi.io/docs/operators/0.45.2/deploying.html#type-KafkaTopic-reference)
when determining topic requirements or resource behavior.
