# CoRE-Backplane Operations/Devices Stack

This Lovely deployment installs optional hardware/device integrations and is
owned by `Apps/Operations/Devices.yaml`.

Supported components include NVIDIA device plugin and DRA driver, HAMi,
AMD/Intel GPU plugins, Intel device-plugin operator, Node Feature Discovery and
Kepler. The ApplicationSet also injects Kustomize patches.

GPU/device plugins often require host devices, privileged access, runtime
classes, labels and vendor drivers. Enable only hardware present in the target
cluster. Validate node discovery, allocatable resources, scheduling, device
isolation and workload teardown. Driver/plugin upgrades can strand workloads
or require node reboot.

## SR-IOV DRA migration

This stack owns the opt-in SR-IOV DRA policy renderer in
[`templates/SriovDraPolicy.yaml`](templates/SriovDraPolicy.yaml). It is disabled
by default. Each `devices.sriovDra.pools` entry requires a name, a Multus NAD
resource name, an explicit node selector, and hardware resource filters. It
renders `DeviceAttributes` and `SriovResourcePolicy` in this Application's
destination namespace (`kube-system`). The driver must watch `kube-system` and
install its CRDs before enabling the policy. See the upstream
[SR-IOV DRA driver policy and MULTUS mode guide](https://github.com/k8snetworkplumbingwg/dra-driver-sriov/blob/main/README.md).

DC1 enables the upstream controller, kubelet plugin, CRDs, and DeviceClass
through the pinned [SR-IOV DRA Helm chart at commit `5125c9d`](https://github.com/k8snetworkplumbingwg/dra-driver-sriov/tree/5125c9dea8853cc0fad300f845b3e6c5a1000a67/deployments/helm/dra-driver-sriov).
The chart version is `0.0.0-5125c9d` and its OCI digest is
`sha256:f2014a852030af6b3b6454a2d7db0de512f8069592433f6874e1ff6c4224503b`.
The driver image is pinned to
`sha256:719cc5763341243558194feafb2cfe755279dc8c930ece981bc6e4af5f8dc7ca`.
The kubelet plugin runs in `MULTUS` mode; its SR-IOV CNI installer is disabled
because Network/Base already installs that binary. Home1 and K3s leave the
driver disabled.

DC1 currently configures no DRA policy pools, so this installation advertises
no VFs. Before adding a pool, verify Talos CDI support and inventory an
exclusive canary VF set that the device plugin does not advertise. The
[migration plan](../../Network/Base/SRIOV_DRA_MIGRATION.md) records pool
ownership and rollback requirements. The device plugin remains the production
allocator for Tunnelers. Verify the controller and kubelet plugin rollout,
`DeviceClass`, CRDs, and absence of advertised VFs in DRA ResourceSlices
before adding any policies.
To roll back this installation, disable `devices.sriovDra` on DC1; do not
remove the CRDs until claims and policies have been removed.
