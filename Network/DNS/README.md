# CoRE-Backplane Network/DNS Stack

This stack deploys PowerDNS [dnsdist](https://www.dnsdist.org/) as the
site-local public DNS front door. The owning
[`Apps/Network/DNS.yaml`](../../Apps/Network/DNS.yaml) ApplicationSet injects
the site exposure and backend values. Authoritative PowerDNS remains owned by
the [Network/NS stack](../NS/README.md), K8GB CoreDNS remains owned by
[Network/Global](../Global/README.md), and cluster service discovery remains
owned by [Network/Base](../Base/README.md). A separate PowerDNS Recursor
Deployment provides site-local general recursion for explicitly allowed LANs.

The dnsdist Deployment, Services, ConfigMap, and ServiceMonitors are generated
through the pinned [BJW-S common library chart
5.0.1](https://github.com/bjw-s-labs/helm-charts/tree/common-5.0.1/charts/library/common).
The ConfigMap source remains in [`templates/DNSDistConfig.yaml`](templates/DNSDistConfig.yaml)
and is parsed into the common chart values; BJW-S includes its checksum on the
Recursor controller so changes to its Lua script roll the Recursor pods.
ServiceMonitor resources use the common chart's native `serviceMonitor`
configuration.

## Routing and exposure

The [official PowerDNS dnsdist image](https://hub.docker.com/r/powerdns/dnsdist-21)
is pinned to `2.1.3` by multi-platform image digest. Its [downstream
health checks and server-pool model](https://www.dnsdist.org/guides/downstreams.html)
are rendered from [`values.yaml`](values.yaml) and
[`templates/DNSDistConfig.yaml`](templates/DNSDistConfig.yaml).

`syncmy.date.` and `mylogin.social.` are sent to the local `ns-core`
PowerDNS Service. `resolvemy.host.` is deliberately omitted from the local
authoritative suffix list; queries from the site LANs use the Recursor and can
follow delegations to private authoritative servers. The more specific
`gslb.mylogin.space` and `gslb.mylogin.social` zones are sent to the
cluster-specific K8GB CoreDNS Service derived from `cluster.name` and
`environment` when listed in
`dnsdist.k8gb.zones`. The GSLB suffix rules precede the parent-zone
authoritative rules so `gslb.mylogin.social` reaches K8GB. Backend Service
names use
`cluster.kubernetesDomain` (the active CoreDNS configuration may use
`k8s.<site>.resolvemy.host` alongside `cluster.local`), while `cluster.domain`
remains the external/site cluster identity. dnsdist resolves those Service
names with `getAddressInfo()` before registering IP backends. The
authoritative backend uses Network/NS's headless `ns-core-discovery` Service,
which returns the ready PowerDNS Pod addresses. dnsdist health-checks each Pod
with an SOA query for `mylogin.social.` and uses round-robin selection across
the healthy replicas using dnsdist's
[round-robin server policy](https://www.dnsdist.org/guides/serverselection.html).
This avoids probing the public nameserver LoadBalancer
IP or hiding an unhealthy replica behind one ClusterIP. dnsdist refreshes the
headless Service addresses every 30 seconds and adds or removes individual
backends as NS Pods become ready or are replaced. The recursive pool discovers
the ready PowerDNS Recursor Pod addresses through its own IPv4 headless
Service, health-checks each with an SOA query for `.`, and round-robins across
healthy replicas. DNSDist uses that pool only for the site LAN CIDRs injected
by the ApplicationSet:
`10.0.0.0/24` in YVR and `172.16.51.0/24` in YXL/DC1. The YVR
`10.0.0.19` answer rewrite runs in the Recursor, so it applies only to queries
that dnsdist routes to that pool from the `10.0.0.0/24` client network. Queries
from other source networks and queries outside the configured authoritative
zones fall through to the authoritative pool, so the public listener does not
provide open recursion. The Recursor sees dnsdist as its network peer; dnsdist's
source-network routing rule is therefore the enforcement point for this
restriction.

## Home1 DNSDist placement

The Home1 ApplicationSet requests four DNSDist frontend replicas, matching the
observed deployment and allowing one pod on each preferred node. The pods are
restricted to `hpc2`, `laptop2`, `srv2`, `srv3`, and `hpc3`. Kubernetes node
affinity gives `hpc2` and `laptop2` the
highest preference, `srv2` and `srv3` the next preference, and `hpc3` the
lowest preference. A hostname topology-spread constraint keeps the pod count
balanced across eligible nodes. DNSDist tolerates the `load=testing:NoSchedule`
taint on `hpc2` to make that preferred node schedulable for this workload.
These affinity weights are scheduler preferences, so resource fit and node
availability can affect the final placement; inspect pod placement after a
rollout. See Kubernetes' [node affinity
documentation](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/)
and [topology spread constraints](https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/).
DC1 does not receive these Home1-specific scheduling settings through the
owning [DNS ApplicationSet](../../Apps/Network/DNS.yaml).

The Recursor runs as a separate three-replica Deployment at both sites. It
performs full iterative resolution, validates DNSSEC, and accepts inbound DNS
only from private addresses. A NetworkPolicy further restricts ingress to
DNSDist Pods and egress to upstream DNS over UDP/TCP port 53. Incoming TCP is
limited to 128 concurrent clients, eight per client, and 100 queries per
connection. It uses `SO_REUSEPORT`; TCP Fast Open is disabled because the
runtime sysctl does not permit it. Pod TCP buffers are tuned with namespaced
sysctls, while Talos sets the corresponding node TCP buffer limits.

The Recursor has a 100,000-entry record cache and 50,000-entry packet cache.
It refreshes records asynchronously when they reach 10% of their original TTL
and can serve expired records for up to one hour when an upstream refresh
fails, following PowerDNS's
[Serve Stale behavior](https://doc.powerdns.com/recursor/appendices/internals.html#serve-stale).
The full DNSSEC validation mode and the TCP, socket, and cache limits are
configured through the Recursor's
[YAML settings](https://doc.powerdns.com/recursor/yamlsettings.html).

## Prometheus metrics

The chart enables the native PowerDNS metrics endpoints rather than adding a
duplicate exporter container. dnsdist exposes `/metrics` on its internal
`dnsdist-metrics` Service, and the Recursor exposes `/metrics` on the
`recursor-discovery` Service's metrics port. Both are scraped by ServiceMonitors
every 30 seconds; the metrics webservers are bound to internal addresses and
allow only private network ranges. See the [dnsdist Prometheus endpoint
documentation](https://www.dnsdist.org/guides/webserver.html), the [Recursor
Prometheus endpoint](https://doc.powerdns.com/recursor/http-api/prometheus.html),
and the [Grafana dnsdist dashboard](https://grafana.com/grafana/dashboards/20422-dnsdist/).
The dashboard ConfigMap is owned by this stack and imported by the shared
[Grafana dashboard syncer](../../Observability/Dashboards/README.md).

The Recursor permits outgoing DNS queries to RFC 1918 and IPv6 ULA addresses so
delegations for domains with private authoritative nameservers can resolve. Its
`outgoing.dont_query` list continues to block loopback, link-local, and
documentation/reserved address ranges. This exception applies to recursive
lookups generally, because the Recursor cannot identify which private
nameservers belong to locally owned domains before following a delegation.
Incoming recursion remains limited to the site LAN networks through dnsdist
and the Recursor ACL. See PowerDNS's [`dont-query` setting](https://doc.powerdns.com/recursor/settings.html#dont-query)
for the destination filtering behavior.

YVR enables an additional
[`postresolve` Lua hook](https://docs.powerdns.com/recursor/lua-scripting/hooks.html)
and [DNS record editing API](https://docs.powerdns.com/recursor/lua-scripting/dnsrecord.html)
to inspect completed answers. It rewrites A answers when either a CNAME points
to the Vault-backed YVR `PublicHostname` injected as
`dnsdist.cnameFilter.target`, or the answer chain contains a CNAME under
`gslb.mylogin.space` and an A record. It removes the returned CNAME chain and
terminal records, then returns one A record for the original queried name at
`dnsdist.cnameFilter.address` (`10.0.0.19`). This covers aliases whose names
are not known to the ApplicationSet. The Recursor hook does not perform its own
hostname lookup; it relies on the K8GB CNAME chain to scope GSLB rewrites.
Other query types and unrelated CNAMEs are returned unchanged. The
`dnsdistHostOverrides` entries still handle direct queries for
`idp.mylogin.space.` and the Vault-backed YVR public hostname.

DNSSEC signatures for rewritten responses are removed with the original chain,
so those synthesized A answers are unsigned. YXL/DC1 runs the same Recursor
configuration without this rewrite.

The dnsdist pod sets resolver `ndots: '0'` through its BJW-S pod DNS
configuration so fully qualified internal Service names are resolved directly.
Both dnsdist and the Recursor pods carry the targeted
`configmap.reloader.stakater.com/reload: 'dnsdist-config'` annotation.
[Stakater Reloader](https://docs.stakater.com/reloader/latest/reference/annotations.html)
restarts the appropriate workload when this common-chart-generated ConfigMap
changes. This reloads dnsdist's listener and backend configuration safely at
process startup and ensures the Recursor loads an updated Lua filter script.

dnsdist periodically resolves the headless Network/NS and Recursor Services
and updates its per-Pod backend list without requiring a ConfigMap change.

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

Both target clusters also expose the same internal `core-dns` LoadBalancer
Service on UDP and TCP port 53 at `10.1.1.53`. PureLB allocates it from the
site-local anycast pool: `core-anycast` in Home1 and `anycast` in DC1. Those
`/32` pools are declared in the respective [cluster definitions](../../Operations/Clusters/templates/prod/).
The service selects the same dnsdist pods as the site-facing `dnsdist`
Service, so authoritative, K8GB, and recursive query routing remain shared.
The `10.1.1.0/24` client network is included in dnsdist's recursive routing
allowlist; the Recursor itself already permits this private range. PureLB's
[ServiceGroup pool configuration](https://purelb.io/docs/configuration/service-groups/)
and [Service address annotations](https://purelb.io/docs/operations/services/)
document the allocation and requested-address behavior. The Service does not
publish a public DNS record.

## Verification and recovery

The two-replica dnsdist Deployment and three-replica Recursor Deployment use
rolling updates with one surge Pod and zero unavailable replicas. Their
startup probes allow up to five minutes for the DNS listeners to open, and
readiness checks require TCP connections to succeed before a Pod is included
as a Service endpoint. PodDisruptionBudgets keep at least one dnsdist and two
Recursor Pods available during voluntary disruptions. This
allows a rollout to pause safely when the cluster cannot schedule the surge
Pod, rather than removing a serving replica to make room. The readiness checks
confirm listener startup; dnsdist's downstream health checks independently
remove failed authoritative and recursive backends from query selection.
Newly discovered backends remain eligible during a configurable 20-second
warmup, relying on Kubernetes readiness while their processes finish
initializing. dnsdist then starts active SOA checks at one-second intervals;
two consecutive failures mark a backend down and two consecutive successes
are required for recovery. These settings are in `dnsdist.healthCheck*` in
[`values.yaml`](values.yaml) and apply to authoritative, recursive, and K8GB
backends. This uses dnsdist's documented
[`healthCheckMode` and `setActiveAuto()` behavior](https://www.dnsdist.org/guides/downstreams.html).

Render this chart with the target ApplicationSet values and verify the DNS
ConfigMap, both Deployments and their replicas, the Recursor NetworkPolicy,
headless backend names, both LoadBalancer Services, PureLB annotations, and
UDP/TCP ports. After reconciliation, verify `core-dns` receives
`10.1.1.53` in each cluster and that it resolves a cluster Service name, a
configured authoritative name, a GSLB name, and an external recursive name
over UDP and TCP. Both DNS Services target the container ports by the matching
`dns-udp` and `dns-tcp` names; verify both names are present on the rendered
dnsdist container.
After reconciliation, verify dnsdist and K8GB readiness, the PowerDNS backend
Service type, external authoritative answers over UDP and TCP, and that a
public recursive query is refused or answered authoritatively rather than
recursively. Verify the YVR WAN target externally before publishing glue or
delegating a child zone.

When changing the generated DNS configuration, verify the ConfigMap data,
Stakater Reloader's rollout, both ready endpoints, and the affected answers.
dnsdist does not expose a remote control socket. See the [dnsdist configuration and runtime guidance](https://www.dnsdist.org/running.html)
and [PowerDNS dnsdist container documentation](https://github.com/PowerDNS/pdns/tree/master/dockerdata),
the [PowerDNS Recursor 5.4.9 image](https://hub.docker.com/r/powerdns/pdns-recursor-54),
[PowerDNS Security Advisory 2026-12](https://doc.powerdns.com/recursor/security-advisories/powerdns-advisory-2026-12.html),
[Recursor YAML settings](https://doc.powerdns.com/recursor/yamlsettings.html),
[DNSSEC validation](https://doc.powerdns.com/recursor/dnssec.html),
[performance and TCP Fast Open](https://doc.powerdns.com/recursor/performance.html#tcp-fast-open-support),
and [Kubernetes Pod sysctls](https://kubernetes.io/docs/tasks/administer-cluster/sysctl-cluster/).

To roll back the public front door, remove or disable this ApplicationSet only
after restoring an intentional public port-53 owner. The PowerDNS Service will
remain `ClusterIP` until its ApplicationSet is deliberately changed.
