# Reverse DNS chart

This chart packages CoreDNS reverse-DNS service and PowerDNS
configuration/credentials.

## Deployment status

No direct `Apps/Network` ApplicationSet reference was found. Treat it as
inactive, manually deployed or indirectly consumed until ownership is
confirmed.

It depends on authoritative reverse-zone delegation, PowerDNS/database
reachability where used, Vault/External Secrets, and correct address
inventory. Query PTR records directly and through normal resolvers; verify
IPv4 `in-addr.arpa`, IPv6 `ip6.arpa`, parent delegation, negative answers and
TTL/cache behavior.
