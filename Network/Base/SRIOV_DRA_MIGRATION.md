# CoRE-Backplane Network/Base SR-IOV DRA Migration

This plan tracks moving YXL SR-IOV allocation from the SR-IOV device plugin to
Kubernetes Dynamic Resource Allocation (DRA), while retaining Multus and the
SR-IOV CNI for secondary network attachment. The fleet owner is
[`Apps/Network/Base.yaml`](../../Apps/Network/Base.yaml); this plan is linked
from the [Network/Base stack guide](README.md).

## Current YXL path

The `core-dc1-talos-prod` cluster runs Kubernetes 1.36. The current
[`Network/Base` Kustomize layer](kustomization.yaml) installs Multus, SR-IOV
CNI, and the SR-IOV network device plugin. Its ApplicationSet injects
`sriovDevicePluginResourceList` from the site-specific generator in
[`Apps/Network/Base.yaml`](../../Apps/Network/Base.yaml). Pods request those
extended resources and Multus NADs identify the same resource in
`k8s.v1.cni.cncf.io/resourceName`.

YXL inventory currently includes Intel I350 netdevice and VFIO pools, plus
Mellanox ConnectX-3 netdevice and VFIO pools. These selectors encode the PF,
PCI vendor/device, and bound driver; preserve those hardware contracts when
translating them to DRA policy and attributes. The SRV1 VF reservation is
tracked in its Talos configuration and must be carried into the eventual DRA
policy without advertising Cilium's VF or the two reserved kernel-mode VFs to
other consumers.

The intended DRA network path keeps Multus and SR-IOV CNI. The upstream
[SR-IOV DRA driver](https://github.com/k8snetworkplumbingwg/dra-driver-sriov)
has a `MULTUS` mode: the driver publishes allocated device attributes and
Multus passes the selected `deviceID` to SR-IOV CNI. A DRA policy must publish
`k8s.cni.cncf.io/resourceName` matching the NAD's
`k8s.v1.cni.cncf.io/resourceName`. This replaces the device plugin's
allocation/accounting path; it does not replace Multus or SR-IOV CNI.

## Readiness and constraints

- Kubernetes 1.36 exposes the stable `resource.k8s.io/v1` DRA API, and the YXL
  cluster has the built-in DeviceClass, ResourceClaim,
  ResourceClaimTemplate, and ResourceSlice APIs. No SR-IOV DRA classes or
  slices are currently installed there.
- The upstream driver repository currently has no tagged release, and its
  Helm chart identifies itself as `0.0.0-dev` with an `appVersion` of `latest`.
  This does not meet the repository's immutable dependency policy. Do not add
  it to the live deployment until the source revision and image are pinned,
  the chart/API compatibility is reviewed, and the image is available from an
  approved registry by digest.
- The driver's `MULTUS` mode requires Multus and a container runtime with CDI
  support. It does not provide the DRA device-metadata CDI file path available
  in `STANDALONE` mode. Verify Talos/containerd CDI behavior on the target
  nodes before selecting a deployment mode.
- Current SR-IOV-consuming applications create Pods with device-plugin
  extended-resource requests. Each chart must be updated to create or reference
  ResourceClaims, while preserving interface counts, NAD resource names,
  VLAN behavior, and site selection. Audit rendered Pods and NetworkAttachment
  Definitions for every YXL consumer before changing the pool owner.
- KubeVirt v1.10.0 documents that SR-IOV interfaces are not supported with its
  DRA network integration. Keep KubeVirt SR-IOV VM passthrough on its existing
  compatibility path until upstream support and the VM claim flow are proven;
  do not treat enabling KubeVirt's `NetworkDevicesWithDRA` feature gate as part
  of the Multus migration.
- Device-plugin and DRA allocations must not advertise overlapping physical
  VFs to independent allocators. During a canary, carve disjoint VF sets or
  nodes, verify the live PCI/VF ownership, and only then remove the old pool
  advertisement for migrated devices.

## Migration sequence

1. Pin and review a released (or explicitly approved immutable source build of)
   the SR-IOV DRA driver, including its CRDs, RBAC, node privileges, container
   runtime requirements, upgrade and removal behavior, and supported
   Kubernetes APIs.
2. Reconcile the physical inventory from the YXL Talos node configurations
   and live node state. Map each VF to its PF, PCI ID, kernel/VFIO binding,
   and owner. Preserve the SRV1 Cilium and kernel-mode reservations.
3. In a non-production test cluster or on a disjoint canary VF set, install
   the driver in `MULTUS` mode and create narrowly selected
   `SriovResourcePolicy` and `DeviceAttributes` resources. Confirm
   ResourceSlices advertise only the intended VFs and that one Multus
   attachment consumes exactly one intended VF.
4. Migrate one YXL pod workload at a time. Verify its claim allocation,
   scheduler placement, Multus network status, PCI device assignment, VLAN,
   routes, and application traffic. Keep a rollback manifest for restoring
   the device-plugin request and pool.
5. Migrate VFIO and KubeVirt consumers separately after the driver's VFIO
   lifecycle and KubeVirt integration are verified. Remove device-plugin
   selectors only after all consumers and allocations on those VFs have
   drained successfully.

## Operational verification and rollback

Before and after each canary, compare the node's ResourceSlices and
ResourceClaims with the PCI/PF inventory, inspect Multus network-status, and
confirm allocated VFs are not simultaneously exposed by the SR-IOV device
plugin. Exercise pod deletion and rescheduling to verify VF cleanup and reuse.
Rollback by restoring the device-plugin pool and workload resource requests
for the affected disjoint VF set, then confirm DRA claims are released before
returning those VFs to the legacy allocator. Do not run both allocators over
the same VFs during rollback.

Upstream references: [SR-IOV DRA driver documentation](https://github.com/k8snetworkplumbingwg/dra-driver-sriov),
[Multus DRA integration](https://github.com/k8snetworkplumbingwg/multus-cni/blob/master/docs/how-to-use.md),
[Kubernetes Dynamic Resource Allocation](https://kubernetes.io/docs/concepts/scheduling-eviction/dynamic-resource-allocation/),
and [KubeVirt v1.10.0 release notes](https://kubevirt.io/2026/changelog-v1.10.0.html).
