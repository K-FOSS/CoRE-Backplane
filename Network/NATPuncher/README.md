# NATPuncher chart

NATPuncher deploys CoTURN as CoRE's STUN/TURN service for NAT traversal and
relayed connectivity. It is owned by `Apps/Network/NATPuncher.yaml`.

Review listening/public addresses, UDP/TCP/TLS ports, relay ranges,
firewall/NAT policy, authentication realm/users, secret references,
LoadBalancer exposure, DNS and certificates.

Validate STUN discovery and authenticated TURN allocations from outside the
cluster. Test UDP and TCP/TLS fallback separately and monitor allocation
failures, bandwidth, port exhaustion and authentication errors.

TURN is abuse-sensitive. Do not enable anonymous relay, expose management
interfaces, or use weak static credentials.
