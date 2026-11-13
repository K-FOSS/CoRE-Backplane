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
- Envoy proxy tracing to the cluster-local Alloy OTLP/gRPC Service.

| Label | Meaning |
| --- | --- |
| `resolvemy.host/gw` | Gateway name. |
| `resolvemy.host/gw-ns` | Gateway namespace. |
| `resolvemy.host/security` | Exposure/authentication mode. |

Dependencies include Gateway API/Envoy Gateway, Cilium and LoadBalancer
addresses, cert-manager, DNS/ExternalDNS and Authentik.

The shared EnvoyProxy samples 10% of proxy requests by default and exports
traces over OTLP/gRPC to the cluster-local `core-collectors-alloy-otlp` Service
in `core-prod`. The same service name is present in each Talos production
cluster, so the configuration targets the local Alloy instance; Alloy then
forwards traces to the configured Tempo backend. The Authentik HTTPRoutes use a
route-level policy to raise their sampling fraction to 100%. See the
[Envoy Gateway proxy tracing documentation](https://gateway.envoyproxy.io/docs/tasks/observability/proxy-trace/)
and [Grafana Alloy OTLP exporter documentation](https://grafana.com/docs/alloy/latest/reference/components/otelcol/otelcol.exporter.otlp/)
for the upstream behavior.

The shared HTTPS listener uses [Gateway API certificate references](https://gateway-api.sigs.k8s.io/guides/user-guides/tls/)
for every public hostname it terminates. Its certificate list includes the
`accessmyporndownload-default-certificates` Secret declared by
`Network/TLS/Certificates` so the Stash route can serve
`accessmyporn.download`. The Stash ApplicationSet currently deploys only to
`core-home1-talos-prod`; adding the certificate to a shared listener does not
create a route on other clusters.

The shared Gateway exposes dedicated SIP, mail, and IMAP listener sections for
cross-namespace `UDPRoute`, `TCPRoute`, and `TLSRoute` attachments:
`sip-udp`/`sip-tcp` on `5060` and `sips-tls` on `5061`. The SMTP and IMAP
listener definitions are currently commented out pending application route
backends. The TLS listeners use passthrough mode because the attached
`TLSRoute` owns the backend TLS flow; certificates and route backend Services
remain owned by the application charts.

The `sips-no-sni-fallback` [EnvoyPatchPolicy](https://gateway.envoyproxy.io/docs/api/extension_types/#envoypatchpolicy)
removes the generated SNI match from the `sips-tls` filter chain so TLS clients
without SNI can still reach the Kamailio TLS backend. Keep this patch aligned
with the single SIPS TLSRoute and verify its `Accepted` and `Programmed`
conditions after Gateway reconciliation.

Verify Gateway/HTTPRoute `Accepted`, `Programmed` and `ResolvedRefs`, DNS, SNI
and certificate chains, redirects, backend health, and login/logout flows.
Avoid changing shared listeners, policies, DNS and certificates in one
unvalidated rollout.
