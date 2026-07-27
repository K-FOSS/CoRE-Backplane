# Lab VMs chart

This chart creates KubeVirt lab virtual machines, CDI-backed disks and
installer images, Multus networks, and optional Services for ports reached
through KubeVirt's pod-network masquerade interface.

The fleet entry point is
[`Apps/Lab/VMs.yaml`](../../Apps/Lab/VMs.yaml). It selects bare-metal clusters
and injects per-cluster VM, installer, and network lists through Lovely. Its
values are authoritative for deployed labs; the checked-in
[`values.yaml`](values.yaml) provides defaults and examples.

## Resources and lifecycle

The chart renders:

- one `NetworkAttachmentDefinition` for every item in `networks`;
- one standalone CDI `DataVolume` for every item in `installers`;
- one KubeVirt `VirtualMachine` for every item in `vms`;
- an embedded `dataVolumeTemplate` for each enabled VM disk; and
- one or more Services for VM ports with `expose: true`.

VMs are rendered with `spec.running: true`. A VM disk is enabled when
`disk.enabled` is omitted, so explicitly set `disk.enabled: false` for an
ephemeral VM with no data disk. With no disk source, CDI creates a blank disk.

Installer DataVolumes are independent resources shared by name. A VM with
`installing: true` attaches the named installer at boot order 1 and defaults
its data disk to boot order 2. Changing `installing` to `false` removes the
installer attachment and makes the data disk boot order 1.

The owning ApplicationSet uses `preserveResourcesOnDeletion: true`. Do not
assume that removing an ApplicationSet-generated Application cleans up VM
disks; inspect the Application, VirtualMachine, DataVolume, and PVC deletion
policy before removing a lab.

## Prerequisites

- KubeVirt and CDI, installed by the virtual-machine operations deployment.
- Multus and each CNI plugin used by `networks`.
- Matching SR-IOV device-plugin resources on schedulable nodes.
- A default or explicitly selected `StorageClass` that supports the requested
  access mode, volume mode, and cloning behavior.
- Network VLANs, bridges, MTUs, and device resources configured on the target
  cluster.
- ExternalDNS only when `externalDNSHostname` is used.
- Hardware virtualization and any device-plugin resources requested by GPUs
  or host devices.

See [Virtual Machine operations](../../Operations/VirtualMachines/README.md)
for the platform-level KubeVirt deployment.

## Values

### Global and compute defaults

| Value | Meaning |
| --- | --- |
| `env` | Environment label injected by the ApplicationSet. It is currently not consumed directly by the templates. |
| `vmDefaults` | Default compute, memory, resources, scheduling, and device settings inherited by every VM. |
| `vms` | VM definitions. Per-VM settings override `vmDefaults`. |
| `installers` | Shared CDI DataVolumes, typically installation ISOs or bootable seed images. |
| `networks` | Multus NAD definitions available to VM interfaces. |

The CPU key is singular: `cpu`, not `cpus`. `cpu.cores`, `sockets`, and
`threads` define guest-visible topology, while `resources.requests` and
`resources.limits` control Kubernetes scheduling and cgroup allocation. For
guaranteed CPU allocation, use equal whole-number CPU requests and limits with
`cpu.dedicatedCpuPlacement: true`.

`memory.guest` is the guest-visible memory. Resource memory requests and
limits remain separate. Huge pages can be passed through in `memory.hugepages`
and the corresponding resource request/limit.

The following scheduling fields can be set in `vmDefaults` or on a VM:
`priorityClassName`, `nodeSelector`, `affinity`, `tolerations`,
`topologySpreadConstraints`, `schedulerName`, and `evictionStrategy`.
Per-VM values replace their default counterpart.

Arbitrary KubeVirt device entries can be placed under `devices`, including
`gpus` and `hostDevices` with their device-plugin `deviceName`.

### Installer images

Every installer requires `name` and `size`, plus one source:

- `url`, shorthand for `source.http.url`;
- a full CDI `source` such as `http`, `registry`, `pvc`, `snapshot`, `blank`,
  `upload`, or `vddk`; or
- `sourceRef`, for example a CDI `DataSource`.

Supported PVC/DataVolume options include `contentType`, `preallocation`,
`priorityClassName`, `storageClassName`, `volumeMode`, and `accessModes`.
HTTP shorthand also supports `secretRef`, `certConfigMap`, and `extraHeaders`.

An ISO installer and a bootable disk image are different workflows:

- Import an ISO as an installer, set `vms[].installing: true`, and reference
  its name through `vms[].installer`.
- Import a bootable image as a seed, clone it with `vms[].disk.source.pvc`,
  leave `installing: false`, and boot from the cloned writable VM disk.

For a PVC clone, the source namespace must match the release namespace unless
cross-namespace cloning is explicitly authorized by CDI.

### VM disks and attachments

`vms[].disk` controls the persistent VM disk:

| Value | Meaning |
| --- | --- |
| `enabled` | Defaults to `true` when omitted. |
| `size` | Requested PVC size; defaults to `20Gi`. |
| `url`, `source`, `sourceRef` | CDI source. With none of these, a blank disk is created. |
| `contentType`, `preallocation`, `priorityClassName` | DataVolume options. |
| `storageClassName`, `volumeMode`, `accessModes` | PVC options. |
| `attachment.type` | `disk` (default), `cdrom`, or `lun`. |
| `attachment.bus` | Shorthand for the target bus. Defaults are `virtio` for disk, `sata` for CD-ROM, and `scsi` for LUN. |
| `attachment.bootOrder` | Defaults to 2 while installing and 1 otherwise. |
| `attachment.target` | Additional fields for the selected KubeVirt disk target. |
| `attachment.options` | Common KubeVirt Disk fields such as cache, I/O mode, serial, dedicated I/O thread, block size, and tag. |

