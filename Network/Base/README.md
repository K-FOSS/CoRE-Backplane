# Network Base

This rendering unit installs the foundational networking services used by CoRE
bare-metal infrastructure clusters. It is live, site-specific desired state;
changes can affect pod networking, DNS, ingress, BGP, load balancers, and direct
device access on every selected cluster.

## Ownership and target selection

[`Apps/Network/Base.yaml`](../../Apps/Network/Base.yaml) owns this directory.
Its `ApplicationSet` selects Argo CD cluster secrets with these labels:

- `mylogin.space/tenant=core.mylogin.space`
- `resolvemy.host/computetype=baremetal`
- `resolvemy.host/nodetype=infra`

The merge generator currently supplies site networking values for
`core-dc1-talos-prod` and `core-home1-talos-prod`. A cluster must also match the
cluster-secret selector and its name must match a list-generator element.
Resources are deployed to `kube-system`. Argo CD uses server-side apply and
preserves resources when a generated Application is deleted.

## Rendering and reconciliation

The `argocd-lovely-plugin` renders the local Helm chart and Kustomize unit, then
merges two ApplicationSet-provided layers:

1. `LOVELY_HELM_MERGE` injects cluster and site settings: cluster name and ID,
   cluster-mesh peers, NodePort address range, cluster domain, tenant, and the
   ExternalDNS owner ID.
2. `LOVELY_KUSTOMIZE_MERGE` patches the Multus DaemonSet and generated FRR-K8s
   startup ConfigMap.

Argo CD applies the result, after which each controller reconciles its own
resources. Argo CD `Healthy` or `Synced` does not establish that datapaths, BGP
sessions, DNS publication, gateways, load balancers, or SR-IOV allocations work.

## Components and current behavior

