# YVR VyOS NAT snapshot

This document records the supplied NAT snapshot for
`wan-gw2.home2.yvr.resolvemy.host`, running VyOS `2026.01.12-0023-rolling`,
observed October 16, 2026, in `America/Vancouver`. It describes this router
only; it does not establish that other YVR routers have the same configuration.
This is a documentation snapshot, not a router configuration change. It is
linked from the [Lab VMs documentation index](README.md), the
[NATPuncher stack overview](../../Network/NATPuncher/README.md), and the
[Network documentation index](../../Network/README.md).

The public destination is represented throughout this page by the canonical
repository reference
`<path:CORE0_SITE1/data/Network/Public/YVR#PublicHostname>`. This is
documentation indirection. It does not establish that VyOS matches a hostname,
resolves this reference dynamically, or updates its configuration when the
referenced value changes. No resolved public address is recorded here.

## Interfaces and address groups

| Interface or group | Members |
| --- | --- |
| WAN interface | `eth0` |
| LAN interface | `eth1` |
| WAN-MainGW | `10.0.0.19` |
| YVR public hostname | `<path:CORE0_SITE1/data/Network/Public/YVR#PublicHostname>` |
| CoRE-MainGW | `10.1.1.84` |
| CoRE-Unifi | `10.44.5.44` |
| CoTURN cluster IP | `10.44.6.44` |
| RTPEngine target | `10.44.4.82` |
| PNets | `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16` |
| INT-NONAT | `10.0.0.0/24`, `172.31.99.0/25`, `10.1.20.21/32` |
| CoRE-MainGW-TCP | TCP ports `80`, `443`, `8443`, `5061` |
| CoRE-MainGW-UDP | UDP ports `443`, `8443` |
| Unifi-Controller | TCP port `8080` |

## Destination NAT

| Rule | Destination match | Protocol / ports | Additional condition | Translate destination to |
| ---: | --- | --- | --- | --- |
| 3 | WAN-MainGW | TCP/UDP `3478`, `5349` | None | `10.44.6.44` |
| 4 | WAN-MainGW | UDP `15000–15049` | None | `10.44.6.44` |
| 5 | WAN-MainGW | `tcp_udp` `11000–11279` | None | `10.44.4.82` |
| 6 | WAN-Public | `tcp_udp` `11000–11279` | None | `10.44.4.82` |
| 10 | WAN-MainGW | TCP `80`, `443`, `8443`, `5061` | Incoming interface `WAN` | `10.1.1.84` |
| 20 | WAN-MainGW | UDP `443`, `8443` | Incoming interface `WAN` | `10.1.1.84` |
| 30 | `10.0.0.19` | TCP `80`, `443`, `8443`, `5061` | Source PNets | `10.1.1.84` |
| 40 | `10.0.0.19` | UDP `443`, `8443` | Source PNets | `10.1.1.84` |
| 53 | `<path:CORE0_SITE1/data/Network/Public/YVR#PublicHostname>` | TCP/UDP `53` | None | `10.44.6.11` |
| 443 | `<path:CORE0_SITE1/data/Network/Public/YVR#PublicHostname>` | TCP `80`, `443`, `8443`, `5061` | None | `10.1.1.84` |
| 444 | `<path:CORE0_SITE1/data/Network/Public/YVR#PublicHostname>` | UDP `443`, `8443` | None | `10.1.1.84` |
| 1001 | `<path:CORE0_SITE1/data/Network/Public/YVR#PublicHostname>` | TCP `8080` | None | `10.44.5.44` |

All listed DNAT mappings preserve the destination port. “None” means that no
additional source or incoming-interface condition is configured. Rules with
no incoming-interface condition can match traffic arriving internally as well
as traffic arriving from WAN. Internal clients can use the public-destination
DNAT mappings; rules 30 and 40 additionally map PNets clients connecting to
`10.0.0.19` to CoRE-MainGW.

Rules 3 and 4 are the current CoTURN destination mappings. They match
`WAN-MainGW`; this snapshot does not show a CoTURN destination rule matching
`WAN-Public`. Rule 4 is UDP only. Rules 5 and 6 are the separate RTPEngine
destination mappings and use VyOS's configured `tcp_udp` protocol for the
`11000–11279` range. None of rules 3–6 specifies an inbound interface.

## Source NAT

| Rule | Source match | Destination match | Protocol / ports | Outgoing interface | Action |
| ---: | --- | --- | --- | --- | --- |
| 10 | `10.0.0.0/24` | Any | Any | WAN | Exclude from SNAT |
| 53 | PNets | `10.44.6.11` | TCP/UDP `53` | Any | SNAT to `10.1.20.21` |
| 54 | PNets | `10.44.4.82` | TCP/UDP `11000–11279` | Any | SNAT to `10.1.20.21` |
| 55 | PNets | `10.44.6.44` | TCP/UDP `3478`, `5349`, `15000–15049` | Any | SNAT to `10.1.20.21` |
| 99 | PNets | Any | Any | WAN | SNAT to `10.0.0.12` |
| 441 | INT-NONAT | CoRE-MainGW | UDP `443`, `8443` | Any | Exclude from SNAT |
| 442 | INT-NONAT | CoRE-MainGW | TCP `80`, `443`, `8443`, `5061` | Any | Exclude from SNAT |
| 443 | PNets | CoRE-MainGW | TCP `80`, `443`, `8443`, `5061` | Any | SNAT to `10.1.20.21` |
| 444 | PNets | CoRE-MainGW | UDP `443`, `8443` | Any | SNAT to `10.1.20.21` |
| 1001 | Any | CoRE-Unifi | TCP `8080` | Any | SNAT to `10.1.20.21` |

