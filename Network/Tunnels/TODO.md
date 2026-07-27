# Production networking TODO

This roadmap tracks traffic-control, CNI, tunnel, routing, and operational
improvements for production ISP and enterprise deployments.

## P0: Traffic-control correctness

- [ ] Replace aggregate rate limits implemented as `fq maxrate`.
  - `fq maxrate` limits each flow, not the aggregate interface rate.
  - Use CAKE `bandwidth`, TBF, or HTB with a fair-queueing child when an
    aggregate interface or tunnel limit is intended.
  - Apply the correction consistently to SR-IOV, GRE, VXLAN, and WireGuard.
  - Preserve plain `fq` as an explicit per-flow pacing option.
- [ ] Introduce one reusable `trafficControl` values model for CNI interfaces
  and tunnel interfaces.
  - Support root qdiscs, classes, child qdiscs, handles, and options.
  - Retain compatibility with the existing `qdisc`, `bandwidth`,
    `qdiscOptions`, `qdiscHandle`, `classes`, and `priorityQueues` fields.
- [ ] Add structured `tc filter` support.
  - Support `flower` matches for DSCP, ECN, VLAN PCP, IP prefixes, protocols,
    ports, firewall marks, and tunnel metadata.
  - Support class assignment and actions such as police, drop, mark, and
    mirred.
  - Allow `skip_hw` and `skip_sw` only when explicitly configured.
  - Keep a reviewed raw-filter escape hatch for unsupported classifiers.
- [ ] Add ingress control.
  - Support ingress policing for simple hard limits.
  - Support IFB redirection with CAKE, TBF, or HTB for ingress shaping.
  - Evaluate an optional chained CNI bandwidth plugin for basic rate/burst
    limiting.
- [ ] Add Helm validation for traffic-control relationships.
  - Require class `parent` and `classid`.
  - Require filter parent, protocol, priority, classifier, and destination.
  - Reject aggregate bandwidth on qdiscs that only implement per-flow limits.
  - Validate handles, rates, burst sizes, and supported qdisc names.

### P0 acceptance

- [ ] `helm lint` and representative `helm template` fixtures pass.
- [ ] Tests cover fq pacing, CAKE shaping, HTB classes, priority queues,
  filters, and ingress shaping.
- [ ] A multi-flow throughput test confirms that aggregate limits cannot be
  exceeded.
- [ ] A failed or unsupported qdisc configuration prevents the pod from
  becoming ready and reports an actionable error.

## P1: Observability and safe rollout

- [ ] Verify the applied configuration in the init container.
  - Capture `tc -s -j qdisc`, `class`, and `filter` output.
  - Capture `ip -details link` and relevant `ethtool` state.
  - Fail when expected qdiscs, classes, or filters are missing.
- [ ] Export traffic-control and NIC metrics.
  - Queue backlog, drops, overlimits, ECN marks, and requeues.
  - Per-class packets and bytes.
  - VF/NIC errors, drops, ring exhaustion, and link state.
  - WireGuard peer handshake age and transfer counters.
  - Tunnel packet loss, latency, and reachability.
- [ ] Add dashboards and alerts.
  - Sustained qdisc backlog or drops.
  - Interface/VF errors and link flaps.
  - Missing WireGuard handshakes.
  - BFD or routing adjacency failures.
- [ ] Add canary values and a documented rollback procedure.
- [ ] Pin `nicconfig`, tunnel, FRR, and WireGuard images to tested versions or
  digests instead of `latest`.
- [ ] Add startup, readiness, and diagnostic output that distinguishes CNI,
  qdisc, tunnel, and routing failures.

## P1: SR-IOV CNI controls

- [ ] Stop hardcoding `spoofchk: off`; make it an explicit per-interface
  setting with a documented router-oriented default.
- [ ] Pass through supported SR-IOV CNI properties:
  - `trust`
  - `link_state`
  - `vlanQoS`
  - VF minimum and maximum transmit rates
  - MAC and VLAN settings
- [ ] Add optional interface tuning for:
  - Channel counts (`ethtool -L`)
  - Interrupt coalescing (`ethtool -C`)
  - RSS hash and indirection configuration
  - RPS/XPS CPU masks
  - Pause-frame, FEC, and EEE settings where supported
- [ ] Coordinate pod CPU pinning, IRQ affinity, and NUMA locality with the
  allocated SR-IOV device.
- [ ] Detect and report unsupported ethtool features instead of silently
  assuming NIC/driver support.
- [ ] Evaluate the SR-IOV metrics exporter for PF/VF health and statistics.

### SR-IOV hardware gate

- [ ] Validate every advanced feature against the production ConnectX-3 /
  `mlx4` kernel and firmware combination.
- [ ] Do not enable `mqprio`, hardware traffic-class offload, or
  `flower skip_sw` by default until tested on that hardware.
- [ ] Record supported qdiscs, classifiers, channel counts, offloads, and
  kernel modules as deployment prerequisites.

## P1: Tunnel improvements

- [ ] Use the shared traffic-control model for GRE, VXLAN, and WireGuard.
- [ ] Calculate or validate tunnel MTU from the underlay MTU and encapsulation
  overhead.
- [ ] Add configurable PMTU/DF behavior.
- [ ] Add optional TCP MSS clamping for environments where PMTU cannot be
  repaired.
- [ ] Detect and report GRE/VXLAN checksum, segmentation, and tunnel-port
  offloads.
- [ ] Add VXLAN FDB, neighbour, ageing, learning, and checksum controls.
- [ ] Consider Geneve, IPIP, and GRETAP only when a concrete deployment needs
  them.
- [ ] Add tunnel health checks using BFD or explicit peer reachability.

## P2: Routing and enterprise safeguards

- [ ] Add BFD profiles and bind them to BGP, OSPF, and tunnel peers.
- [ ] Add BGP maximum-prefix limits and warning thresholds.
- [ ] Expand route-map, prefix-list, AS-path, and community policy support.
- [ ] Add optional BGP authentication and GTSM/TTL security.
- [ ] Add graceful maintenance/drain behavior before pod termination.
- [ ] Add VRF and policy-routing support for isolated uplinks and overlapping
  address spaces.
- [ ] Add explicit asymmetric-routing sysctls, including configurable
  `rp_filter`, source validation, ARP behavior, and neighbour tuning.
- [ ] Test ECMP behavior, failure convergence, and route withdrawal during
  pod restart and node drain.

## P2: Production validation

- [ ] Add a `values.schema.json` for tunnel, interface, routing, and
  traffic-control configuration.
- [ ] Add CI fixtures for:
  - Client-only WireGuard without a listen port
  - GRE and VXLAN with aggregate shaping
  - Root CAKE
  - HTB with fq_codel and CAKE children
  - DSCP and VLAN-PCP classification
  - Ingress IFB shaping
  - Multiple SR-IOV resource types
- [ ] Run throughput, latency-under-load, fairness, loss, and failover tests.
- [ ] Test IPv4, IPv6, ECN, small packets, jumbo frames, and mixed packet
  sizes.
- [ ] Confirm shaping accuracy with GSO/GRO enabled and disabled.
- [ ] Document kernel modules, CNI plugin versions, NIC firmware, and driver
  versions used by the supported production profile.
