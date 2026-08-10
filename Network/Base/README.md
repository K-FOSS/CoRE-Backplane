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