Source rules 54 and 55 are source NAT, not port forwards. They change the
source address of matching LAN clients to `10.1.20.21`; destination NAT is the
separate operation that changes a service destination to a cluster target.
For CoTURN, rule 55 hides each matching LAN client's original source address
and gives the return traffic a routed path back through VyOS.

The route output places `10.1.20.21` in the LAN VRF on both `dum10` and
`dum1002`. It also shows the cluster service range `10.44.4.0/22` as routed;
the CoTURN cluster IP `10.44.6.44` is within that range. The RTPEngine target
`10.44.4.82` is in the same routed cluster range.

## Evaluation and resulting behavior

NAT rules are evaluated in numerical order within each chain; an earlier
matching rule takes precedence over later matches. Source NAT evaluates its
destination after DNAT has translated it. The rule numbers in the DNAT and
source NAT tables are independent chains.

Source rule 99 is earlier than the MainGW exclusions and SNAT rules 441–444.
For a PNets connection leaving `eth0` that has not matched an earlier source
rule, rule 99 applies before those later rules. The MainGW exclusions preserve
the original source for INT-NONAT only when the packet reaches rules 441 or
442. Other matching PNets clients use `10.1.20.21` under rules 443 or 444 when
those rules are reached.
Those service-specific rules also match direct connections to CoRE-MainGW;
prior DNAT is not required.

DNS source rule 53 translates matching PNets clients to `10.1.20.21` before
the general outbound rule is considered. UniFi source rule 1001 has no source
restriction, but only applies if no earlier source NAT rule matches.

Outbound PNets traffic leaving `eth0` normally uses `10.0.0.12`, except
`10.0.0.0/24`, which is excluded from SNAT by rule 10, and traffic matching
earlier service-specific rules. The exclusions and service-specific SNAT rules
do not override rule 99 for a matching PNets flow that has already matched
rule 99 while leaving WAN.

CoTURN uses cluster IP `10.44.6.44` for TCP and UDP `3478` and `5349`, plus
UDP relay ports `15000–15049`, through destination rules 3 and 4. Matching
PNets clients use source rule 55 and are translated to `10.1.20.21`, which
hides their original source and supports the routed return path through VyOS.
This snapshot does not show a CoTURN destination rule for `WAN-Public`; that
would be a separate possible configuration change.

RTPEngine is a separate service at `10.44.4.82`. Destination rules 5 and 6
map TCP and UDP ports `11000–11279` from WAN-MainGW and WAN-Public,
respectively. Matching PNets clients use source rule 54 and are translated to
`10.1.20.21`. These RTPEngine mappings must be kept distinct from the CoTURN
cluster target and port ranges.

The [NATPuncher overview](../../Network/NATPuncher/README.md#coturn-service-configuration)
describes Kubernetes Service and UPnP settings separately from this static
VyOS state. Those settings do not add or change the destination rules recorded
here.

NAT configuration alone does not prove firewall permission, routing
reachability, upstream forwarding, or service availability. Any subsequent
upstream translation to a public address is outside this snapshot and is not
verified here.

For the meaning and processing model of VyOS NAT rules, see the official
[VyOS rolling NAT44 documentation](https://docs.vyos.io/en/rolling/configuration/nat/nat44.html).
The link describes current rolling documentation and is not evidence that
every behavior or command is identical in the captured build.

## Packet-flow examples

These examples assume the destination match represented by the canonical
reference above matches as supplied in the snapshot. The reference itself
does not imply that VyOS performs hostname lookup. Routing assumptions are
stated per example, and these NAT outcomes do not prove forwarding or service
availability.

1. **PNets client outside INT-NONAT to public destination on TCP 443:**
   accessing `<path:CORE0_SITE1/data/Network/Public/YVR#PublicHostname>` on
   TCP `443` changes the destination to `10.1.1.84:443`. Assuming the
   translated route does not leave WAN, source rule 443 changes the source to
   `10.1.20.21`.
2. **INT-NONAT client to the same service:** accessing
   `<path:CORE0_SITE1/data/Network/Public/YVR#PublicHostname>` on TCP `443`
   changes the destination to `10.1.1.84:443`. Assuming the translated route
   does not leave WAN, source is preserved when rule 442 is reached. A valid
   return route to the original client is required.
3. **PNets client to public DNS:** accessing
   `<path:CORE0_SITE1/data/Network/Public/YVR#PublicHostname>` on TCP or UDP
   port `53` changes the destination to `10.44.6.11:53`; source rule 53
   changes the source to `10.1.20.21`.
4. **PNets client outside `10.0.0.0/24` to an ordinary Internet destination
   through `eth0`:** assuming no earlier source NAT rule matches, rule 99
   changes the source to `10.0.0.12`.
5. **`10.0.0.0/24` client to an Internet destination through `eth0`:** source
   rule 10 excludes it from SNAT on this router. This does not establish
   whether another device later translates the source.
