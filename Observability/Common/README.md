# CoRE-Backplane Observability/Common Stack

This chart deploys the federated Garage S3 backend in YXL and YVR used by
[Mimir](../Metrics/README.md) and [Loki](../Logs/README.md). Both start with
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

The chart creates a three-replica Garage storage cluster with replication
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

Each site advertises the managed Garage node pod addresses from its routable
site pod CIDR for identity-specific cross-site RPC. No node-address or public
LoadBalancer dependency is used. The operator uses those endpoints while
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
