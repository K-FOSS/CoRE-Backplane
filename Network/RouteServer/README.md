# Route Server chart

This chart runs one or more FRRouting (FRR) route servers and route reflectors.
Each entry in `routeservers` produces a separate FRR workload, BGP
`LoadBalancer` Service, FRR configuration ConfigMap, and one
`NetworkAttachmentDefinition` (NAD) per data-plane interface.

The fleet entry point is
[`Apps/Network/RouteReflector.yaml`](../../Apps/Network/RouteReflector.yaml).
It selects the target clusters and injects the real site-specific route
servers, interfaces, peers, prefixes, communities, and policy. The checked-in
[`values.yaml`](values.yaml) is a reference/default configuration, not a
complete description of what runs in every cluster.

## Architecture

For a route server named `rs0`, the chart renders:

- a single FRR workload using the BJW-S common chart;
- a `LoadBalancer` Service on TCP/179, with the requested `ipAddress`
  advertised through PureLB;
- a ConfigMap containing `frr.conf`, `daemons`, and `vtysh.conf`;
- Multus NADs named `net-<release>-rs0-<index>`;
- init containers that configure MTU, ring sizes, offloads, source-specific
  routes, and optional `tc` queueing; and
- optionally, a netshoot sidecar and a Cilium egress gateway policy.

The interface at index `0` replaces the pod's default network through Multus.
Later interfaces are attached as `eth1`, `eth2`, and so on. Consequently,
reordering `networking.interfaces` changes both Linux interface names and the
FRR configuration that refers to them.

The FRR container deliberately runs `bgpd` with `--no_kernel`: learned BGP
routes are not installed into the pod's kernel forwarding table. OSPF, OSPFv3,
and IS-IS can still require `NET_ADMIN`, `NET_RAW`, `SYS_ADMIN`, and
`NET_BIND_SERVICE`.

## Prerequisites

- Argo CD and the Lovely plugin for the fleet deployment path.
- Multus and the CNI plugin named by each interface's `type`.
- The matching SR-IOV device plugin resource on eligible nodes when
  `type: sriov` is used.
- PureLB for the BGP Service address annotations.
- Cilium egress gateway support only when `networking.egressGW.enabled` is
  enabled.
- Layer-2 VLANs, MTUs, IP addressing, and peer configuration that match the
  physical fabric.

An SR-IOV interface consumes one unit of its configured extended resource.
The chart sums interfaces that use the same `sriov.device` and puts that count
in the FRR container's resource limits.

The optional egress gateway policy currently has a chart-hardcoded egress IP
and node selector. Treat it as deployment-specific and inspect the rendered
policy before enabling it.

## Values

### Top level

| Value | Meaning |
| --- | --- |
| `frr.defaultVersion` | Image tag used when a route server does not set `frr.version`. |
| `routeservers.<name>` | One independently configured FRR route server. |

### Route server

| Value | Meaning |
| --- | --- |
| `ipAddress` | FRR router ID, default BGP cluster ID, and requested PureLB Service address. It must be unique and valid for all three uses. |
| `affinity` | Pod affinity/anti-affinity passed to the workload. Use it to constrain the pod to nodes with the required NIC resources. |
| `pod.labels` | Extra labels added to the pod. |
| `networking.interfaces` | Ordered list of Multus interfaces. Index `N` becomes `ethN`. |
| `prefixLists.ipv4` | IPv4 FRR prefix lists used by route maps. |
| `routeMaps` | Ordered FRR route-map entries. The current structured matcher supports `match.ipv4PrefixList`. |
| `ospf`, `ospf6`, `isis` | Global routing-daemon configuration. An interface must also opt into the relevant protocol under `routing`. |
| `bgp` | BGP process, peer-group, peer, and address-family configuration. |
| `frr.version` | Per-server FRR image tag. |
| `frr.rawConfig` | Unstructured FRR commands appended after the generated BGP configuration. |
| `nicConfig.image` | Optional image override for NIC and traffic-control init containers. |
| `debugSidecar` | Optional sidecar sharing the pod network namespace. |

### Interfaces

Each `networking.interfaces[]` entry supports:

