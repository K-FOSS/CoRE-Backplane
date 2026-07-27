# CoRE network charts

The `Network` directory contains the charts that provide cluster networking,
service ingress, DNS/IPAM, bare-metal boot services, routed overlays, remote
access, and network-management applications.

These charts operate at several layers. A successful Helm render does not
prove that routing converged, DNS answers correctly, a certificate is usable,
or a physical host can PXE boot.

## Chart index

| Chart | Purpose | Fleet entry point |
| --- | --- | --- |
| [Base](Base/README.md) | Cilium, BGP, SR-IOV, load balancing, Gateway and ExternalDNS foundations. | `Apps/Network/Base.yaml` |
| [BareMetal](BareMetal/README.md) | Tinkerbell and static artifacts used by physical provisioning. | `Apps/Network/BareMetal.yaml` |
| [ClusterBroker](ClusterBroker/README.md) | Submariner broker and broker credentials. | No direct ApplicationSet currently found. |
| [Filter](Filter/README.md) | Containerized IPv4/IPv6 filtering/routing function. | `Apps/Network/Filter.yaml` |
| [Ingress](Ingress/README.md) | Envoy Gateway, shared gateways, routes and authentication policy. | `Apps/Network/Ingress.yaml` |
| [IPAM](IPAM/README.md) | NetBox/DCIM, DHCP, DNS integration and inventory credentials. | `Apps/Network/IPAM.yaml` |
| [NATPuncher](NATPuncher/README.md) | CoTURN STUN/TURN service. | `Apps/Network/NATPuncher.yaml` |
| [NS](NS/README.md) | PowerDNS and PowerDNS-Admin authoritative DNS. | `Apps/Network/NS.yaml` |
| [PrivateNetworking](PrivateNetworking/README.md) | NetBird and optional/transitional Netmaker overlays. | `Apps/Network/PrivateNetworking.yaml` |
| [RDNS](RDNS/README.md) | CoreDNS reverse DNS and PowerDNS integration. | No direct ApplicationSet currently found. |
| [RouteServer](RouteServer/README.md) | FRR route reflectors/servers and routing policy. | `Apps/Network/RouteReflector.yaml` |
| [Testing](Testing/README.md) | LibreSpeed, iperf3 and network validation resources. | `Apps/Network/Testing.yaml` |
| [TLS/Certificates](TLS/Certificates/README.md) | Per-cluster certificates and Gateway references. | `Apps/Network/Certificates.yaml` |
| [Tunnels](Tunnels/README.md) | WireGuard/IP tunnels with FRR routing integration. | `Apps/Network/Tunneler.yaml` and legacy `TunnelerOld.yaml` |
| [Unifi](Unifi/README.md) | UniFi Network Application and database/secret integration. | `Apps/Network/Unifi.yaml` |

## Deployment model

ApplicationSets under `Apps/Network` select registered Argo CD clusters using
tenant, environment, region, datacentre, compute-role and node-role labels.
They inject site-specific values such as cluster domains, peers, addresses,
routes and service exposure.

Most charts use `argocd-lovely-plugin` to merge Helm values and, in some cases,
Kustomize patches. Inspect the owning ApplicationSet before rendering from the
checked-in `values.yaml`.

## Typical dependency order

```text
physical switching and routing
  -> Base (CNI and service networking)
  -> Secrets and TLS
  -> IPAM/DNS and BareMetal
  -> Ingress and private networking
  -> route servers and tunnels
  -> applications and network testing
```

Sync waves provide coarse ordering but do not replace readiness or network
validation.

## Shared dependencies

Charts may require Cilium, Gateway API and Envoy Gateway, External Secrets and
Vault stores, Crossplane user/credential APIs, cert-manager, ExternalDNS,
NetBox, Tinkerbell, DHCP/PXE, object storage, FRR and Linux networking
capabilities.

## Change safety

Before reconciling a network change:

1. Identify every cluster selected by the ApplicationSet.
2. Render with injected cluster/site values.
3. Check interfaces, addresses, CIDRs, ASNs, policies and peer direction.
4. Confirm the change does not remove its own management/recovery path.
5. Preserve out-of-band access.
6. Apply one failure domain at a time where practical.
7. Validate inside and outside the affected cluster.

Validate Cilium status, routing neighbors/tables, Gateway and HTTPRoute
conditions, authoritative DNS, certificate chains, TURN allocation, WireGuard
handshakes and PXE boot as applicable.

The physical topology is documented in
[Operations/Clusters/ENVIRONMENT.md](../Operations/Clusters/ENVIRONMENT.md).
