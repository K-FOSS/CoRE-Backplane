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

The chart also issues `syncmydate-default-certificates` for `syncmy.date` and
`*.syncmy.date`. Network/Time mounts that Secret for Chrony's NTS server; the
private key remains cert-manager-managed and is not stored in Git.

For `core-dc1-talos-prod`, the chart issues
`observability-garage-s3-tls` for
`observability-garage-s3.core-prod.svc.<cluster-domain>` using the
`kjdev-cluster` ClusterIssuer. The Secret stays in `core-prod` and is
referenced by the Envoy Gateway `main-gw` HTTPS listener. Its HTTPRoute sends
S3 requests to Garage over the cluster network; Garage's S3 listener itself
is HTTP. The certificate source is the cluster's injected
`cluster.domain` FQDN, such as `k3s.dc1.resolvemy.host`, rather than the
Kubernetes default `cluster.local` domain. `Apps/Network/Certificates.yaml`
uses the repository's slop remote so this certificate follows the same Git
revision as the other deployed stacks.

Verify certificate `Ready`, issuer/challenge status, DNS names, renewal time,
secret location, Gateway `ResolvedRefs`, and the externally served TLS chain
and SNI. Confirm secret ownership and renewal before removing an established
certificate.