| Value | Meaning |
| --- | --- |
| `type` | CNI plugin type. SR-IOV receives additional resource handling. |
| `sriov.device` | Required extended resource name for SR-IOV, for example `mellanox.com/mlx4_cx3_netdevice`. |
| `sriov.vlan` | VLAN included in the generated CNI configuration. |
| `mtu`, `macAddress` | Link MTU and requested Multus MAC address. |
| `ipam.addresses` | Static IPv4 and/or IPv6 CIDRs. The legacy singular `ipam.address` is also accepted. |
| `ipam.routes` | Static routes. `dst` and `gw` go into CNI IPAM; optional `src` causes the init container to replace the route with the selected source. |
| `tuning` | A tuning CNI plugin appended after the primary plugin, commonly for sysctls. |
| `rings`, `offload` | Maps passed to `ethtool -G` and `ethtool -K`. |
| `bandwidth` | FRR interface bandwidth and, unless overridden, the root qdisc rate. `gbit` values are converted to Mbps for FRR. |
| `qdisc`, `qdiscHandle`, `qdiscOptions` | Root `tc` qdisc settings. |
| `classes`, `priorityQueues`, `trafficRules` | Advanced `tc` classes, child qdiscs, and flower filters. `filters` is retained as an alias for `trafficRules`. |
| `routing.ospf`, `routing.ospf6`, `routing.isis` | Per-interface routing configuration. Presence enables the protocol on that interface unless `enabled: false` is explicit. |
| `routing.bgp` | Numbered or unnumbered interface BGP neighbor. |

For interface BGP, omit `address` to generate an unnumbered neighbor such as
`neighbor eth0 interface`; set it for a numbered neighbor. `asn` is required.
`addressFamilies` defaults to `ipv4 unicast`, and `routeMapIn`/`routeMapOut`
attach policy to each activated address family.

### BGP configuration

`bgp.peerGroups` creates reusable groups. Every group requires `name` and
`asn`. If either `timers.keepalive` or `timers.holdtime` is set, both are
required. Optional timer values include `connect`, `delayOpen`, and
`advertisementInterval`.

`bgp.peers` creates address-based neighbors. A peer can set `remoteASN`,
`ebgpmultihop`, and/or `peerGroup`. Address-family activation for these peers
is expressed through `bgp.afi`. That structure is rendered as FRR commands,
so validate its generated output carefully.

Example interface-based neighbor:

```yaml
routeservers:
  rs0:
    ipAddress: 192.0.2.10
    networking:
      interfaces:
        - type: sriov
          mtu: 9000
          sriov:
            vlan: 50
            device: example.com/uplink
          ipam:
            addresses:
              - 192.0.2.10/31
          routing:
            bgp:
              asn: 64501
              description: fabric-spine-1
              addressFamilies:
                - ipv4 unicast
              routeMapIn: FABRIC-IN
              routeMapOut: FABRIC-OUT
    bgp:
      enabled: true
      asn: 64500
      peerGroups: []
      peers: []
      afi: {}
    frr:
      version: 10.6.1
```

## Rendering and inspection

Render the chart defaults from the repository root:

```sh
helm lint Network/RouteServer
helm template route-server Network/RouteServer \
  --namespace core-net-prod > /tmp/route-server.yaml
```

The ApplicationSet merge is authoritative for a real cluster. To reproduce a
site render, put the relevant `routeservers` block from
`Apps/Network/RouteReflector.yaml` in a temporary values file and pass it with
`-f`.

Inspect the generated FRR configuration before reconciliation:

```sh
helm template route-server Network/RouteServer \
  --namespace core-net-prod |
  yq 'select(.kind == "ConfigMap") | .data."frr.conf"'
```

After deployment, useful checks include:

```sh
kubectl -n core-net-prod get pods,svc,network-attachment-definitions
kubectl -n core-net-prod exec <route-server-pod> -c frr -- vtysh -c 'show running-config'
kubectl -n core-net-prod exec <route-server-pod> -c frr -- vtysh -c 'show bgp summary'
kubectl -n core-net-prod exec <route-server-pod> -c frr -- vtysh -c 'show ip ospf neighbor'
```

Enable `debugSidecar` only for a bounded diagnostic window. It shares every
Multus interface with FRR; grant extra capabilities through
`securityContext` only when a specific tool requires them.

## Change safety

Route-policy errors can leak, suppress, or blackhole prefixes. Before syncing:

1. Verify the ApplicationSet's selected clusters and merged values.
2. Check that interface ordering, device resources, VLANs, MTUs, addresses,
   routes, ASNs, router IDs, and BGP cluster IDs match the fabric.
3. Review every prefix-list and route-map default path, including the behavior
   when no entry matches.
4. Compare the rendered `frr.conf` with the current running configuration.
5. Record received and advertised routes, next hops, communities, local
   preference, MED, and prefix counts before and after the change.
6. Confirm data-plane reachability independently of neighbor establishment.

The chart uses a `Recreate` workload strategy, so configuration changes can
interrupt a route server. Roll out redundant route servers one at a time and
retain console or out-of-band access to the surrounding network.
