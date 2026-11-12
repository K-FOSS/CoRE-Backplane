# CoRE-Backplane Storage/S3/Operators/Garage Stack

This YVR/YXL stack installs the Garage Kubernetes operator and its CRDs. It is
owned by the [Garage operator ApplicationSet](../../../../Apps/Storage/S3/Garage-Operator.yaml).
The Garage cluster for observability is defined separately in
[Observability/Common](../../../../Observability/Common/README.md).

## Ownership and configuration

The ApplicationSet selects the core bare-metal infrastructure clusters in DC1
regions YVR and YXL and installs the pinned upstream operator chart `0.9.0` into
`garage-operator-system`. It watches only `core-prod` for Garage custom
resources. The operator chart is published by the
[Garage Kubernetes Operator project](https://github.com/rajsinghtech/garage-operator)
as an OCI artifact. Chart version `0.9.0` is pinned; its OCI digest is
`sha256:b42209895a946ab4977d9f9e0702e22a3f61b2337bde87fbaa6789a5cfea3659`.
The operator image and Garage `v2.4.1` image are pinned by digest in
[values.yaml](values.yaml).
This upgrade retains the existing v1beta1 conversion path but marks v1beta1
`GarageCluster` as deprecated; new resources should use v1beta2 after reviewing
the upstream [API compatibility documentation](https://rajsinghtech.github.io/garage-operator/concepts/api-versions/)
and [upgrade guidance](https://rajsinghtech.github.io/garage-operator/operations/upgrades/).
The Garage runtime image remains v2.4.1 in this change, so the controller and
storage-image rollouts stay separate.

Admission and conversion webhooks are enabled and use cert-manager with a
self-signed Issuer. cert-manager must be healthy before the operator sync.
CRDs are retained when the operator chart is removed. Remove dependent
GarageCluster, GarageBucket and GarageKey resources deliberately before
removing the controller; retain and recover the Longhorn PVCs separately.

The chart enables the operator's authenticated
[ServiceMonitor and bundled Grafana dashboard](https://github.com/rajsinghtech/garage-operator/blob/v0.9.0/docs/how-to/monitoring.md).
The dashboard ConfigMap is placed in `core-prod`, where the Grafana sidecar
discovers it. A narrowly scoped ClusterRoleBinding permits the target cluster's
central Alloy collector to read only the operator's non-resource `/metrics`
endpoint.
Those metrics include current bytes and object counts for every managed
GarageBucket. An unlimited bucket has no bucket-specific available-space
value; physical availability comes from the Garage node metrics instead.

## Reconciliation and verification

Build and render from the repository root:

```bash
helm dependency build Storage/S3/Operators/Garage
helm lint Storage/S3/Operators/Garage
helm template garage-operator Storage/S3/Operators/Garage --namespace garage-operator-system
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
