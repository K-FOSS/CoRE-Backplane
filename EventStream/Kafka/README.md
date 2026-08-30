# Kafka

This chart deploys the [Strimzi Kafka Operator](https://strimzi.io/docs/operators/0.45.2/deploying.html)
and a three-broker Kafka cluster named `core-kafka`. The operator dependency is
pinned to Strimzi `0.45.2`, the final Strimzi release line that supports
ZooKeeper-based Kafka clusters. A future migration to KRaft must follow the
[Strimzi KRaft migration procedure](https://strimzi.io/docs/operators/0.45.2/deploying.html#assembly-migrating-to-kraft-str).

The owning [Kafka ApplicationSet](../../Apps/EventStream/Kafka.yaml) deploys
this chart to the `core-home1-talos-prod` cluster in the `core-prod` namespace
through the `argocd-lovely-plugin`. The chart's Kafka custom resource is held
until sync wave `10`, after the operator and its CRDs are installed.

The three Kafka brokers use required pod anti-affinity on the
`kubernetes.io/hostname` topology, selecting the Strimzi broker label
`strimzi.io/name: core-kafka-kafka`. Each broker therefore runs on a different
worker node; the cluster requires at least three eligible worker nodes. See
Strimzi's [pod anti-affinity configuration](https://strimzi.io/docs/operators/0.45.2/deploying.html#assembly-scheduling-str)
for the supported scheduling model.

Kafka clients authenticate through the internal TLS listener on port `9093`
using Authentik OAuth2 JWTs. The chart creates the Authentik provider and
application through the repository's `authentik` Terraform ProviderConfig and
publishes the generated client credentials in the `core-kafka-oidc` connection
Secret. The broker validates tokens locally using Authentik's JWKS endpoint;
see the [Strimzi OAuth configuration](https://strimzi.io/docs/operators/0.45.2/deploying.html#con-oauth-server-configuration-str)
and [Authentik OAuth2 endpoints](https://docs.goauthentik.io/add-secure-apps/providers/oauth2/).

The client Secret contains `client_id`, `client_secret`, `issuer_url`, and
`jwks_url` keys. Do not print its values. A client must request an Authentik
access token for the `core-kafka` provider and use the `preferred_username`
claim as its Kafka principal.

The chart also deploys the pinned [Kafbat UI Helm chart](https://github.com/kafbat/helm-charts/tree/main/charts/kafka-ui)
at chart version `1.6.5` and image version `v1.5.0`. Kafbat is exposed at the
ApplicationSet-generated `kafka-ui.<cluster>.<datacenter>.<region>.mylogin.space`
hostname through the existing `core-prod/main-gw` Gateway. Its native
[OAuth2/OIDC login](https://ui.docs.kafbat.io/configuration/authentication/for-the-ui/oauth2)
uses a separate Authentik provider and application named `Core Kafka UI`, with
the strict callback URI for that hostname. Users therefore receive SSO through
Authentik while Kafbat retains its own client session and does not reuse the
Kafka broker client.

Kafbat connects to the internal TLS listener at
`core-kafka-kafka-bootstrap:9093` with SASL/PLAIN. Strimzi exchanges the UI
client ID and secret for an OAuth token at Authentik's token endpoint; the UI
pod trusts the `core-kafka-cluster-ca-cert` Secret. This uses the listener's
`enablePlain` path and avoids bundling a separate Strimzi OAuth callback plugin
in the Kafbat image. See [Strimzi OAuth client authentication](https://strimzi.io/docs/operators/0.45.2/deploying.html#con-oauth-server-configuration-str)
and [Kafbat configuration](https://ui.docs.kafbat.io/configuration/configuration-file)
for the supported Kafka and application configuration shapes.

The Kafka provider trusts the UI provider as a federated Authentik provider,
and both providers use the same configured signing certificate. Strimzi's
listener therefore validates the shared JWKS but does not set a single
`validIssuerUri`; this is required because the Kafka and UI clients have
different per-provider issuers. Keep the Authentik signing certificate and
provider set tightly controlled.

The combined Terraform Workspace writes the Kafka and UI credentials to
`core-kafka-oidc` under separate keys. The UI keys are pushed to
`EventStream/Kafka/UI/OIDC` in `mainvault-core` with deletion policy `None`.
The Kafka and UI clients remain intentionally separate.

The internal and external listeners also enable Strimzi OAuth over SASL/PLAIN
and point at the Authentik token endpoint. This supports clients such as
OpenNMS that can pass a username and password but do not bundle Strimzi's
OAuth callback library: the username is the OAuth client ID and the password
is the generated client secret. Strimzi exchanges those values for a token
before validating the resulting JWT; see the [Strimzi OAuth client
authentication documentation](https://strimzi.io/docs/operators/0.45.2/deploying.html#con-oauth-server-configuration-str).

When enabled, `OIDCSecretSync.yaml` publishes only the generated Kafka OAuth
connection fields to the `mainvault-core` [External Secrets
Store](https://external-secrets.io/latest/provider/cluster-secret-store/)
under `EventStream/Kafka/OIDC`. The PushSecret reconciles every five minutes,
replaces the remote fields as a unit, and leaves the remote record in place
when the PushSecret or Argo application is removed. Kafka broker pods carry a
targeted [Stakater Reloader Secret annotation](https://github.com/stakater/Reloader#how-to-use-reloader)
for `core-kafka-oidc`; a changed local connection Secret therefore causes
Strimzi to roll the brokers. The broker does not consume this Secret for
normal JWT validation, so this restart is a credential-rotation safeguard.

## OpenNMS IPC topics

The broker disables automatic topic creation, so the chart declares the
required Horizon IPC topics as Strimzi `KafkaTopic` resources. The list follows
OpenNMS's [Horizon 36 required Kafka topics](https://docs.opennms.com/horizon/36/deployment/core/message-broker/kafka-topics.html):
`OpenNMS.Sink.Heartbeat`, `OpenNMS.Sink.Events`, `OpenNMS.Sink.Syslog`,
`OpenNMS.Sink.Trap`, `OpenNMS.Sink.DeviceConfig`, `OpenNMS.rpc-response`,
`OpenNMS.twin.request`, `OpenNMS.twin.response`, and the location-specific RPC
request and Twin response topics for `core-home1-talos-prod` and
`core-dc1-talos-prod`. The optional sink topics are declared proactively so
enabling trap, syslog, event, or device-configuration forwarding does not rely
on broker-side automatic topic creation.
Keep the list synchronized with the exact `MINION_LOCATION` values and the
`OpenNMS` instance ID in the Insight ApplicationSet. Each topic is provisioned
with three partitions and three replicas for this three-broker cluster.

The Home1 ApplicationSet also enables the external TLS listener on port `9094`,
which Strimzi exposes through ClusterIP Services rather than a cloud
LoadBalancer or NodePort. It publishes
`kafka.<cluster>.<datacenter>.<region>.mylogin.space` for bootstrap
and `kafka-0.<cluster>.<datacenter>.<region>.mylogin.space` for broker `0`
through ExternalDNS. Both names are covered by the existing
`myloginspace-default-certificates` Secret, which Strimzi uses through
`brokerCertChainAndKey`; the certificate and key are not copied into Git.
The generated external bootstrap and broker Services carry
`wan-mode: 'public'`, which is required by the site ExternalDNS selection.
Strimzi adds the configured broker addresses to its advertised listeners and
requires those names in the certificate SANs; see [custom listener
certificates](https://strimzi.io/docs/operators/0.45.2/configuring.html#type-CertAndKeySecretSource-reference)
and [external listener annotations](https://strimzi.io/docs/operators/0.45.2/configuring.html#type-GenericKafkaListenerConfiguration-reference).

Kafka and ZooKeeper each use a 10 GiB persistent claim with
`deleteClaim: false`; deleting the Argo application preserves resources and
does not intentionally remove those claims. Verify the Strimzi operator and
the `core-kafka` custom resource after reconciliation:

```sh
kubectl -n core-prod get deployment,strimzipodset,kafka,zookeeper
kubectl -n core-prod describe kafka core-kafka
kubectl -n core-prod get deployment/core-kafka-ui httproute/core-kafka-ui
kubectl -n core-prod describe workspace/core-kafka-ui-authentik
```

Then open the generated `kafka-ui.<cluster>.<datacenter>.<region>.mylogin.space`
URL and verify that Authentik login returns to Kafbat and that the `core-kafka`
cluster lists topics. Do not print either OIDC Secret; inspect only key names,
controller conditions, and application logs with secret values redacted.
