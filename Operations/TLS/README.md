# CoRE-Backplane Operations/TLS Stack

This deployment installs cert-manager and trust-manager and defines
Cloudflare/Vault-backed issuers and credentials. It is owned by
[the TLS ApplicationSet](../../Apps/Security/TLS.yaml). Its cluster generator
currently selects the Talos clusters `core-dc1-talos-prod` and
`core-home1-talos-prod` through the `mylogin.space/tenant` label.

## Ownership, targets and rendering

The ApplicationSet renders this chart into the `cert-manager` namespace on
each selected cluster. The chart pins [cert-manager 1.21.2](https://cert-manager.io/docs/releases/release-notes/release-notes-1.21/)
and [trust-manager 0.25.0](https://github.com/cert-manager/trust-manager/releases/tag/v0.25.0)
from the [Jetstack Helm repository](https://charts.jetstack.io/). Exact pins
keep both clusters on the same tested dependency set; do not replace them with
open-ended constraints.

The cert-manager controller and webhook run with two replicas, a rolling
update strategy that keeps one replica available, and a PodDisruptionBudget.
The controller remains leader-elected, so this protects the API and certificate
reconciliation paths during an upgrade without creating competing active
controllers.

ACME propagation checks use only Cloudflare `1.1.1.1`/`1.0.0.1` and Quad9
`9.9.9.9` on port 53 for DNS-01 and HTTP-01. The
[cert-manager DNS-01 configuration](https://cert-manager.io/docs/configuration/acme/dns01/)
documents why `--dns01-recursive-nameservers-only` is required to prevent the
controller from falling back to cluster-local recursive DNS. This does not
change Kubernetes API or Vault service discovery, which still uses cluster DNS.

## Dependencies

- Vault/External Secrets for issuer credentials.
- Cloudflare DNS credentials for applicable ACME challenges.
- Reachable ACME and Vault endpoints.
- Correct DNS zones, trust bundles and Gateway consumers.

## Upgrade and verification

Before upgrading, back up cert-manager resources as recommended by the
[cert-manager upgrade guide](https://cert-manager.io/docs/installation/upgrade/).
For a future minor-version change, follow the upstream guidance to upgrade one
minor version at a time using the latest patch release, and review the relevant
[release notes](https://cert-manager.io/docs/releases/) first. This chart is
currently on the supported 1.21 line; cert-manager 1.21 requires Kubernetes
1.22 or newer and trust-manager 0.25 requires Kubernetes 1.25 or newer.

After Argo CD reconciles each child application, verify the cert-manager and
trust-manager Deployments, webhook readiness, all `Issuer` and `ClusterIssuer`
conditions, active ACME `Order`/`Challenge` resources, certificate renewal
times, and trust-manager `Bundle` conditions on both Talos clusters. A healthy
rollout alone does not prove that existing certificates can renew.

The 1.21 upgrade removes the chart-created `serviceaccounts/token` grant and
some aggregate ACME `Challenge`/`Order` permissions. This deployment uses the
Vault token Secret and Cloudflare credentials defined by this stack; it does
not use `serviceAccountRef` pointing at the cert-manager controller ServiceAccount
or create ACME Orders/Challenges directly. If that usage changes, add explicit
RBAC before upgrading. See the [1.20 to 1.21 upgrade notes](https://cert-manager.io/docs/releases/upgrading/upgrading-1.20-1.21/).

Certificate and issuer changes can affect most platform ingress and internal
TLS simultaneously. Validate issuer readiness, challenge/order state,
certificate renewal, secret ownership, served chains and trust-manager bundle
propagation. Preserve emergency access that does not depend on the certificate
path being changed.
