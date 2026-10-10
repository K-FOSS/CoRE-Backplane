# CoRE-Backplane Storage/S3/SeaweedFS/Operator Stack

This YXL-only stack installs the SeaweedFS controller and its CRDs. It is
owned by the [operator ApplicationSet](../../../../Apps/Storage/S3/SeaweedFS-Operator.yaml)
and supports the separate [SeaweedFS workload](../README.md).

## Ownership, target and rendering

The ApplicationSet selects core bare-metal infrastructure clusters labelled
`dc1` and `yxl`; the current target is `core-dc1-talos-prod`. It renders the
official [SeaweedFS Operator Helm chart](https://github.com/seaweedfs/seaweedfs-operator)
version `0.1.43` (operator application `1.0.40`) into the dedicated
`seaweedfs-operator-system` namespace. The chart owns the CRDs, controller,
webhook and cluster RBAC. Its image is selected by the chart's immutable
release version but its values expose a tag rather than a digest.

## Reconciliation and removal

Sync this operator Application first and wait until its CRDs report
`Established` before syncing the workload Application. These are distinct
Argo CD Applications; the ApplicationSets do not enforce child sync order.
The operator chart configures its webhook and disables optional dashboard,
ServiceMonitor and CSI resources.

Build and validate from the repository root:

```bash
helm dependency build Storage/S3/SeaweedFS/Operator
helm lint Storage/S3/SeaweedFS/Operator
helm template seaweedfs-operator-yxl Storage/S3/SeaweedFS/Operator --namespace seaweedfs-operator-system
```

After sync, verify the Deployment and webhook are healthy and the Seaweed CRDs
are Established. Removing the operator ApplicationSet removes its managed
controller and CRDs according to Argo CD ownership; remove the workload and
preserve its retained Longhorn data before removing the controller.
