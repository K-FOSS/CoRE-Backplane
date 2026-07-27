# CoRE deployment environment

This document records the real environment for which the Cluster Operations
chart and Bare Metal Provisioning System are being developed. It is deployment
context, not a statement of the chart's minimum requirements or a portable
reference architecture.

Inventory and capacity figures are operator-reported and current as of
2026-07-27. Keep this document synchronized with the inventory source of truth
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

The Nexus 92160YC-X switches are separated by site; they are not configured as
a redundant pair. Each site must therefore treat its local switch as a
potential single point of failure unless other documented switching paths
exist. Cross-site placement improves site-failure separation but does not
provide local switching redundancy. Shared power, management, carrier,
configuration, and routing-policy dependencies must still be considered
explicitly.

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

The operator reports that the platform is normally available, with only a few
hours of interruption in a typical month and an occasional day of disruption
roughly every six months, usually during scheduled work.

This is useful operational history, but it is not yet a measured service-level
objective. Planned maintenance, total outages, partial degradation, and
individual service failures need consistent definitions before an availability
percentage can be asserted.

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
