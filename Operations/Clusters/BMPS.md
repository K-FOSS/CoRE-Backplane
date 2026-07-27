# Bare Metal Provisioning System

The Bare Metal Provisioning System (BMPS) is the node-provisioning path built
from the `ClusterNode` Crossplane API, Tinkerbell hardware/workflows, Talos
Image Factory, and Talos machine configuration.

## Responsibility boundaries

- **Crossplane** owns the desired-state API and orchestrates composed
  Kubernetes objects and Terraform workspaces.
- **Tinkerbell** owns hardware inventory, hardware selection, PXE booting, and
  provisioning workflows.
- **Talos Image Factory** produces a schematic for the selected Talos version,
  system extensions, and kernel arguments.
- **Talos** configures the operating system, networking, Kubernetes services,
  sysctls, sysfs entries, watchdogs, and node registration.
- **Cluster API** represents cluster and machine lifecycle and connects the
  infrastructure and control-plane providers.

BMPS does not currently provide a complete inventory/IPAM user interface.
Hardware records, addresses, and labels must already be present and consistent
with the requested node.

## Provisioning lifecycle

1. An operator creates a `ClusterNode` claim with a `clusterRef`.
2. The Composition observes the referenced `Cluster`.
3. A Talos Image Factory workspace selects the Talos version and extensions
   and creates a bootable schematic.
4. Crossplane selects/observes a Tinkerbell `Hardware` object using the
   requested identity and labels.
5. BMPS generates networking and Talos machine configuration from cluster and
   node settings.
6. A Tinkerbell machine/workflow boots the host and installs Talos.
7. Talos contacts the configured control-plane endpoint and the machine joins
   Kubernetes.
8. The Composition creates node-related resources such as Cilium BGP/node or
   FRR configuration when requested.

Several resources are emitted only after an earlier observed object exposes
the required status fields. Provisioning is consequently an eventually
consistent, multi-reconciliation process.

## Required hardware data

At minimum, each target host needs a Tinkerbell `Hardware` record whose
identity, interfaces, MAC addresses, disks, and labels match the
`ClusterNode` selectors. The exact fields are defined by the installed
Tinkerbell CRDs and by `ClusterNodeResource.yaml`.

Keep these invariants:

- One active node claim should resolve to one physical machine.
- The installation disk must be stable and unambiguous.
- The provisioning NIC must be able to reach DHCP/PXE and the configured
  Tinkerbell endpoint.
- Assigned addresses must not overlap and must be routable to the cluster
  control-plane endpoint.
- Hardware labels used for cluster name, node type, and node mode must agree
  with the machine-template affinity rules.

## Configuration inheritance

The cluster supplies shared settings such as Kubernetes/Talos versions,
network ranges, time servers, routing configuration, and cluster-level
sysctls. The node supplies hardware-specific networking, extensions, kernel
parameters, sysfs settings, watchdog configuration, and node-level sysctls.

Where both levels define the same sysctl, the node setting takes precedence:

```text
built-in defaults < Cluster.spec.sysctls < ClusterNode.spec.sysctls
```

Version overrides and hardware-specific settings should be used sparingly;
they make a node different from the rest of its cluster and complicate
replacement and upgrades.

## Safe operating procedure

Before provisioning:

- Confirm the node claim references the intended cluster and namespace.
- Confirm the selected hardware record and installation disk.
- Check that Talos and Kubernetes versions are compatible.
- Check the control-plane endpoint, NTP servers, registry mirrors, and
  Tinkerbell endpoint from the provisioning network.
- Review kernel parameters, system extensions, sysctls, sysfs writes, and any
  wipe-on-reboot option.

During provisioning:

- Watch the claim, composite, `Hardware`, `TinkerbellMachine`, and workflow
  conditions.
- Correlate Tinkerbell controller logs with DHCP/PXE logs and the host console.
- Do not submit competing claims for the same hardware.

After provisioning:

- Confirm the Talos machine is healthy and has joined Kubernetes.
- Verify node addresses, labels, routes, BGP peers, and expected sysctls.
- Confirm Crossplane reports all composed resources ready.
- Preserve enough event and workflow history to diagnose the next failure.

## Recovery notes

Reprovisioning may destroy local data. The
`danger.warningdonotdounlessyouknowwhatyouaredoing.wipeOnReboot` option is
especially destructive and must not be enabled as a routine recovery action.

When a workflow fails, first determine whether the failure is in selection,
network boot, image download, disk installation, Talos configuration, or
cluster joining. Re-running without identifying that boundary can repeat disk
writes without fixing the cause.

There is not yet a documented, automated deprovisioning or rollback contract.
Until one is implemented, treat claim deletion and hardware reuse as
operator-controlled procedures and verify the resulting composed resources
and physical host state manually.
