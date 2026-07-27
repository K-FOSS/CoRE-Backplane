# Network Base chart

This chart installs foundational Kubernetes networking components.

## Components

- Cilium CNI and Cilium BGP resources.
- Optional SR-IOV Network Operator.
- Optional Cloudflare-oriented ExternalDNS.
- Optional PureLB, Envoy Gateway and FRR-K8s.
- Cluster-specific DNS egress and SR-IOV configuration.

`Apps/Network/Base.yaml` injects cluster/site values and applies Kustomize
patches in addition to Helm rendering. Top-level settings are `cilium`,
`sriov-network-operator`, `cf-dns`, `purelb`, `envoy-gw` and `frr-k8s`.

## Prerequisites and validation

Confirm pod/service CIDRs, node addresses, kernel support, physical BGP peers,
and Multus/SR-IOV hardware before enabling related components. ExternalDNS
also requires secret-store and DNS-provider credentials.

This chart can affect all pod, service, ingress, DNS and node connectivity.
After changes, validate Cilium/node health, pod and service traffic, DNS,
ingress, BGP advertisements, LoadBalancer allocation and SR-IOV attachments.
Roll out one cluster/site at a time and preserve out-of-band access.
