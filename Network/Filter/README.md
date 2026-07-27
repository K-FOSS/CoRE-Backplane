# Network Filter chart

This chart deploys a containerized IPv4/IPv6 filtering function intended to
participate in CoRE's routed/segment-routing environment. It is owned by
`Apps/Network/Filter.yaml` and uses the BJW-S common chart.

Review injected and checked-in values for interfaces, addresses, route
advertisements, forwarding/filter policy, node placement, and Linux
capabilities or privileged access.

A filter node can become both a choke point and a bypass path. Incorrect
policy ordering or route advertisement can blackhole traffic or expose an
isolated network. Validate IPv4 and IPv6 independently, inspect advertised
routes, and test both permitted and prohibited flows before directing
production traffic through a new instance.
