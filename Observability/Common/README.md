# CoRE-Backplane Observability/Common Stack

This YXL-only chart provides the Garage S3 backend used by
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

The ApplicationSet selects core bare-metal infrastructure clusters in DC1
region YXL and renders this chart into `core-prod`. Sync the S3 Garage Operator
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
Removing this chart removes the GarageCluster desired resource; retained PVCs
are recovery material and require deliberate cleanup only after data is
backed up and no consumer references the cluster. The Vault path is retained
on chart removal; reapplying the chart pulls those same credentials back into
the bootstrap Secret.

## Intended multi-cluster direction

The current Garage deployment is local to YXL and serves Metrics and Logs.
Historical MinIO objects remain in MinIO; copying them is not required. The
intended next stage is to move Logs, Traces, and Metrics to one shared Garage
service (one logical “cluster” from their perspective) across the YVR and YXL
Talos production clusters. This likely means site-local Garage
clusters joined through Garage federation rather than one Kubernetes
`GarageCluster` resource; that topology and its application-level semantics
must be verified. It still needs per-node routable RPC addresses, identical
RPC credentials at both sites, cross-site network policy and routing,
placement and failure-domain decisions, and
documented backup and recovery behavior. Do not treat the present YXL-only
cluster as that federated service until those dependencies and reconciliation
flows are implemented and verified. See the operator's
[multi-cluster federation guide](https://rajsinghtech.github.io/garage-operator/how-to/federation/)
and [storage identity and layout guide](https://rajsinghtech.github.io/garage-operator/concepts/storage-and-layout/).
