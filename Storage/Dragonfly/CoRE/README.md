# Dragonfly CoRE chart

This chart deploys a Dragonfly distribution/cache service with two replicas,
TLS, S3-backed persistent content and generated credentials. It is owned by
`Apps/Storage/Dragonfly/CoRE.yaml`.

Crossplane user resources create S3 access; ExternalSecret and PushSecret
resources synchronize credentials; a Terraform provider configuration is
generated for integration.

It depends on the Dragonfly Operator/CRDs, S3, Vault/External Secrets,
Crossplane, certificates and network reachability.

Validate replica health, TLS, S3 read/write, credential rotation, cache/data
recovery and client behavior during one-replica failure. Clarify which content
is authoritative in S3 and which state is disposable cache before defining a
restore procedure.
