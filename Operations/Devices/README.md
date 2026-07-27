# Device operations deployment

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
