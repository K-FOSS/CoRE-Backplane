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

Verify Gateway/HTTPRoute `Accepted`, `Programmed` and `ResolvedRefs`, DNS, SNI
and certificate chains, redirects, backend health, and login/logout flows.
Avoid changing shared listeners, policies, DNS and certificates in one
unvalidated rollout.
