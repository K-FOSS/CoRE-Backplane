# CoRE-Backplane Storage/S3/Operators/Garage Stack

This YXL-only stack installs the Garage Kubernetes operator and its CRDs. It is
owned by the [Garage operator ApplicationSet](../../../../Apps/Storage/S3/Garage-Operator.yaml).
The Garage cluster for observability is defined separately in
[Observability/Common](../../../../Observability/Common/README.md).

## Ownership and configuration

The ApplicationSet selects the core bare-metal infrastructure cluster in DC1
region YXL and installs the pinned upstream operator chart `0.8.1` into
`garage-operator-system`. It watches only `core-prod` for Garage custom
resources. The operator chart is published by the
[Garage Kubernetes Operator project](https://github.com/rajsinghtech/garage-operator)
as an OCI artifact. Chart version `0.8.1` is pinned; its OCI digest is
`sha256:2acc04b7ab0021664985fbd1ffac16ea9d3d79b40c4878c361480fba6ffa8c1e`.
The operator image and Garage `v2.4.1` image are pinned by digest in
[values.yaml](values.yaml).

Admission and conversion webhooks are enabled and use cert-manager with a
self-signed Issuer. cert-manager must be healthy before the operator sync.
CRDs are retained when the operator chart is removed. Remove dependent
GarageCluster, GarageBucket and GarageKey resources deliberately before
removing the controller; retain and recover the Longhorn PVCs separately.

## Reconciliation and verification

Build and render from the repository root:

```bash
helm dependency build Storage/S3/Operators/Garage
helm lint Storage/S3/Operators/Garage
helm template garage-operator-yxl Storage/S3/Operators/Garage --namespace garage-operator-system
```

After sync, verify the operator Deployment and webhook are healthy and all six
Garage CRDs are Established before syncing
[Observability/Common](../../../Observability/Common/README.md). Verify
`GarageCluster`, `GarageBucket`, and `GarageKey` readiness conditions and
inspect generated credentials only through secret references; do not print
Secret contents.

Upstream references: the operator's
[installation guide](https://rajsinghtech.github.io/garage-operator/),
[Helm chart configuration](https://github.com/rajsinghtech/garage-operator/tree/main/charts/garage-operator),
and Garage's [Kubernetes deployment guide](https://garagehq.deuxfleurs.fr/documentation/cookbook/kubernetes/).
