# Dragonfly CoRE chart

This chart deploys a Dragonfly distribution/cache service with two replicas,
TLS, S3-backed persistent content and generated credentials. It is owned by
`Apps/Storage/Dragonfly/CoRE.yaml`.

The Dragonfly CR enables its Memcached-compatible listener on port 11211. The
operator adds that port to the master-selecting `dragonfly-core` Service; each
site's PGPool deployment uses its site-specific public DNS name as a shared
query cache.
The Redis endpoint remains password protected and TLS enabled. PGPool's
memcached client does not use that Redis authentication path, so the chart's
NetworkPolicy admits port 11211 only from same-namespace pods labelled
`app.kubernetes.io/name: pgpool`, while preserving existing port 6379 access.
See Dragonfly's
[Memcached compatibility documentation](https://www.dragonflydb.io/blog/memcached-to-dragonfly-stop-serializing-start-simplifying)
and the
[Dragonfly Operator repository](https://github.com/dragonflydb/dragonfly-operator).

Crossplane user resources create S3 access; ExternalSecret and PushSecret
resources synchronize credentials; a Terraform provider configuration is
generated for integration.

It depends on the Dragonfly Operator/CRDs, S3, Vault/External Secrets,
Crossplane, certificates and network reachability.

Validate replica health, TLS, S3 read/write, credential rotation, cache/data
recovery and client behavior during one-replica failure. Clarify which content
is authoritative in S3 and which state is disposable cache before defining a
restore procedure.
