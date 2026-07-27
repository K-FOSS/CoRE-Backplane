# TLS operations deployment

This deployment installs cert-manager and trust-manager and defines
Cloudflare/Vault-backed issuers and credentials. It is owned by
`Apps/Security/TLS.yaml`.

## Dependencies

- Vault/External Secrets for issuer credentials.
- Cloudflare DNS credentials for applicable ACME challenges.
- Reachable ACME and Vault endpoints.
- Correct DNS zones, trust bundles and Gateway consumers.

Certificate and issuer changes can affect most platform ingress and internal
TLS simultaneously. Validate issuer readiness, challenge/order state,
certificate renewal, secret ownership, served chains and trust-manager bundle
propagation. Preserve emergency access that does not depend on the certificate
path being changed.
