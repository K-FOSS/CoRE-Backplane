# CoRE-Backplane Operations/VirtualMachines Stack

This Lovely deployment installs KubeVirt, CDI and KubeVirt Manager using
remote Kustomize resources, then creates the KubeVirt/CDI custom resources and
management route/policy. It is owned by [Apps/Infra/KubeVirt.yaml](../../Apps/Infra/KubeVirt.yaml)
and is listed in the [Operations overview](../README.md).

KubeVirt is pinned to [v1.10.0](https://github.com/kubevirt/kubevirt/releases/tag/v1.10.0), and CDI is pinned to [v1.66.1](https://github.com/kubevirt/containerized-data-importer/releases/tag/v1.66.1);
the operator installs the CDI CRDs and controllers before the CDI custom
resource in this stack. KubeVirt Manager currently tracks a mutable upstream
`main` manifest. Inspect and preferably pin the fetched manager resources for
reproducibility. See the [CDI upstream repository](https://github.com/kubevirt/containerized-data-importer)
for operator documentation and release notes.

The KubeVirt operator and operand are upgraded together because this KubeVirt
resource does not set `spec.imageTag`. The v1.9.1 to v1.10.0 change follows
the supported upgrade path; v1.10 supports Kubernetes 1.37 and the previous
two minor versions, including the YXL Kubernetes 1.36 cluster. KubeVirt enables
Beta feature gates by default, so the CR explicitly disables Beta gates to
retain the established opt-in behavior. This includes the v1.10 additions
`ContainerPathVolumes`, `IncrementalBackup`, `NetworkDevicesWithDRA`,
`UtilityVolumes`, and `VSOCK`. KubeVirt v1.10 also notes that SR-IOV interfaces
are not supported with DRA networks, so enabling the DRA network gate is not
part of this upgrade. See the [KubeVirt update guide](https://kubevirt.io/user-guide/cluster_admin/updating_and_deletion/),
[v1.10.0 release notes](https://kubevirt.io/2026/changelog-v1.10.0.html),
and the [v1.10.0 feature-gate report](https://github.com/kubevirt/kubevirt/releases/download/v1.10.0/feature-gates.json).

The v1.10.0 operator CRD exceeds the client-side apply annotation limit. The
Kustomize resource is fetched from the official operator release; manual
installation or recovery must use server-side apply (`kubectl apply
--server-side`) or `kubectl create`, as documented in the [release notes](https://github.com/kubevirt/kubevirt/releases/tag/v1.10.0).

## Dedicated CPUs with DRA

The DC1 [ApplicationSet](../../Apps/Infra/KubeVirt.yaml) enables KubeVirt
v1.10's alpha `CPUsWithDRA` feature gate. Home1 and K3s leave it disabled.
For a VM with `dedicatedCPUPlacement: true`, KubeVirt creates a CPU
`ResourceClaim` for the `dra.cpu` DeviceClass and adds it to the launcher Pod.
The [CPU DRA driver](../Devices/README.md) is installed by the earlier device
ApplicationSet sync wave. See the upstream [KubeVirt v1.10 release notes](https://kubevirt.io/2026/changelog-v1.10.0.html)
and [CPU DRA driver installation guide](https://dra-driver-cpu.sigs.k8s.io/docs/user/installation/).
No DC1 VMIs were running when this configuration was prepared. The driver
requires kubelet `cpuManagerPolicy: none`; this was observed on all three DC1
nodes. CPU DRA VMIs cannot live migrate, and NUMA guest mapping passthrough
is incompatible with this gate, as described in the
[KubeVirt CPU DRA implementation](https://github.com/kubevirt/kubevirt/pull/19228).
Verify claim allocation and CPU pinning on a
test VM before enabling dedicated CPU placement on a production VM.

KubeVirt monitoring is configured for the shared [Alloy services collector](../../Observability/Collectors/README.md):
`monitorNamespace` and `serviceMonitorNamespace` are `core-prod`, and
`monitorAccount` is `core-collectors-alloy-services`. KubeVirt creates the
`prometheus-kubevirt-rules` ServiceMonitor for the `kubevirt-prometheus-metrics`
Service; Alloy discovers it and forwards the component and VMI metrics to
Mimir. The account must remain the ServiceMonitor collector identity, not a
Prometheus instance that is no longer deployed. See the upstream [KubeVirt
component monitoring guide](https://kubevirt.io/user-guide/user_workloads/component_monitoring/).

The upstream [KubeVirt monitoring repository](https://github.com/kubevirt/monitoring)
provides the [KubeVirt Control Plane dashboard](https://github.com/kubevirt/monitoring/blob/3b7d265a9be46a3bc3b27d03de81728069f2b587/dashboards/grafana/kubevirt-control-plane.json).
This stack renders it from the pinned
[`dashboards/kubevirt-control-plane-3b7d265.json`](dashboards/kubevirt-control-plane-3b7d265.json)
(SHA-256 `1130b5c292b62181d4fbddfec9b7dca1eb4eea85bfd329ba6211a84c2d051337`)
through [`KubeVirtControlPlaneDashboard.yaml`](templates/KubeVirtControlPlaneDashboard.yaml).
The KubeVirt operator manages KubeVirt components and monitoring resources, but
does not install Grafana dashboards; dashboards are community maintained. The
dashboard ConfigMap is rendered for production into `core-prod`, where the
existing Grafana dashboard syncer discovers it and imports it into the `KubeVirt`
folder. Its instance selector is adjusted to match Alloy's cAdvisor labels,
and the syncer supplies cluster, datacenter, and region scoping. See the
[KubeVirt metrics reference](https://kubevirt.io/monitoring/metrics.html).
The dashboard includes Kubernetes API server and etcd panels; those metric
families were absent from DC1 Talos Mimir when added, so those panels may be
empty until those sources are collected.

For per-VM performance triage, this stack also imports the community
[KubeVirt VM dashboard 25821](https://grafana.com/grafana/dashboards/25821-kubevirt-vm/)
from pinned [revision 1](https://grafana.com/api/dashboards/25821/revisions/1/download).
Its upstream JSON is stored at
[`dashboards/kubevirt-vm-grafana-25821-rev1.json`](dashboards/kubevirt-vm-grafana-25821-rev1.json)
(SHA-256 `c050de3b56f0a4d925c2560450d023a3e534c685480aeb0885f4319ad6ecc0a7`)
and adapted in [`KubeVirtVMPerformanceDashboard.yaml`](templates/KubeVirtVMPerformanceDashboard.yaml).
The `KubeVirt VM Performance` dashboard covers CPU use, vCPU delay/wait,
resident versus configured memory, network traffic and drops, and disk IOPS,
throughput, and latency. It uses the existing KubeVirt metrics and the
`kubevirt_vmi_vcpu_delay:rate5m` / `kubevirt_vmi_vcpu_wait:rate5m` recording
rules defined in the [Metrics stack](../../Observability/Metrics/templates/MimirClusterResourceRules.yaml).
The upstream revision expects `kubevirt_vmi_vcpu_count` and node CPU frequency
series, which are not available in DC1 Talos Mimir. The local overlay removes
those dependencies, shows CPU usage in cores, and identifies whether the
selected VM currently has a VMI. No vCPU-normalized CPU percentage is shown
because the collected metrics do not provide a vCPU count.

The Metrics stack records both `kubevirt_vmi_cpu_usage:rate5m` (vCPU plus
hypervisor time) and `kubevirt_vmi_vcpu_usage:rate5m` (guest vCPU time). Their
difference is host-side virtualization overhead and should not be interpreted
as VyOS guest CPU. The `kubevirt_vmi_vcpu_delay:rate5m` and
`kubevirt_vmi_vcpu_wait:rate5m` series expose scheduler and I/O pressure.

Virtualization requires hardware virtualization, device access, storage
classes and network attachments. Validate operator/CRD compatibility, live
migration prerequisites, CDI imports, VM console access, disruption behavior
and backups before upgrades.

## Migration and GPU TODOs

These are planned changes; this stack currently does not migrate or rewrite
existing VMs automatically.

- [ ] Confirm the installed KubeVirt version and feature-gate report before
  changing `templates/KubeVirt.yaml`. The current v1.10.0 resource accepts
  [`KubeVirtSpec`](https://kubevirt.io/api-reference/v1.10.0/definitions.html#v1.KubeVirtSpec),
  [`KubeVirtConfiguration`](https://kubevirt.io/api-reference/v1.10.0/definitions.html#v1.KubeVirtConfiguration),
  [`SMBiosConfiguration`](https://kubevirt.io/api-reference/v1.10.0/definitions.html#v1.SMBiosConfiguration),
  and [`KubeVirtWorkloadUpdateStrategy`](https://kubevirt.io/api-reference/v1.10.0/definitions.html#v1.KubeVirtWorkloadUpdateStrategy).
  Recheck the [feature-gate lifecycle and v1.8/v1.9 behavior](https://kubevirt.io/user-guide/cluster_admin/activating_feature_gates/)
  on every operator upgrade.
- [ ] Establish the GPU passthrough path for each affected VM: device-plugin
  resource name, `HostDevices` gate, node labels, IOMMU/VFIO setup, guest
  driver, and the VM's emulated video device. `HostDevices` makes passthrough
  possible and `VideoConfig` controls the emulated video device. Test the
  VM-specific CPU, KVM, Hyper-V and video
  settings against the [KubeVirt `DomainSpec`](https://kubevirt.io/api-reference/v1.10.0/definitions.html#v1.DomainSpec),
  [`FeatureHyperv`](https://kubevirt.io/api-reference/v1.10.0/definitions.html#v1.FeatureHyperv),
  [`FeatureKVM`](https://kubevirt.io/api-reference/v1.10.0/definitions.html#v1.FeatureKVM),
  and [GPU passthrough guidance](https://kubevirt.io/user-guide/compute/host-devices/).
- [ ] Add explicit, values-driven migration defaults in the VM chart rather
  than relying on this platform CR alone: migratable network bindings, shared
  storage, compatible CPU/machine settings, and a migration policy. Review the
  [live-migration requirements and limitations](https://kubevirt.io/user-guide/compute/live_migration/)
  and the [`MigrationConfiguration` schema](https://kubevirt.io/api-reference/v1.10.0/definitions.html#v1.MigrationConfiguration)
  before enabling them fleet-wide.
- [ ] Define the default VM disk policy for migration in
  [`Lab/VMs/values.yaml`](../../Lab/VMs/values.yaml) and
  [`Lab/VMs/templates/VMs.yaml`](../../Lab/VMs/templates/VMs.yaml): use a
  storage class with `ReadWriteMany`, choose filesystem versus block mode,
  keep the disk attachment on a migration-compatible bus, and set CDI source
  and preallocation behavior deliberately. Validate the resulting
  [`DataVolumeTemplateSpec`](https://kubevirt.io/api-reference/v1.10.0/definitions.html#v1.DataVolumeTemplateSpec),
  [`PersistentVolumeClaimSpec`](https://kubevirt.io/api-reference/v1.10.0/definitions.html#v1.PersistentVolumeClaimSpec),
  and [`Disk`](https://kubevirt.io/api-reference/v1.10.0/definitions.html#v1.Disk)
  against the installed CDI/KubeVirt CRDs.
- [ ] Inventory current VMs and their PVCs, then migrate them one at a time to
  migratable volumes. Preserve VM names, MAC addresses, boot order, guest
  identity and network attachments; take a tested snapshot/backup first, and
  do not replace a live PVC until the rollback path and storage-class recovery
  behavior are proven. A `ReadWriteOnce` PVC, SR-IOV/bridge network, pinned
  node, or passthrough device can keep a VM non-migratable even when the
  KubeVirt CR is configured for `LiveMigrate`.
- [ ] Add a verification runbook that checks `LiveMigratable`, migration
  conditions/events, PVC access mode and storage class, VMI network bindings,
  GPU assignment, guest driver behavior, and rollback after a controlled node
  drain. Use the [workload-update strategy documentation](https://kubevirt.io/user-guide/cluster_admin/updating_and_deletion/)
  to distinguish operator-driven updates from an explicit VM migration.

## VM details supplied by the KubeVirt resource

The cluster-wide [`KubeVirt` resource](templates/KubeVirt.yaml) supplies these
defaults or capabilities to VMIs; it does not replace the per-VM
[`VirtualMachine` template](../../Lab/VMs/templates/VMs.yaml).

| KubeVirt setting | Current value | Effect on a VM |
| --- | --- | --- |
| `configuration.developerConfiguration.featureGates` | `HostDevices` | Enables alpha host-device assignment for passthrough resources. `LiveMigration`, `ExpandDisks`, and `VideoConfig` are GA in v1.10.0 and are always enabled. |
| `configuration.developerConfiguration.disabledFeatureGates` | Beta gates in the v1.10.0 report | Keeps Beta features opt-in across the upgrade. `VideoConfig` is GA and remains available. |
| `configuration.smbios.manufacturer` | `Talos Virtualization` | SMBIOS manufacturer presented to the guest. |
| `configuration.smbios.product` | `talosvm` | SMBIOS product presented to the guest. |
| `configuration.smbios.family` | `ccio` | SMBIOS family presented to the guest. |
| `configuration.smbios.sku` | `TalosCloud` | SMBIOS SKU presented to the guest. |
| `configuration.smbios.version` | `v0.1.0` | SMBIOS version presented to the guest. |
| `workloadUpdateStrategy.workloadUpdateMethods` | `LiveMigrate` | Requests live migration for operator-managed workload updates when the individual VMI is migratable. It does not make a VM migratable. |

The [v1.10.0 `SMBiosConfiguration` schema](https://kubevirt.io/api-reference/v1.10.0/definitions.html#v1.SMBiosConfiguration)
defines the five `smbios` fields above. The guest-visible machine type, CPU
model/topology, memory, firmware, devices, network bindings, and disk
attachments come from each VM's `spec.template.spec.domain` and are rendered
by the lab VM chart. For the operational meaning of those fields, use the
[KubeVirt virtual-hardware guide](https://kubevirt.io/user-guide/compute/virtual_hardware/)
and the pinned [`DomainSpec` schema](https://kubevirt.io/api-reference/v1.10.0/definitions.html#v1.DomainSpec).

The `TalosCloud` value is an SMBIOS identity string; it is not a KubeVirt
cloud profile and does not configure Talos, CPU compatibility, GPU behavior,
storage, or migration. Confirm the effective values from the rendered VM/VMI
and libvirt domain XML after reconciliation rather than assuming that a
cluster-wide KubeVirt default overrides an explicit VM field.

## CDI utility pod resources

The CDI `podResourceRequirements` setting applies to its clone, import and
upload utility pods. This stack requests `100m` CPU and `60M` memory, with
limits of `4` CPU and `600M` memory. CDI uses these values when it creates
utility pods; pods already running keep their existing resources. See the
[CDI configuration reference](https://github.com/kubevirt/containerized-data-importer/blob/v1.66.1/doc/cdi-config.md)
and [CDI quota guidance](https://github.com/kubevirt/containerized-data-importer/blob/v1.66.1/doc/quota.md).

When a clone restarts, compare the `cdi-clone-source` pod's last termination
with the matching upload server's logs. A source pod can complete its stream
and still fail when the upload server cannot write the extracted disk to
`/data`. Longhorn filesystem ownership handling is configured by
[`Storage/Base`](../../Storage/Base/README.md): its CSI driver honors the
`fsGroup: 107` security context CDI sets on transfer pods, including for RWX
claims. The CPU limit does not resolve a destination filesystem permission
failure.