`installerAttachment` supports the same attachment structure. It defaults to
a SATA CD-ROM at boot order 1.

Example ISO installation:

```yaml
installers:
  - name: debian
    url: https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian.iso
    size: 2Gi

vms:
  - name: debian-lab
    installing: true
    installer: debian
    disk:
      enabled: true
      size: 20Gi
    podNetwork:
      enabled: true
```

After installation succeeds, set `installing: false` and sync again. The
existing VM DataVolume remains the boot disk.

### Firmware

Set `boot.secureBoot: true` to render EFI Secure Boot. `tpm.enabled: true`
adds a TPM device. The chart currently does not render `boot.mode`, `uefi`, or
an explicit non-Secure-Boot EFI stanza; those values in existing examples
should not be treated as effective firmware controls.

Secure Boot typically needs SMM (enabled by this chart), UEFI-compatible guest
media, and a TPM for operating systems that require one.

### Networks

Each top-level network becomes a NAD:

| Value | Meaning |
| --- | --- |
| `name` | NAD name and the name referenced by `vms[].networks[]`. |
| `type` | CNI type; defaults to `sriov`. |
| `vlan`, `mtu` | Included in the CNI configuration when set. |
| `sriov.device` | Required for SR-IOV; used as the NAD resource annotation and VM resource allocation. |
| `bridge` | Bridge name when `type: bridge`. |

For SR-IOV networks, the chart tracks the full network definition and lets
KubeVirt request the resource named in the NAD annotation. A VM network entry
can add a stable `macAddress`.

`podNetwork.enabled: true` adds KubeVirt's masquerade interface. It is the only
interface through which this chart exposes ports with Kubernetes Services.
Multus interfaces are attached directly and are not selected by those
Services.

### Ports and Services

`vms[].ports` defines guest ports on the pod-network masquerade interface:

| Value | Meaning |
| --- | --- |
| `name` | KubeVirt port name and default Service group name. |
| `port` | Guest/target port. |
| `protocol` | `TCP` by default; values are upper-cased in the Service. |
| `expose` | Create a Service for this port. Requires `podNetwork.enabled: true`. |
| `serviceName` | Groups multiple ports into `<vm>-<serviceName>`. Defaults to the port name. |
| `servicePort` | Service-facing port; defaults to the guest port. |
| `serviceType` | Defaults to `ClusterIP`. |
| `serviceLabels` | Labels placed on the generated Service. |
| `externalDNSHostname` | Adds the ExternalDNS hostname annotation. |

Ports grouped under the same `serviceName` must use identical `serviceType`,
`serviceLabels`, and `externalDNSHostname`, or rendering fails.

The ApplicationSet augments exposed Services with environment-specific labels
before values reach the chart. Review the rendered merge rather than assuming
the checked-in chart values are the final Service configuration.

Example grouped Service:

```yaml
podNetwork:
  enabled: true
ports:
  - name: http
    port: 80
    expose: true
    serviceName: web
    externalDNSHostname: lab.example.com
  - name: https
    port: 443
    expose: true
    serviceName: web
    externalDNSHostname: lab.example.com
```

When grouping ports, repeat `externalDNSHostname` on both entries; group
settings are intentionally required to match.

## Rendering and validation

From the repository root:

```sh
helm lint Lab/VMs
helm template lab-vms Lab/VMs \
  --namespace core-testing > /tmp/lab-vms.yaml
```

To reproduce a real cluster, copy its `installers`, `networks`, and `vms`
values from `Apps/Lab/VMs.yaml` into a temporary file and pass it with `-f`.
Pay special attention to the values transformed in `LOVELY_HELM_MERGE`.

Before syncing, inspect at least:

```sh
yq 'select(.kind == "VirtualMachine") |
  {name: .metadata.name, networks: .spec.template.spec.networks,
   resources: .spec.template.spec.domain.resources,
   volumes: .spec.template.spec.volumes}' /tmp/lab-vms.yaml
yq 'select(.kind == "DataVolume" or .kind == "Service") |
  {kind: .kind, name: .metadata.name, spec: .spec}' /tmp/lab-vms.yaml
```

After syncing:

```sh
kubectl -n core-testing get vm,vmi,dv,pvc
kubectl -n core-testing get network-attachment-definitions,services
kubectl -n core-testing describe dv <data-volume>
kubectl -n core-testing describe vmi <vm-name>
```

Check CDI import/clone completion before diagnosing VM boot, then check VMI
scheduling events, device-plugin capacity, Multus attachment events, guest
console output, and guest network configuration in that order.

## Change safety

- Removing or renaming a VM can orphan or delete storage depending on Argo CD,
  KubeVirt, CDI, and PVC ownership behavior. Back up irreplaceable disks first.
- A wrong clone source or installer name can boot unintended media.
- SR-IOV device names and VLANs are cluster-specific; a valid render does not
  prove that a node has capacity or physical connectivity.
- Changing MAC addresses can invalidate DHCP leases, firewall rules, or router
  configuration.
- CPU passthrough, dedicated placement, huge pages, GPUs, host devices, and
  strict affinity can make a VM unschedulable.
- `LoadBalancer` or externally published Services can expose a guest beyond the
  lab. Verify labels, DNS names, firewall policy, and listening services.

Use the KubeVirt console or out-of-band guest access while changing routing or
firewall VMs so a network mistake does not remove the only recovery path.
