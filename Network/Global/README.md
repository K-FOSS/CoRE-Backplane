# CoRE-Backplane Network/Global Stack

This chart starts the k8gb global load-balancing control plane in the two
registered production infrastructure clusters. The owning
[`Apps/Network/Global.yaml`](../../Apps/Network/Global.yaml) ApplicationSet
injects the unique `home1` and `dc1` geotags and selects only registered CoRE
bare-metal infrastructure clusters. Argo CD renders the pinned
[k8gb chart v1.0.0](https://github.com/k8gb-io/k8gb/tree/v1.0.0/chart/k8gb),
which installs the controller, its CRDs, and its local CoreDNS component in
the `k8gb` namespace. The chart owns that namespace and creates it at sync wave
`-2` so namespaced RBAC resources have a namespace before they reconcile.

## Current deployment scope

This is the control-plane foundation. The chart creates the current `k8gb.io`
CRDs, disables installation of the legacy `k8gb.absa.oss` CRDs, and enables
Gateway API integration. It sets the distinct per-site `clusterGeoTag` and
`extGslbClustersGeoTags` values. Public DNS exposure is owned separately by
the [Network/DNS stack](../DNS/README.md).

The first static k8gb zone is `gslb.mylogin.space`, delegated beneath the
`mylogin.space` parent zone. No `ZoneDelegation` or `Gslb` resources are
created yet, and the embedded ExternalDNS remains disabled. K8GB CoreDNS
remains an internal `ClusterIP` backend; the separate Network/DNS stack may
route configured zones to it.

## DNS prerequisites before enabling a global service

Each participating k8gb CoreDNS server must have an externally reachable DNS
address for the parent zone's NS and glue records. YXL/DC1 retains the legacy
PowerDNS PureLB endpoint at `66.165.222.100`; the Network/DNS stack owns the
YVR endpoint through KubeVIP with UPnP forwarding. The actual YVR WAN target
must be verified from outside the site before publishing glue.

The operator-provided authoritative DNS topology is `ns1.resolvemy.host`
through `ns4.resolvemy.host`, with two names assigned to DC1 and two to YVR.
The underlying authoritative service is owned by the [Network/NS PowerDNS
chart](../NS/README.md), while its public port-53 exposure is owned by
[Network/DNS](../DNS/README.md).
That chart currently runs one PowerDNS workload pod per cluster, so the
two-per-site statement describes the assigned nameservers, not observed pod
replicas. The Network/NS ApplicationSet currently emits `ns4` to DC1 and `ns2`
to YVR; the records for the other names and their site assignments must be
verified in the authoritative zone. The live Home1/YVR endpoint must still be
checked externally, so existing nameserver records do not by themselves prove
that k8gb's CoreDNS endpoint can be reached publicly. Confirm each name's actual
A/AAAA target, its serving site's address, the parent zone's authoritative
owner, and external UDP/TCP port 53 reachability before creating delegation
or glue.

Use the existing PowerDNS ownership for `resolvemy.host`; do not configure the
Cloudflare provider to write that zone or create a competing DNS writer. k8gb
supports [RFC2136](https://www.k8gb.io/latest/provider_rfc2136/) through its
embedded ExternalDNS. The Network/NS PowerDNS configuration currently allows
RFC2136 updates from private network ranges; k8gb must not use anonymous
updates. First create and validate a narrowly scoped TSIG identity and its
secret distribution, or confirm an appropriately scoped PowerDNS API
integration. Limit ExternalDNS to the selected child/delegation zone and
verify TXT ownership behavior before enabling it. The existing Network/Base
Cloudflare ExternalDNS Secret is namespace-scoped and does not grant access to
the PowerDNS API.

When those prerequisites are ready, deploy a `ZoneDelegation` in each cluster
that serves the child zone and a matching `Gslb` referencing the same
Gateway/Service in each participating site. Dynamic zones let k8gb activate
CoreDNS only for zones that have participating workloads. Follow the
[ZoneDelegation guide](https://www.k8gb.io/latest/dynamic_zones/),
[Gslb strategies](https://www.k8gb.io/latest/strategy/),
[resource reference guide](https://www.k8gb.io/latest/resource_ref/), and
[upstream rollback procedure](https://www.k8gb.io/latest/rollback_procedures/).

## Reconciliation and verification

The ApplicationSet child Applications install the same pinned chart on each
selected cluster; their Helm dependencies are resolved by the Lovely renderer.
The k8gb controller manages its CRDs and local CoreDNS configuration. It does
not create cross-cluster workloads, load-balancer addresses, DNS credentials,
or parent-zone delegation in this initial configuration.

After reconciliation, verify both child Applications, K8GB and CoreDNS
readiness, CRD establishment, the site geotags, and that no
`ZoneDelegation` or `Gslb` resources exist. Once DNS prerequisites are met,
verify ZoneDelegation status, generated DNSEndpoints, Cloudflare/provider
records, authoritative UDP/TCP answers from outside each site, and the actual
application failover before treating a hostname as globally served.

Argo CD preserves resources if this ApplicationSet is removed. Removing k8gb
may leave CRDs, custom resources, DNS zones, and delegation records behind.
Before deletion, remove application `Gslb` and `ZoneDelegation` resources using
the [k8gb cleanup guidance](https://www.k8gb.io/latest/dynamic_zones/), inspect
finalizers and ExternalDNS TXT ownership, and deliberately remove CRDs only
after no k8gb objects remain.
