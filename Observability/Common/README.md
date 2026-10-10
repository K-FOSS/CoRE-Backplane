# CoRE-Backplane Observability/Common Stack

This YXL-only chart provides the Garage object-store cluster used by
[Mimir](../Metrics/README.md). It is owned by the
[Observability Common ApplicationSet](../../Apps/Observability/Common.yaml).
The Garage controller and CRDs are owned separately by the
[Garage Operator ApplicationSet](../../Apps/Storage/S3/Garage-Operator.yaml).

## Ownership and reconciliation

The ApplicationSet selects core bare-metal infrastructure clusters in DC1
region YXL and renders this chart into `core-prod`. Sync the S3 Garage Operator
first, wait for its CRDs and webhook to become healthy, then sync this chart to
create the `GarageCluster`. The Metrics ApplicationSet follows and owns the
Mimir buckets and S3 key in the same namespace.

## Garage cluster and data flow

The chart creates a three-replica Garage storage cluster with replication
factor `3`. Each Garage node requests a `20Gi` Longhorn data PVC and a `2Gi`
metadata PVC. The data StorageClass uses one Longhorn replica so Garage's
three object copies provide the data replication; the metadata class uses two
Longhorn replicas. PVC reclaim and Garage PVC retention policies are both
`Retain`. Review capacity before sync; this configuration requests 66Gi of
PVC capacity and Longhorn will additionally allocate metadata replicas.

The chart reads the operator's initial Garage Admin API token and shared RPC
secret from `mainvault-core`, CoreVault key `Garage/Mimir`, properties
`AdminToken` and `RPCSecret`. Create those values before reconciliation. The
admin token is a high-privilege control-plane credential; limit access and do
not reuse the Garage S3 key. Missing CoreVault properties leave the
ExternalSecret unready and prevent successful Garage reconciliation.

The Garage image is pinned to the Garage `v2.4.1` digest in
[values.yaml](values.yaml). Garage recommends keeping its metadata on fast
storage and uses the replication factor to distribute object copies; see the
[Garage configuration reference](https://garagehq.deuxfleurs.fr/documentation/reference-manual/configuration/)
and [Kubernetes deployment guide](https://garagehq.deuxfleurs.fr/documentation/cookbook/kubernetes/).
Longhorn class parameters are documented in its
[StorageClass reference](https://longhorn.io/docs/1.13.0/references/storage-class-parameters/).

## Operations and data retention

Validate with:

```bash
helm lint Observability/Common
helm template core-dc1-talos-prod-observability-common-prod Observability/Common --namespace core-prod
```

After reconciliation, verify the ExternalSecret is ready, GarageCluster is
Ready, all Garage PVCs are bound, and Garage health reports three nodes with a
committed layout. Then reconcile Metrics and verify its GarageBucket and
GarageKey conditions and the generated S3 Secret without printing its data.
Removing this chart removes the GarageCluster desired resource; retained PVCs
are recovery material and require deliberate cleanup only after data is
backed up and no consumer references the cluster.
