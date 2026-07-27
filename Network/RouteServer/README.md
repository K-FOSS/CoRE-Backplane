# Route Server chart

This chart deploys FRR route servers/reflectors from `frr` and `routeservers`
values. It is owned by `Apps/Network/RouteReflector.yaml`, which injects
site-specific peers, prefixes, communities and policy.

Configuration supports interfaces, BGP neighbors, numbered or unnumbered
peering, prefix lists and route maps. It requires correct node placement,
reachable peer interfaces, unique ASNs/router IDs and matching physical
switch/router policy.

Route-policy errors can leak, suppress or blackhole prefixes. Review generated
FRR configuration and compare received/advertised routes before and after
changes. Validate neighbors, address families, next hops, communities, local
preference/MED, prefix limits and data-plane reachability.
