# CoRE deployment environment

This document records the real environment for which the Cluster Operations
chart and Bare Metal Provisioning System are being developed. It is deployment
context, not a statement of the chart's minimum requirements or a portable
reference architecture.

Inventory and capacity figures are operator-reported and current as of August
2026. Keep this document synchronized with the inventory source of truth
as the fleet changes.

## Operational scope

CoRE is a solo-operated private cloud distributed across two sites in two
Canadian provinces. Nine servers are presently managed across the sites, with
additional systems held in production or inventory. The available fleet
provides approximately:

- 1.5 TiB of aggregate RAM.
- 500 aggregate CPU cores.
- Thirteen server, workstation, and mobile systems across production and
  inventory.

The platform is designed to preserve remote access when an individual site
fails. Site independence therefore includes more than Kubernetes workload
placement: routing, identity dependencies, management access, and the
bootstrap path must remain usable or have a documented alternative during a
site outage.

## Compute fleet

| Quantity | System | Notes |
| ---: | --- | --- |
| 7 | Dell PowerEdge R620 | Rack-server fleet spanning production and inventory. |
| 1 | Dell PowerEdge R720xd | Storage-oriented rack server. |
| 2 | Dell PowerEdge R730xd | Newer storage-oriented rack servers. |
| 1 | Framework Laptop, 11th-generation Intel Core i5 | 40 GiB RAM. |
| 1 | Apple iMac 5K, Late 2015 | 32 GiB RAM. |
| 1 | Intel Core i7-8700K system | 32 GiB RAM. |

Not every inventoried system should be assumed to be an active Kubernetes node
or part of a critical quorum. Workstation and mobile-class systems can be
useful as development, lab, edge, or recovery capacity but have different
power, storage, and remote-management characteristics from the PowerEdge
fleet.

Hardware inventory should eventually be generated from NetBox/IPAM rather than
maintained manually in this document.

## dc1.yxl.resolvemy.host hardware inventory

The following records are the authoritative hardware inventory for the YXL
data-centre systems as of August 2026. Names in this section are canonical;
legacy identifiers are intentionally omitted from this public documentation.
Site, rack,
addressing, Kubernetes placement, and workload assignments remain defined by
the deployment manifests and IPAM records.

### Legacy K3s infrastructure

#### Infra1

| Field | Current record |
| --- | --- |
| Platform / identity | Dell PowerEdge R620; acquired on eBay in 2018 |
| Role and software | Legacy K3s server; Flatcar Container Linux; not a May 2026 cluster addition |
| CPU | 2 × Intel Xeon E5-2690 @ 2.90 GHz; 8 cores / 16 threads per CPU; 16 physical cores / 32 hardware threads total |
| Memory | 384 GB DDR3 ECC; 24 × 16 GB, all 24 slots populated; dual-rank; rated 1600 MHz, operating at 1333 MHz |
| DIMMs | 16 × Kingston `9965516-496.A00LF`; 8 × Hynix `HMT42GR7BFR4A-PB` |
| Storage controller | Dell PERC H710 Mini; encryption capable |
| Virtual disk | RAID5; 64 KB stripe; Write Back Force / Read Ahead; 438,489,317,376 bytes; metadata span length 4 disks |
| Physical disks currently detected | Bay 1, Bay 2, and Bay 5: Seagate `ST9146803SS`, 146,163,105,792 bytes each, SAS 6 Gb/s |
| Networking | Integrated Broadcom BCM5720 (4 × 1 GbE); Intel XXV710 add-in (2 × 25 GbE SFP28), PCIe slot 3 |
| Power | 1 × Dell 750 W PSU installed; slot 2 absent |
| Management | iDRAC7 Enterprise |

### May 2026 cluster additions

#### SRV1

| Field | Current record |
| --- | --- |
| Platform / identity | Dell PowerEdge R620; added to the cluster in May 2026 |
| CPU | 2 × Intel Xeon E5-2697 v2 @ 2.70 GHz; 12 cores / 24 threads per CPU; 24 physical cores / 48 hardware threads total |
| Memory | 128 GB DDR3 ECC; 8 × 16 GB in 8 of 24 slots; dual-rank; operating at 1333 MHz |
| DIMMs | 5 × Hynix `HMT42GR7MFR4A-H9`; 3 × Hynix `HMT42GR7AFR4A-H9` |
| Storage | Dell PERC H710 Mini, encryption capable; one HGST `HUC101212CSS600`, 1,199,638,052,864 bytes (~1.2 TB), SAS 6 Gb/s, bay 0 |
| Virtual disk | RAID0 single-disk span; 64 KB stripe; Write Back / Adaptive |
| Networking | Integrated Intel I350-t rNDC; 4 × 1 GbE |
| Power | 2 × Dell 750 W PSUs providing redundant power |
| Management | iDRAC7 Enterprise |

#### SRV3

| Field | Current record |
| --- | --- |
| Platform / identity | Dell PowerEdge R620; added to the cluster in May 2026 |
| CPU | 2 × Intel Xeon E5-2697 v2 @ 2.70 GHz; 12 cores / 24 threads per CPU; 24 physical cores / 48 hardware threads total |
| Memory | 128 GB DDR3 ECC; 8 × 16 GB in 8 of 24 slots; dual-rank; operating at 1333 MHz |
| DIMMs | 8 × Hynix `HMT42GR7AFR4A-H9` |
| Storage | Dell PERC H710 Mini, encryption capable; one HGST `HUC101212CSS600`, 1,199,638,052,864 bytes (~1.2 TB), SAS 6 Gb/s, bay 0 |
| Virtual disk | RAID0 single-disk span; 64 KB stripe; Write Back / No Read Ahead |
| Networking | Integrated Intel I350-t rNDC; 4 × 1 GbE |
| Power | 2 × Dell 750 W PSUs providing redundant power |
| Management | iDRAC7 Enterprise |

