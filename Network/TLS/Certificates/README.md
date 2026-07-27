# Network TLS Certificates chart

This chart creates per-cluster certificate resources and Gateway reference
grants. `Apps/Network/Certificates.yaml` injects cluster, environment,
datacentre and region.

It requires cert-manager, the referenced issuer, DNS-provider credentials,
Gateway API resources and any Vault/External Secrets integration used by the
issuer.

Verify certificate `Ready`, issuer/challenge status, DNS names, renewal time,
secret location, Gateway `ResolvedRefs`, and the externally served TLS chain
and SNI. Confirm secret ownership and renewal before removing an established
certificate.
