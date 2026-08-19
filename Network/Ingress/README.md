# Network Ingress chart

This chart defines CoRE's shared ingress layer using Envoy Gateway and Gateway
API resources. It is owned by `Apps/Network/Ingress.yaml`; the Envoy Gateway
controller itself is enabled through Network Base.

## Components

- GatewayClass and shared Gateway resources.
- EnvoyProxy and BackendTrafficPolicy configuration.
- HTTP routes and HTTPS redirects.
- Authentik forward-auth/security policy.
- Specialized Home Assistant and UniFi integration.
- Backend and certificate reference grants.

| Label | Meaning |
| --- | --- |
| `resolvemy.host/gw` | Gateway name. |
| `resolvemy.host/gw-ns` | Gateway namespace. |
| `resolvemy.host/security` | Exposure/authentication mode. |

Dependencies include Gateway API/Envoy Gateway, Cilium and LoadBalancer
addresses, cert-manager, DNS/ExternalDNS and Authentik.

The shared HTTPS listener uses [Gateway API certificate references](https://gateway-api.sigs.k8s.io/guides/user-guides/tls/)
for every public hostname it terminates. Its certificate list includes the
`accessmyporndownload-default-certificates` Secret declared by
`Network/TLS/Certificates` so the Stash route can serve
`accessmyporn.download`. The Stash ApplicationSet currently deploys only to
`core-home1-talos-prod`; adding the certificate to a shared listener does not
create a route on other clusters.

Verify Gateway/HTTPRoute `Accepted`, `Programmed` and `ResolvedRefs`, DNS, SNI
and certificate chains, redirects, backend health, and login/logout flows.
Avoid changing shared listeners, policies, DNS and certificates in one
unvalidated rollout.
