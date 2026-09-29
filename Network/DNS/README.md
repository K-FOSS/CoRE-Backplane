# CoRE-Backplane Network/DNS Stack

This stack deploys PowerDNS [dnsdist](https://www.dnsdist.org/) as the
site-local public DNS front door. The owning
[`Apps/Network/DNS.yaml`](../../Apps/Network/DNS.yaml) ApplicationSet injects
the site exposure and backend values. Authoritative PowerDNS remains owned by
the [Network/NS stack](../NS/README.md), K8GB CoreDNS remains owned by
[Network/Global](../Global/README.md), and cluster-recursive CoreDNS remains
owned by [Network/Base](../Base/README.md).

The dnsdist Deployment and Services are generated through the pinned
[BJW-S common library chart 5.0.1](https://github.com/bjw-s-labs/helm-charts/tree/common-5.0.1/charts/library/common).
The dnsdist ConfigMap remains a direct chart resource because its Lua routing
configuration is specific to this stack.

## Routing and exposure

The [official PowerDNS dnsdist image](https://hub.docker.com/r/powerdns/dnsdist-21)
is pinned to `2.1.1`, the latest verified Docker image tag. Its [downstream
health checks and server-pool model](https://www.dnsdist.org/guides/downstreams.html)
are rendered from [`values.yaml`](values.yaml) and
[`templates/DNSDistConfig.yaml`](templates/DNSDistConfig.yaml).

`resolvemy.host.` is sent to the local `ns-core` PowerDNS Service. K8GB zones
are sent to the K8GB CoreDNS Service when listed in
`dnsdist.k8gb.zones`. Recursive requests are sent to the cluster-domain-qualified
cluster DNS Service only for the CIDRs in `dnsdist.recursive.allowedNetworks`;
other public requests remain in the authoritative pool so the public endpoint
is not an open resolver.

YVR dnsdist is the public port-53 Service for the single-WAN site and uses
KubeVIP with UPnP forwarding. YXL/DC1 intentionally retains the legacy
PowerDNS NS Service through PureLB at `66.165.222.100` with service group
`anycast`; dnsdist is disabled there so the two Services cannot compete for
the address. The PowerDNS Service is changed to `ClusterIP` only for YVR by
[`Apps/Network/NS.yaml`](../../Apps/Network/NS.yaml).

## Verification and recovery

Render this chart with the target ApplicationSet values and verify the dnsdist
ConfigMap, backend names, Service annotations, and both UDP/TCP Service ports.
After reconciliation, verify dnsdist and K8GB readiness, the PowerDNS backend
Service type, external authoritative answers over UDP and TCP, and that a
public recursive query is refused or answered authoritatively rather than
recursively. Verify the YVR WAN target externally before publishing glue or
delegating a child zone.

To roll back the public front door, remove or disable this ApplicationSet only
after restoring an intentional public port-53 owner. The PowerDNS Service will
remain `ClusterIP` until its ApplicationSet is deliberately changed.