#### SRV7

| Field | Current record |
| --- | --- |
| Platform / identity | Dell PowerEdge R720xd; added to the cluster in May 2026 |
| CPU | 2 × Intel Xeon E5-2630 v2 @ 2.60 GHz; 6 cores / 12 threads per CPU; 12 physical cores / 24 hardware threads total |
| Memory | 384 GB DDR3 ECC; 24 × 16 GB, all 24 slots populated; dual-rank; rated 1600 MHz, operating at 1333 MHz |
| DIMMs | Samsung `M393B2G70QH0-YK0` |
| Storage/controller | Integrated Broadcom/LSI SAS2308 PCI-Express Fusion-MPT SAS-2 controller (PCI vendor/device Broadcom/LSI SAS2308) |
| Storage limits | The current XML export has no normal DCIM controller, physical-disk, or virtual-disk records. RAID level, drive count/capacity, and virtual-disk layout are therefore unknown; any independently documented storage details not contradicted here remain valid. |
| Networking | Integrated Intel I350-t rNDC (4 × 1 GbE); Mellanox ConnectX-3 Pro (`MT27520 Family [ConnectX-3 Pro]`) in PCIe Gen 3 x16 slot 6. Port count/link speed beyond existing independent documentation is unknown. |
| Power | 2 × Dell 1100 W redundant PSUs |
| Management | iDRAC7 Enterprise |

### Scoped capacity totals

These totals are intentionally separate from the broad fleet estimates above:

| Scope | Servers | Physical cores | Hardware threads | Installed RAM |
| --- | ---: | ---: | ---: | ---: |
| May 2026 cluster additions (SRV1 + SRV3 + SRV7) | 3 | 60 | 120 | 640 GB |
| All four records in this update (Infra1 + SRV1 + SRV3 + SRV7) | 4 | 76 | 152 | 1,024 GB |

Infra1's capacity is not included in the May 2026 cluster-additions total
because it remains a legacy K3s system.

## Network fabric

The switching fleet consists of:

| Quantity | Model | Intended role |
| ---: | --- | --- |
| 2 | Cisco Nexus 92160YC-X | One data-centre switch at YVR and one at YXL. |
| 1 | Cisco Nexus N3K-C3172TQ-10GT | 10 GbE aggregation/access switching at YXL. |
| 1 | Cisco Catalyst 3850 | Campus/access and management connectivity. |

The platform uses data-centre networking concepts including BGP, OSPF, VLANs,
multi-NIC hosts, SR-IOV, and routed Kubernetes networking. Switch
configuration, firmware, topology, address allocation, and out-of-band
management paths are external dependencies of this chart and must be backed up
and documented with the same care as the Kubernetes control plane.

The Nexus 92160YC-X switches are separated by site and are not configured as a
redundant pair. Having one Nexus at each site does not by itself provide local
switching redundancy. Cross-site placement improves site-failure separation,
while shared power, management, carrier, configuration, and routing-policy
dependencies must still be considered explicitly.

## Operator workflow

Day-to-day development is performed through Eclipse Che environments running
on the platform. Authentik provides the interactive login path, allowing the
operator to access the development environment and integrated services through
single sign-on.

This is an important production workload and a practical health check for the
platform: identity, ingress, certificates, DNS, storage, networking,
Kubernetes scheduling, and the Che control plane must all work for a
development session to start.

Maintain an access path that does not depend on Authentik, Eclipse Che, or the
primary Kubernetes cluster for emergency recovery. Emergency credentials must
be strongly protected, periodically tested, and usable through the
out-of-band-management network.

## Availability experience

No formal measured service-level objective is currently asserted. Planned
maintenance, total outages, partial degradation, and individual service
failures need consistent definitions before an availability percentage can be
asserted.

The first services worth measuring from the user's perspective are:

- Authentik authentication success and latency.
- Eclipse Che workspace-start success and duration.
- DNS, ingress, and certificate availability.
- Management and out-of-band access at each site.
- Kubernetes API and Crossplane reconciliation health.
- Bare-metal provisioning success and duration.

## Failure-domain expectations

The target behavior during a single-site failure is:

- The surviving site remains remotely reachable.
- Operators retain an authentication-independent emergency access path.
- Routing converges without manual access to the failed site.
- The surviving management plane exposes enough state to diagnose the outage.
- Backups remain accessible from a failure domain separate from the affected
  site.
- Recovery does not require services that existed only at the failed site.

Not every application must necessarily remain available during a site outage.
Critical services, their recovery objectives, and whether they run
active/active, active/passive, or restore-on-demand should be documented
explicitly rather than inferred from the physical topology.

## Capacity is not an availability guarantee

The fleet has substantial aggregate capacity, but schedulable capacity is
constrained by site placement, hardware generation, memory locality, storage,
network bandwidth, quorum requirements, power, cooling, and maintenance
headroom. Capacity reporting should distinguish:

- Installed inventory.
- Powered and reachable hardware.
- Kubernetes-ready allocatable capacity.
- Capacity reserved for failover.
- Capacity unavailable because of maintenance or faults.

The cluster API and future inventory integration should expose these
distinctions instead of presenting aggregate core and memory totals as a
single interchangeable pool.
