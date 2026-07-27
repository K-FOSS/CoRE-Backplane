# Bare Metal network chart

This chart deploys the network-facing Tinkerbell and static-artifact services
used by CoRE's Bare Metal Provisioning System. It is owned by
`Apps/Network/BareMetal.yaml` and selected for bare-metal infrastructure
clusters.

## Components and dependencies

- Tinkerbell stack, Tink server and Hegel metadata service.
- Static artifact access through S3-backed/proxy services.
- Crossplane-generated S3 users and Vault-backed credentials.
- Routes and services used before a machine has Kubernetes installed.

It requires DHCP/PXE/iPXE reachability, Tinkerbell hardware inventory, object
storage, DNS/routing/firewall policy, and the Cluster Operations compositions.
See [the BMPS documentation](../../Operations/Clusters/BMPS.md).

Changes can prevent machines from booting or target incorrect hardware.
Validate endpoint addresses, DHCP options, artifact URLs, hardware identity,
installation disks and workflow status. Test with quarantined hardware and
preserve console/out-of-band access.

| Label | Typical values | Purpose |
| --- | --- | --- |
| `resolvemy.host/computetype` | `baremetal`, `virtualmachine`, `container` | Compute implementation. |
| `resolvemy.host/nodetype` | `infra`, `compute`, `init` | Node role. |
