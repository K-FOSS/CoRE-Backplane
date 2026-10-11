# CoRE-Backplane Network/DNS Stack

This stack deploys PowerDNS [dnsdist](https://www.dnsdist.org/) as the
site-local public DNS front door. The owning
[`Apps/Network/DNS.yaml`](../../Apps/Network/DNS.yaml) ApplicationSet injects
the site exposure and backend values. Authoritative PowerDNS remains owned by
the [Network/NS stack](../NS/README.md), K8GB CoreDNS remains owned by
[Network/Global](../Global/README.md), and cluster service discovery remains
owned by [Network/Base](../Base/README.md). A separate PowerDNS Recursor
Deployment provides site-local general recursion for explicitly allowed LANs.

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
names with `getAddressInfo()` before registering IP backends. The
authoritative backend uses Network/NS's headless `ns-core-discovery` Service,
which returns the ready PowerDNS Pod addresses. dnsdist health-checks each Pod
with an SOA query for `resolvemy.host.` and uses round-robin selection across
the healthy replicas using dnsdist's
[round-robin server policy](https://www.dnsdist.org/guides/serverselection.html).
This avoids probing the public nameserver LoadBalancer
IP or hiding an unhealthy replica behind one ClusterIP. dnsdist refreshes the
headless Service addresses every 30 seconds and adds or removes individual
backends as NS Pods become ready or are replaced. The recursive pool discovers
the ready PowerDNS Recursor Pod addresses through its own IPv4 headless
Service, health-checks each with an SOA query for `.`, and round-robins across
healthy replicas. DNSDist uses that pool only for the site LAN CIDRs injected
by the ApplicationSet: `10.0.0.0/24` in YVR and `172.16.51.0/24` in YXL/DC1.
Queries outside those networks and the configured authoritative zones fall
through to the authoritative pool, so the public listener does not provide
open recursion.

The Recursor runs as a separate three-replica Deployment at both sites. It
performs full iterative resolution, validates DNSSEC, and accepts inbound DNS
only from private addresses. A NetworkPolicy further restricts ingress to
DNSDist Pods and egress to upstream DNS over UDP/TCP port 53. Incoming TCP is
limited to 128 concurrent clients, eight per client, and 100 queries per
connection. It uses `SO_REUSEPORT`, a 256-entry TCP Fast Open queue, and TCP
Fast Open for outbound authoritative connections. Pod TCP buffers are tuned
with namespaced sysctls; the Talos node configuration enables
`net.ipv4.tcp_fastopen=3` and the corresponding node TCP buffer limits.

The Recursor has a 100,000-entry record cache and 50,000-entry packet cache.
It refreshes records asynchronously when they reach 10% of their original TTL
and can serve expired records for up to one hour when an upstream refresh
fails, following PowerDNS's
[Serve Stale behavior](https://doc.powerdns.com/recursor/appendices/internals.html#serve-stale).
The full DNSSEC validation mode and the TCP, socket, and cache limits are
configured through the Recursor's
[YAML settings](https://doc.powerdns.com/recursor/yamlsettings.html).

YVR enables an additional
[`postresolve` Lua hook](https://docs.powerdns.com/recursor/lua-scripting/hooks.html)
and [DNS record editing API](https://docs.powerdns.com/recursor/lua-scripting/dnsrecord.html)
to inspect completed answers. If an A response contains a CNAME to the
Vault-backed YVR `PublicHostname` injected as `dnsdist.cnameFilter.target`, it
removes the returned CNAME chain and terminal records, then returns one A
record for the original queried name at `dnsdist.cnameFilter.address`
(`10.0.0.19`). This covers any alias whose CNAME points at the Vault-provided
hostname, including aliases whose names are not known to the ApplicationSet.
Other query types and unrelated CNAMEs are returned unchanged. The
`dnsdistHostOverrides` entries still handle direct queries for
`idp.mylogin.space.` and the Vault-backed YVR public hostname.

DNSSEC signatures for rewritten responses are removed with the original chain,
so those synthesized A answers are unsigned. YXL/DC1 runs the same Recursor
configuration without this rewrite.

The dnsdist pod sets resolver `ndots: '0'` through its BJW-S pod DNS
configuration so fully qualified internal Service names are resolved directly.
The pod also runs a same-image configuration watcher. Kubernetes projects
updates to the mounted ConfigMap directory; the watcher publishes a hash marker
and dnsdist's one-second `maintenance()` hook detects it, reloads `rules.lua`,
and replaces the routing rules in place. Listening sockets and the dnsdist
process remain open, so routing-rule changes do not restart the process or roll
out the Pod. Changes to `dnsdist.conf`, including the downstream backend
addresses and health checks, require updating `dnsdist.configRevision` to roll
the Deployment and load the new configuration. The Network/NS headless Service
change advances that revision so dnsdist starts with all ready PowerDNS Pods;
the periodic resolver keeps that set current as Pods change.

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

Render this chart with the target ApplicationSet values and verify the DNS
ConfigMap, both Deployments and their replicas, the Recursor NetworkPolicy,
headless backend names, Service annotations, and UDP/TCP ports.
The Service targets the container ports by the matching `dns-udp` and `dns-tcp`
names; verify both names are present on the rendered dnsdist container.
After reconciliation, verify dnsdist and K8GB readiness, the PowerDNS backend
Service type, external authoritative answers over UDP and TCP, and that a
public recursive query is refused or answered authoritatively rather than
recursively. Verify the YVR WAN target externally before publishing glue or
delegating a child zone.

When changing the generated DNS configuration, verify the ConfigMap data,
the watcher marker, both ready endpoints, and the affected answers. The watcher
only publishes the file hash; dnsdist performs the rule replacement and does
not expose a remote control socket. See the [dnsdist configuration and runtime guidance](https://www.dnsdist.org/running.html)
and [PowerDNS dnsdist container documentation](https://github.com/PowerDNS/pdns/tree/master/dockerdata),
the [PowerDNS Recursor 5.4 image](https://hub.docker.com/r/powerdns/pdns-recursor-54),
[Recursor YAML settings](https://doc.powerdns.com/recursor/yamlsettings.html),
[DNSSEC validation](https://doc.powerdns.com/recursor/dnssec.html),
[performance and TCP Fast Open](https://doc.powerdns.com/recursor/performance.html#tcp-fast-open-support),
and [Kubernetes Pod sysctls](https://kubernetes.io/docs/tasks/administer-cluster/sysctl-cluster/).

To roll back the public front door, remove or disable this ApplicationSet only
after restoring an intentional public port-53 owner. The PowerDNS Service will
remain `ClusterIP` until its ApplicationSet is deliberately changed.
