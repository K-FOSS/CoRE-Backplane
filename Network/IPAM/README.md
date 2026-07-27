# IPAM and DCIM chart

This chart deploys and integrates CoRE's NetBox-based network and hardware
inventory. It is owned by `Apps/Network/IPAM.yaml`, which injects datacentre,
region, DHCP boot paths and cluster metadata.

## Components

- Optional NetBox chart and the deployment's custom image/plugins.
- BGP and IP-calculator plugin support.
- DHCP configuration, templates, identities and secret synchronization.
- DNS/PowerDNS, Authentik/OIDC, Gateway and S3 integration.
- Crossplane/Terraform resources and generated service identities.

NetBox is intended to become the source of truth for sites, racks, devices,
interfaces, prefixes, addresses, VLANs, VRFs, BGP sessions, bare-metal
inventory and DHCP/PXE data. Integration is incomplete; see [TODO](TODO.md).

Dependencies include PostgreSQL, Vault/External Secrets, Crossplane,
Authentik, Gateway API, DNS/certificates and object storage where enabled.

Inventory changes can drive automation. Validate prefix overlap, address
uniqueness, interface/hardware identity, BGP direction, DHCP reservations,
boot artifacts and generated downstream configuration. Back up NetBox and
test restoration before treating it as provisioning authority.
