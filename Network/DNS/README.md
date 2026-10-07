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

`resolvemy.host.` and `mylogin.social.` are sent to the local `ns-core`
PowerDNS Service. The more specific `gslb.mylogin.space` and
`gslb.mylogin.social` zones are sent to the cluster-specific K8GB CoreDNS
Service derived from `cluster.name` and `environment` when listed in
`dnsdist.k8gb.zones`. The GSLB suffix rules precede the parent-zone
authoritative rules so `gslb.mylogin.social` reaches K8GB. Backend Service
names use
`cluster.kubernetesDomain` (the active CoreDNS configuration may use
`k8s.<site>.resolvemy.host` alongside `cluster.local`), while `cluster.domain`
remains the external/site cluster identity. dnsdist resolves those Service
names with `getAddressInfo()` before registering IP backends. Recursive
requests are sent to the cluster-domain-qualified cluster DNS Service only for
the CIDRs in `dnsdist.recursive.allowedNetworks`; other public requests remain
in the authoritative pool so the public endpoint is not an open resolver. The
YVR ApplicationSet routes `10.0.0.0/24` to the `forwarder` pool before the
authoritative, K8GB, and recursive rules. That pool contains only Cloudflare's
`1.1.1.1:53` backend, so matching queries are forwarded to Cloudflare. Other
private networks retain the cluster-recursive rule.

YVR defines exact-name overrides through `dnsdistHostOverrides` in the
ApplicationSet list entry. Both `idp.mylogin.space.` and the Vault-backed YVR
public hostname return `10.0.0.19` for A queries. The direct `idp.mylogin.space.`
rule is needed because Cloudflare resolves the CNAME chain as part of the
upstream response; overriding only the CNAME target cannot change that answer.
dnsdist's
[`QNameRule`](https://www.dnsdist.org/reference/selectors.html) and
[`SpoofAction`](https://www.dnsdist.org/reference/actions.html) answer matching
A queries locally. This override precedes all forwarding and zone rules. Add
further addresses to the entry's `addresses` list to spoof additional A or
AAAA records.

The dnsdist pod sets resolver `ndots: '0'` through its BJW-S pod DNS
configuration so fully qualified internal Service names are resolved directly.
The pod also runs a same-image configuration watcher. Kubernetes projects
updates to the mounted ConfigMap directory; the watcher publishes a hash marker
and dnsdist's one-second `maintenance()` hook detects it, reloads `rules.lua`,
and replaces the routing rules in place. Listening sockets and the dnsdist
process remain open, so configuration-only changes do not restart the process
or roll out the Pod.

YVR dnsdist is the public port-53 Service for the single-WAN site and uses
KubeVIP with the static `kube-vip.io/loadbalancerIPs: '10.0.0.40'` Service
annotation. The annotation requests the reserved VIP from the
[KubeVIP cloud provider](https://kube-vip.io/docs/usage/cloud-provider/);
KubeVIP advertises it without requesting a UPnP mapping for dnsdist.
The separate [NATPuncher stack](../NATPuncher/README.md) owns the YVR gateway's
port-53 mappings. YXL/DC1 retains the legacy PowerDNS NS Service through
PureLB at `66.165.222.100` with service group `anycast` and runs dnsdist at
`66.165.222.105`; the Services have distinct addresses. The PowerDNS Service
is changed to `ClusterIP` only for YVR by
[`Apps/Network/NS.yaml`](../../Apps/Network/NS.yaml).

## Verification and recovery

Render this chart with the target ApplicationSet values and verify the dnsdist
ConfigMap, backend names, Service annotations, and both UDP/TCP Service ports.
The Service targets the container ports by the matching `dns-udp` and `dns-tcp`
names; verify both names are present on the rendered dnsdist container.
After reconciliation, verify dnsdist and K8GB readiness, the PowerDNS backend
Service type, external authoritative answers over UDP and TCP, and that a
public recursive query is refused or answered authoritatively rather than
recursively. Verify the YVR WAN target externally before publishing glue or
delegating a child zone.

When changing the generated dnsdist configuration, verify the ConfigMap data,
the watcher marker, both ready endpoints, and the affected answers. The watcher
only publishes the file hash; dnsdist performs the rule replacement and does
not expose a remote control socket. See the [dnsdist configuration and runtime guidance](https://www.dnsdist.org/running.html)
and [PowerDNS dnsdist container documentation](https://github.com/PowerDNS/pdns/tree/master/dockerdata)
for the upstream behavior this arrangement relies on.

To roll back the public front door, remove or disable this ApplicationSet only
after restoring an intentional public port-53 owner. The PowerDNS Service will
remain `ClusterIP` until its ApplicationSet is deliberately changed.
