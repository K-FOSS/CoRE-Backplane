# Network TLS Certificates chart

This chart creates per-cluster certificate resources and Gateway reference
grants. `Apps/Network/Certificates.yaml` injects cluster, environment,
datacentre and region.

The chart declares [cert-manager `Certificate` resources](https://cert-manager.io/docs/usage/certificate/)
for the hostnames served by shared Gateways. This includes the
`accessmyporn.download` certificate consumed by the `core-prod/main-gw` HTTPS
listener for the Stash route. cert-manager stores it in the
`accessmyporndownload-default-certificates` Secret in `core-prod`; the Gateway
only reads that Secret and does not own its lifecycle. The resource retains the
established certificate and Secret identity from the legacy
`Security/TLS/Certificates` declaration.

It requires cert-manager, the referenced issuer, DNS-provider credentials,
Gateway API resources and any Vault/External Secrets integration used by the
issuer.

Verify certificate `Ready`, issuer/challenge status, DNS names, renewal time,
secret location, Gateway `ResolvedRefs`, and the externally served TLS chain
and SNI. Confirm secret ownership and renewal before removing an established
certificate.
