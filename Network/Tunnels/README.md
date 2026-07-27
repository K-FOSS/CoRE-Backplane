# Network Tunnels chart

This chart deploys WireGuard and IP tunnel endpoints with optional
FRR/BGP/OSPF routing integration. Its primary owner is
`Apps/Network/Tunneler.yaml`; legacy `Apps/Network/TunnelerOld.yaml` also
targets it, so inspect both before changing defaults.

`tunnelers` entries define placement, tunnel type, addresses, WireGuard peers
and allowed IPs, services, FRR routing, policies, static routes and bandwidth
settings. Private keys are expected from Vault-path references injected by the
ApplicationSet.

Some paths require Linux networking capabilities or privileged containers.
Review rendered security contexts, host networking, device access and sysctls.

Tunnel changes can remove cross-site/emergency access. Preserve out-of-band
access; verify both endpoints, keys, MTU, allowed IPs, routing neighbors/routes
and external failover. See [TODO](TODO.md) for migration work.
