# CoRE-Backplane Observability/Common Stack

This chart deploys the federated Garage S3 backend in YXL and YVR used by
[Mimir](../Metrics/README.md), [Loki](../Logs/README.md), and
[Tempo](../Traces/README.md). Both start with
fresh Garage buckets; existing MinIO objects remain in place and are not
copied. It is owned by the
[Observability Common ApplicationSet](../../Apps/Observability/Common.yaml).
The Garage controller and CRDs are owned separately by the
[Garage Operator ApplicationSet](../../Apps/Storage/S3/Garage-Operator.yaml).
The chart also creates one Longhorn `ReadWriteMany` StorageClass per
entry in [`values.yaml`](values.yaml), named `<tenant>-fast-rwx`. These classes
use one replica, disable live migration, require strict local data placement,
and delete dynamically provisioned volumes when their PVCs are deleted.
Longhorn documents these settings in its
[StorageClass parameter reference](https://longhorn.io/docs/1.13.0/references/storage-class-parameters/).

## Ownership and reconciliation

The ApplicationSet selects the core bare-metal infrastructure clusters in DC1/YXL
and Home1/YVR and renders this chart into `core-prod`. Sync the S3 Garage Operator
first, wait for its CRDs and webhook to become healthy, then sync this chart to
create the `GarageCluster`. The Metrics ApplicationSet creates Mimir's
buckets/key; the Logs application's `loki-s3` User claim creates Loki's
buckets/key through the User Composition.

## Garage cluster and data flow

The chart creates a three-replica Auto-managed Garage storage cluster with replication
factor `3`. Each Garage node requests a `20Gi` Longhorn data PVC and a `2Gi`
metadata PVC. The data StorageClass uses one Longhorn replica so Garage's
three object copies provide the data replication; the metadata class uses two
Longhorn replicas. PVC reclaim and Garage PVC retention policies are both
`Retain`. Review capacity before sync; this configuration requests 66Gi of
PVC capacity and Longhorn will additionally allocate metadata replicas.
The Garage Operator applies a hostname topology-spread constraint with
`maxSkew: 1` to storage nodes, requiring eligible nodes to distribute replicas
across distinct Talos hosts. If fewer than three hosts can schedule the pods,
the affected replicas remain Pending rather than co-locating. The operator's
[storage and gateway scheduling settings](https://rajsinghtech.github.io/garage-operator/how-to/configuration/)
describe this `storage.topologySpreadConstraints` field.

The cluster enables the operator-managed Garage node ServiceMonitor at a
60-second interval. Garage exports per-node data and metadata disk capacity,
cluster health, S3 request activity, and block read/write counters through its
[Prometheus metrics endpoint](https://garagehq.deuxfleurs.fr/documentation/reference-manual/monitoring/).
The scrape drops only `rpc_duration_bucket`, whose peer and endpoint labels
otherwise create a large number of histogram series; the related count and sum
series remain available. Bucket bytes and object counts come from the Garage
operator metrics endpoint described in the operator stack documentation.

The chart also deploys [Garage UI](https://github.com/Noooste/garage-ui), pinned
to Helm chart version `0.14.0` and image digest
`sha256:e4a33c448304a3f6e60f08d6aa71b2471fd79ac870a5c7e178ea247dea3238b3`, as the
management interface for this Garage cluster. Its upstream chart values are
provided under the `garage-ui-web` dependency alias in
[`values.yaml`](values.yaml). It uses the cluster's existing bootstrap Secret for the Garage
admin API token and connects to the in-cluster S3 and admin Services over HTTP;
the public UI hostname is `garage-ui.mylogin.space`. The upstream UI's own OIDC
login is disabled because the route is protected by the shared Authentik
forward-auth outpost. The generated Authentik proxy application grants access
only to the `Server Admins` group. Garage UI's optional team access control is
not a replacement for Garage key permissions; its upstream
[access-control documentation](https://github.com/Noooste/garage-ui/blob/main/docs/access-control.md)
describes that limitation.

Garage's S3 listener serves HTTP, so the chart uses the existing Envoy Gateway
`main-gw` HTTPS listener to terminate TLS and routes requests to Garage's port
`3900`. Mimir and Loki connect to
`observability-garage-s3.core-prod.svc.<cluster-domain>:443`. The HTTPRoute
matches that FQDN and preserves the SigV4 `Host` value while routing to Garage.
Its `wan-mode: 'public'` label lets the deployed ExternalDNS controller publish
the route hostname against the Gateway address; `lan-mode: 'private'` retains
the private network classification. No alias Service or generated Envoy
Service name is part of the client endpoint. This follows CoRE-Business AI's
[Envoy Gateway and HTTPRoute pattern](https://slop.writemy.codes/CoRE/CoRE-Business/src/branch/main/AI/templates/Gateway/Gateway.yaml).
The listener references the exact cert-manager certificate issued by
[Network/TLS Certificates](../../Network/TLS/Certificates/README.md). Garage
S3 access remains protected by the operator-generated, bucket-scoped key.
Garage itself does not terminate TLS; see the operator's
[TLS guidance](https://rajsinghtech.github.io/garage-operator/how-to/tls/).

External Secrets Operator generates distinct 32-character random values and
hex-encodes each as a 64-character credential. A `CreatedOnce` ExternalSecret
stores them in a source Secret, and a `PushSecret` publishes them to
`Garage/Mimir` in the `mainvault-core` ClusterSecretStore. The PushSecret uses
`IfNotExists` and a `None` deletion policy: existing Vault values remain
authoritative and deleting the chart does not remove them. A second
ExternalSecret reads the `AdminToken` and `RPCSecret` properties back into the
Garage bootstrap Secret. This flow uses ESO's
[Password generator](https://external-secrets.io/latest/api/generator/password/),
[PushSecret](https://external-secrets.io/latest/api/pushsecret/), and
[HashiCorp Vault provider](https://external-secrets.io/latest/provider/hashicorp-vault/).
It lets the chart initialize an empty Vault path
while preserving an existing path. The PushSecret requires Vault create, read,
and update access to `Garage/Mimir`. The admin token is a
high-privilege control-plane credential; limit access and do not reuse the
Garage S3 key. The generated source Secret, Vault path, and bootstrap Secret
all contain sensitive material. Preserve Vault values through upgrades.

The Garage image is pinned to the Garage `v2.4.1` digest in
[values.yaml](values.yaml). Garage recommends keeping its metadata on fast
storage and uses the replication factor to distribute object copies; see the
[Garage configuration reference](https://garagehq.deuxfleurs.fr/documentation/reference-manual/configuration/)
and [Kubernetes deployment guide](https://garagehq.deuxfleurs.fr/documentation/cookbook/kubernetes/).
The Garage operator API and its supported cluster fields are documented in the
[GarageCluster reference](https://rajsinghtech.github.io/garage-operator/reference/api/garagecluster-v1beta2/).
Bucket and key lifecycle behavior is covered by its
[custom resource guide](https://rajsinghtech.github.io/garage-operator/reference/custom-resources/)
and [bucket and credential guide](https://rajsinghtech.github.io/garage-operator/how-to/buckets-and-credentials/).
Longhorn class parameters are documented in its
[StorageClass reference](https://longhorn.io/docs/1.13.0/references/storage-class-parameters/).

## Shared buckets across sites

YXL and YVR intentionally use the same Garage bucket namespace. The S3
endpoint, Kubernetes Service name, credential handle, and TLS path may differ
by site, but a site suffix must never be added to a bucket name. Garage's
federated layout is the replication boundary; the sites are not two
independent S3 stores that require application-level bucket copying.

| Consumer | Shared Garage bucket(s) | Durable contents |
| --- | --- | --- |
| Mimir | `mimir-blocks`, `mimir-alertmanager`, `mimir-ruler` | TSDB blocks, Alertmanager state, and ruler state |
| Loki | `loki-chunks`, `loki-rules-temp`, `loki-admin` | Chunks/index data, ruler data, and administrative state |
| Tempo | `tempo-traces` | Trace blocks |

YXL is the Garage layout writer and YVR is the follower. The federated
`GarageCluster` uses consistent replication with factor `3` and requires
copies in at least two zones (`yxl` and `yvr`). The YXL bucket resources are
the authoritative bucket records and grant both the YXL and YVR service
identities access to the same global aliases. YVR's consumer claims use the
YXL Garage credential handle where required; this is an identity/bootstrap
detail, not a second bucket set.

Consumers select a local-preferred endpoint for latency and site survival:
YXL normally uses the local TLS S3 Gateway, while YVR uses its local Garage
listener or the local site route according to the rendered ApplicationSet
values. Both endpoints address the federated bucket namespace. A local
endpoint outage must fail over to the other site's routable Garage endpoint
without changing bucket names, prefixes, tenant IDs, or credentials.

The inter-site network is asymmetric: YVR has materially less outbound
capacity than YXL, while normal reachability and YXL ingress/egress are good.
This is a design constraint, not a value to encode in manifests. Keep
telemetry ingestion, processing, reads, and temporary working state local to
the active site. Do not synchronously send a second copy of logs, metrics, or
traces from the application rings across the WAN. Garage remains responsible
for the durable cross-site copy; its replication, repair, and backlog metrics
must be monitored and rate-limited so YVR egress pressure cannot destabilize
collectors or backend write paths.

Failover should prefer YXL for sustained high-volume recovery traffic when YVR
egress is congested, while retaining local-preferred routing during normal
operation. Control-plane coordination, Consul/Redis/EventStream traffic, and
Garage RPC must use bounded timeouts, retries with backoff, and circuit
breaking. A WAN degradation is not a reason to increase Loki, Mimir, or Tempo
replication factors.

### Shared-bucket coordinator ownership

The default ApplicationSet profile runs Mimir, Loki, and Tempo compactor/ruler
workloads in YXL only. YVR continues to run its local gateways, distributors,
ingesters, queriers, query frontends, and other read/write edge components, but
does not independently compact or evaluate the same shared bucket. This keeps
one owner for index/block lifecycle operations while the federated Garage
layout remains available from either site.

Regional promotion is an ordered configuration change: fence the YXL
coordinators and writers, confirm the Garage layout and object backlog are
healthy, enable the YVR compactor/ruler profile, then move the global client
Service preference. Do not run both sites' compactor/ruler coordinators against
the same bucket during a partial failover. Demotion follows the reverse order
after the promoted site has drained its lifecycle work.

Do not infer replication from a successful S3 connection alone. Before a
topology or credential change, verify the YXL writer, YVR follower, remote
Garage nodes, committed layout, and bucket aliases. From both cluster
contexts, verify that the observability `GarageCluster` and node resources are
Ready or intentionally waiting on the writer, then compare the non-secret
bucket aliases and object visibility through each site endpoint. Never print
access keys, secret keys, admin tokens, or generated connection Secrets.

## Operations and data retention

Validate with:

```bash
helm lint Observability/Common
helm template core-dc1-talos-prod-observability-common-prod Observability/Common --namespace core-prod
```

After reconciliation, verify the generator ExternalSecret and PushSecret are
Ready, the Vault-backed bootstrap ExternalSecret is ready, GarageCluster is
Ready, all Garage PVCs are bound, and Garage health reports three nodes with a
committed layout. Also verify `observability-garage-s3-tls` Certificate Ready,
the HTTPRoute is `Accepted` with `ResolvedRefs`, the Gateway listener is
`Programmed`, and the certificate SAN matches the cluster-domain Service FQDN.
Then reconcile Metrics and Logs. Verify their Garage bucket/key resources and
User claim readiness, and inspect generated S3 Secret key names without
printing data. Confirm both clients connect through Envoy Gateway with
certificate verification enabled.
For Garage UI, verify the `garage-ui` Deployment, ServiceMonitor, HTTPRoute,
outpost callback route, fail-closed SecurityPolicy, and Authentik Workspace.
An unauthenticated request to `https://garage-ui.mylogin.space` must redirect
through Authentik, while a `Server Admins` member must be able to browse the
Garage cluster and buckets. The upstream [Garage UI Helm chart](https://github.com/Noooste/garage-ui/tree/main/helm/garage-ui)
documents the configuration and health endpoint used by the deployment.
Removing this chart removes the GarageCluster desired resource; retained PVCs
are recovery material and require deliberate cleanup only after data is
backed up and no consumer references the cluster. The Vault path is retained
on chart removal; reapplying the chart pulls those same credentials back into
the bootstrap Secret.

## Multi-cluster federation

YXL and YVR run site-local `GarageCluster` resources that join one Garage
layout. Both sites read the same `AdminToken` and `RPCSecret` properties from
the `Garage/Mimir` Vault path; the RPC value must therefore remain byte-for-byte
identical in the site-local `mainvault-core` stores. YXL is the sole layout
writer and YVR is a follower. Replication factor `3` with
`zoneRedundancyMode: AtLeast` and `zoneRedundancyMinZones: 2` requires object
copies to span both sites.

Each Auto-managed storage identity at both sites has a dedicated headless RPC
Service. Site ExternalDNS publishes the identity-specific endpoint names, and
the YXL writer uses the YVR names for cross-site RPC. The records resolve to
the routable site pod addresses; no shared node-address or LoadBalancer
dependency is used. The operator uses those endpoints while
the Admin API is published through the site-specific TLS HTTPRoute
`observability-garage-admin.<dc>.<region>.mylogin.space`. This endpoint is
authenticated with the remote site's Garage admin token and is not an S3
endpoint. The [Garage federation guide](https://rajsinghtech.github.io/garage-operator/how-to/federation/)
and [storage identity and layout guide](https://rajsinghtech.github.io/garage-operator/concepts/storage-and-layout/)
describe the routable RPC and serialized layout requirements.

Historical MinIO objects remain in MinIO; federation applies to new Garage
objects only. Before changing membership, verify both sites report
`FederationConfigured=True`, `RemoteClustersHealthy=True`, no sustained
`PeerUnreachable`, and a settled layout. Preserve the YXL writer/YVR follower
ordering for all topology changes.

The same-bucket invariant is part of the recovery contract. A site restore
must rejoin the existing Garage layout and reuse the existing global aliases;
creating `mimir-blocks-yvr`, `loki-chunks-yxl`, or another site-specific bucket
would create a new data set that Mimir, Loki, or Tempo will not query. Retain
the Garage PVCs and bucket resources during backend upgrades, and validate
object reads from both sites before declaring regional failover complete.

The YXL writer declares the three current YVR node identities as external
`GarageNode` resources. Their IDs are read from the YVR PVC-backed Garage
identities and their addresses are the ExternalDNS-published headless Service
names. The YVR follower also receives the writer's per-ordinal RPC endpoint
template through `remoteClusters.connection.storageRpcEndpointTemplate`. If a YVR
node identity is deliberately replaced, update this registry after the new
node is running and before removing the old role; do not reuse an old ID for a
different PVC.