| Component | Source and behavior |
| --- | --- |
| [Cilium](https://docs.cilium.io/en/stable/) | Helm dependency providing the primary CNI, cluster mesh, BGP control plane, and local `CiliumEgressGatewayPolicy`. See [BGP resources](https://docs.cilium.io/en/stable/network/bgp-control-plane/bgp-control-plane-configuration/) and [egress gateway](https://docs.cilium.io/en/stable/network/egress-gateway/egress-gateway/). |
| [Multus CNI](https://github.com/k8snetworkplumbingwg/multus-cni) | Remote Kustomize resource installing thick Multus and the NetworkAttachmentDefinition CRD. The ApplicationSet patches its images, resources, and host network-namespace path. |
| [Multus dynamic networks controller](https://github.com/k8snetworkplumbingwg/multus-dynamic-networks-controller) | Remote Kustomize resource installing the per-node dynamic attachment controller. |
| [SR-IOV CNI](https://github.com/k8snetworkplumbingwg/sriov-cni) | Remote Kustomize resource installing the SR-IOV CNI binary on nodes. |
| [SR-IOV network device plugin](https://github.com/k8snetworkplumbingwg/sriov-network-device-plugin) | Remote Kustomize resource plus Helm-rendered `sriovdp-config`. The owning ApplicationSet supplies its resource pools through `sriovDevicePlugin.resourceList`. The patch in `kustomization.yaml` sets the `kube-sriovdp` CPU request to `16m`; memory and limits retain upstream values. |
| [SR-IOV Network Operator](https://github.com/k8snetworkplumbingwg/sriov-network-operator) | Optional Helm dependency. It is disabled in `values.yaml`; the standalone SR-IOV CNI and device plugin remain enabled independently. |
| [ExternalDNS](https://kubernetes-sigs.github.io/external-dns/latest/) with [Cloudflare](https://kubernetes-sigs.github.io/external-dns/latest/docs/tutorials/cloudflare/) | Enabled Helm dependency publishing public records selected by `wan-mode=public`. Credentials come from the referenced Kubernetes Secret and must not be committed here. |
| [PureLB](https://purelb.gitlab.io/purelb/) | Enabled Helm dependency using the Cilium announcer and `purelb.io/purelb` load-balancer class. |
| [Envoy Gateway](https://gateway.envoyproxy.io/docs/) | Enabled OCI Helm dependency with two replicas and Backend and EnvoyPatchPolicy extension APIs. Follow its [Helm installation and upgrade guidance](https://gateway.envoyproxy.io/docs/install/install-helm/). |
| [FRR-K8s](https://github.com/metallb/frr-k8s) | Enabled Helm dependency. The ApplicationSet replaces its startup daemon configuration and permits incoming BGP connections. |

The remote Multus dynamic controller, SR-IOV CNI, and SR-IOV device-plugin
resources track moving branches. Some referenced images also use mutable tags.
These are existing supply-chain risks: inspect fetched manifests and image
references on every change, and pin both before treating a render as reproducible.

## Values and generated resources

The primary value groups are `cilium`, `sriov-network-operator`, `cf-dns`,
`sriovDevicePlugin`, `purelb`, `envoy-gw`, and `frr-k8s`. Site-specific values
belong in the owning ApplicationSet rather than as additional literals in this
directory.

`sriovDevicePlugin.resourceList` is required and must contain at least one
device-plugin resource-pool object. Its objects are passed to the upstream
`resourceList` configuration without reshaping, so supported fields include
`resourceName`, `resourcePrefix`, `deviceType`, and `selectors`. The chart default
is deliberately empty and fails rendering until the owning ApplicationSet or a
representative values file supplies the hardware-specific pools.

Each list-generator element owns its cluster's
`sriovDevicePluginResourceList`. The merge generator carries that typed list
into the shared Application template, which serializes it as
`sriovDevicePlugin.resourceList`. DC1 advertises Intel I350 port-specific VFIO
and netdevice pools plus Mellanox CX3 VFIO and kernel-driver pools. Home1
advertises its X540 VF ranges and I350 VFIO pool. Keep these inventories
separate: interface names and driver bindings are node-local contracts, not
portable cluster defaults.

Local templates generate:

- Cilium BGP peer and advertisement policy in `kube-system`.
- A Cilium egress policy routing `k8s-app=kube-dns` traffic to the listed public
  resolver CIDRs through host interface `eno1`.
- `kube-system/sriovdp-config` from `sriovDevicePlugin.resourceList`, including
  hardware-specific PCI vendor, device, driver, PF name, VF range, resource
  name, and resource-prefix selectors.

SR-IOV selectors are physical-host contracts. Confirm interface names, PCI IDs,
drivers, IOMMU/VFIO state, and non-overlapping VF ranges on every target node.
The device plugin advertises resources but does not create VFs or bind drivers.

## Prerequisites

- Compatible Kubernetes and CRD versions for Cilium, Gateway API, Envoy
  Gateway, PureLB, ExternalDNS, and SR-IOV resources.
- Working Cilium datapath and out-of-band access before changing BGP, DNS
  egress, or node networking.
- Multus directories and container-runtime sockets at the rendered host paths.
- SR-IOV-capable hardware with VFs created and bound to referenced drivers.
- Reachable BGP peers, unique cluster IDs, correct CIDRs, and valid cluster-mesh
  endpoints.
- An existing DNS-provider Secret and least-privilege Cloudflare token for
  ExternalDNS. Never place its value in Git or rendered validation output.

## Validation

Cilium replacements must remain ready for four minutes (`minReadySeconds: 240`)
before the rolling update advances to the next node. This shared setting applies
to both sites; see [Kubernetes DaemonSet rolling updates](https://kubernetes.io/docs/tasks/manage-daemon/update-daemon-set/).

For the staged migration from disabled Cilium policy enforcement, follow the
[policy enforcement rollout](POLICY_ENFORCEMENT.md). It covers existing policy
inventory, per-site audit stages, workflow verification, and recovery.
The DC1-only `policyRollout` batch adds candidate restrictions for Envoy Gateway
controller egress and Longhorn manager/UI ingress. A render guard requires
audit mode; storage data-plane and recovery validation remains a cutover gate.
The current desired state evaluates policies in `default` mode with daemon
audit mode and policy verdict events enabled on both sites. Would-be L3/L4 denials
remain permitted; L7 proxy policies are not covered by audit mode. Longhorn and API/controller recovery checks must pass before
audit mode is disabled; live adoption requires Argo CD reconciliation and
verification of every agent's effective settings.

Resolve Helm dependencies locally; `Chart.lock` and `charts/` are intentionally
ignored and must not be committed. Render both named clusters with the same
Lovely plugin and injected layers used by Argo CD. At minimum, run:

```console
helm dependency update .
helm lint . -f representative-site-values.yaml
kustomize build . --load-restrictor LoadRestrictionsNone \
  | kubectl apply --dry-run=client -f -
git diff --check -- Network/Base
```

The representative values must include a non-empty
`sriovDevicePlugin.resourceList`; use the owning ApplicationSet configuration
for the target site. Do not invent interface names or VF ranges merely to make
the template pass.

The plain Kustomize command validates only the remote-resource layer. It does
not include Helm output or the ApplicationSet-injected Lovely merge. Inspect
complete renders for namespaces, selectors, resource names, privileges,
host-path mounts, mutable images, and unexpected Secret data.

After a staged Argo CD sync, verify the downstream outcome:

```console
kubectl -n kube-system rollout status daemonset/kube-sriov-device-plugin
kubectl -n kube-system get daemonset kube-sriov-device-plugin \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="kube-sriovdp")].resources.requests.cpu}{"\\n"}'
kubectl get nodes -o json
```

The JSONPath value must be `16m`. Inspect node `status.allocatable` for each
expected extended resource and schedule a representative workload requesting
one resource from the intended pool. Also verify Cilium health and connectivity,
cluster-mesh peers, BGP sessions and learned routes, LoadBalancer allocation,
Gateway listeners and routes, and actual ExternalDNS records.

## Rollback and deletion

Rollback through Git and let Argo CD reconcile the prior render. Reverting the
CPU request restores the prior pod template and rolls the DaemonSet again.
Existing workloads retain allocated devices during a normal plugin restart, but
new allocations may be unavailable until the plugin re-registers with kubelet.

Do not delete the Application as a rollback mechanism. The `ApplicationSet`
uses `preserveResourcesOnDeletion: true`, so deletion can leave unmanaged
resources. Removing Multus, SR-IOV, Cilium, BGP, or Gateway resources can strand
workloads or remove connectivity. First remove dependent workloads and
NetworkAttachmentDefinitions, confirm no devices or routes remain in use, then
remove ownership deliberately through Git while preserving out-of-band access.

## Cluster DNS configuration

Network/Base adopts the Talos-installed CoreDNS (`k8s-app=kube-dns`): the existing
`kube-system/coredns` ConfigMap, Deployment and ServiceAccount, plus the
`system:coredns` ClusterRole and ClusterRoleBinding. The kube-dns Service and
its DNS IP remain bootstrap-owned and unchanged. No additional namespaced
Role/RoleBinding is needed for the observed ServiceAccount access path.

The owning [ApplicationSet](../../Apps/Network/Base.yaml) injects
`kubeDNS.enabled: true`, `kubeDNS.clusterDomain` from
`{{ .values.clusterDomain }}`, and each site's `values.kubeDNS` settings. Both
sites supply `upstreams: ['1.1.1.1', '8.8.8.8']`. The shared Corefile lives in
[`CoreDNSConfig.yaml`](templates/DNS/CoreDNSConfig.yaml), not the ApplicationSet.
Defaults in [`values.yaml`](values.yaml) keep adoption disabled and reject
missing domains/images or empty upstream lists when enabled.

[`CoreDNSWorkload.yaml`](templates/DNS/CoreDNSWorkload.yaml) preserves bootstrap
names, selectors, RBAC, four replicas, resources, anti-affinity, tolerations
and `dnsPolicy: Default`. Direct manifests are an intentional common-library
exception to preserve fixed bootstrap identities and ordering without a
parallel Deployment or Service. Both sites use the shared
`registry.k8s.io/coredns/coredns:v1.13.2`
[image version](https://github.com/coredns/coredns/releases/tag/v1.13.2) from
`values.yaml`; Home1 upgrades from v1.12.0 on reconciliation while DC1 retains
its existing version. Review the upgrade and DNS reload logs before proceeding
to another site.
Both sites use shared `values.yaml` defaults for `NS_ID` from `status.podIP`,
liveness HTTP `/health` on 8080 (60-second initial delay), and readiness HTTP
`/ready` on 8181. Home1 gains these settings and will roll its DNS Deployment;
DC1 preserves its observed settings. See CoreDNS
[health](https://coredns.io/plugins/health/) and
[readiness](https://coredns.io/plugins/ready/) semantics.
RBAC remains list/watch only for endpoints,
Services, Pods, namespaces and EndpointSlices; no Secret access is added.

Before adoption, the live configurations observed on 2026-09-26 differ by site:

- Home1 resolves `k8s.home1.resolvemy.host` and `cluster.local` in Kubernetes,
  forwards other queries to `172.31.193.16`, and disables positive and negative
  caching for `k8s.home1.resolvemy.host`.
- DC1 resolves `cluster.local` and `k3s.dc1.resolvemy.host` in Kubernetes,
  forwards to `1.1.1.1`, `1.0.0.1`, `9.9.9.9`, and `8.8.8.8`, disables caching
  for `k3s.dc1.resolvemy.host`, and retains `nsid {$NS_ID}`.

The desired shared template Corefile forwards both sites to `1.1.1.1` and
`8.8.8.8`, serves `cluster.local` and the injected cluster domain, and disables
caching for that domain. It omits DC1's existing NSID directive. In Home1 this
bypasses the current site-local resolver, so verify any private zones previously
resolved by `172.31.193.16` before adoption. External DNS query metadata now goes
to these public resolvers. The existing DNS egress-gateway destinations include
both IPs. See
the CoreDNS [Kubernetes plugin](https://coredns.io/plugins/kubernetes/),
[forwarding plugin](https://coredns.io/plugins/forward/),
[cache plugin](https://coredns.io/plugins/cache/), and
[NSID plugin](https://coredns.io/plugins/nsid/) for their semantics.

Talos remains responsible for DNS bootstrap. Before initial adoption, verify
all adopted resources, their field managers, and the Deployment's `config-volume`
mount; check for a Talos/bootstrap reconciler that could overwrite them. The initial
server-side dry runs without conflict takeover report `data.Corefile` owned by
`kubectl-edit` in Home1 and Headlamp in DC1. Adoption must transfer that field to
Argo CD; earlier ConfigMap-only dry runs with `--force-conflicts` succeeded on
both clusters. Review the expanded adoption's field conflicts separately and
do not force replacement of bootstrap resources. The desired
forwarding changes require verification of private and external resolution on
both sites before adoption. ConfigMap, ServiceAccount and RBAC use sync wave -4,
then Deployment uses -3. Selective sync does not honor sync waves: adopt the
ConfigMap/ServiceAccount/RBAC first, then Deployment after checking dependencies.
Do not resync the whole networking stack for this adoption. CoreDNS's
[reload plugin](https://coredns.io/plugins/reload/) loads projected ConfigMap
changes without requiring a rollout; Pod-template changes do trigger a rolling
update. Check reload errors and resolve both a
cluster Service name and an external name from workload pods on different nodes:

```console
kubectl --context CONTEXT -n kube-system get configmap coredns -o yaml
kubectl --context CONTEXT -n kube-system logs -l k8s-app=kube-dns --since=10m
kubectl --context CONTEXT exec -n NAMESPACE POD -- nslookup kubernetes.default.svc.CLUSTER_DOMAIN
kubectl --context CONTEXT exec -n NAMESPACE POD -- nslookup github.com
```

Corefile edits take effect only after Git publication and Argo CD reconciliation;
creating these files alone does not change live DNS. Existing configurations
were managed by Talos and manual edits before adoption. Recovery must retain
node/API access independent of cluster DNS. Revert the shared template or site's
injected values in Git and selectively reconcile the affected resources to roll
back; in an incident, record any direct correction and reconcile it back to Git.
All adopted resources use Argo CD
[Prune=false](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-options/#no-prune-resources)
and [Delete=false](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-options/#no-resource-deletion)
so disabling adoption or deleting the Application retains DNS and its access path.
That leaves the last configuration unmanaged until another owner is deliberately
established; it does not restore the bootstrap Corefile automatically.

Run `bash tests/core-dns.sh DC1_VALUES HOME1_VALUES` with fully rendered
ApplicationSet/Lovely injected values files to verify identical base Corefiles,
resource identities, preserved DNS policy and required-value guards. The script
requires Helm, `rg` and jq-backed `yq`. Generated outputs remain in a private
temporary directory; do not publish rendered Secrets. Live query and reload
verification is still required after reconciliation.

Expanded server-side dry runs on 2026-09-26 accepted all five resources on each
site with conflict takeover simulated; prospective Deployment Pod templates
matched live state exactly before the later shared image/probe changes. Home1's
desired Pod template now changes and triggers a rollout. Without takeover,
only `data.Corefile` conflicted
on each site. These checks made no live changes and do not prove runtime DNS
resolution under the new upstreams.
