# Photos

This rendering unit deploys Immich `v3.2.2` directly with the [BJW-S common
library](https://github.com/bjw-s-labs/helm-charts/tree/common-5.0.1/charts/library/common)
at `photos.mylogin.space`. The server and machine-learning workloads remain
`photos-server` and `photos-machine-learning`; the shared Dragonfly TLS proxy
is configured by the chart-generated `photos-redis-proxy` ConfigMap.

The v3 upgrade requires the database migration guidance to be reviewed because
v3 removes `pgvecto.rs`; this deployment selects `pgvector`. See Immich's
[v3.0.0 release notes](https://github.com/immich-app/immich/discussions/29439)
and [upgrade documentation](https://docs.immich.app/install/upgrading/)
before reconciliation.

Smart Search uses `ViT-B-16-SigLIP2__webli`, configured through the generated
Immich config ConfigMap. After changing the model, re-run all Smart Search jobs;
Immich notes that changing models can leave incompatible embeddings in the
database. See [Immich's Smart Search model guidance](https://docs.immich.app/features/searching/).

The chart currently deploys Immich's API and microservices together in the
single `photos-server` Deployment. The deployment does not override Immich's
worker selection; this follows the v3.2.2 server process model described in
the [upstream worker source](https://github.com/immich-app/immich/blob/v3.2.2/server/src/main.ts).

The Immich library is a dedicated `50Gi` Longhorn `ReadWriteMany` PVC named
`photos-library`, using the `photos-library` StorageClass. The StorageClass
uses one replica and a `Delete` reclaim policy; deleting the ApplicationSet
preserves Argo CD-managed resources, but deliberate PVC/StorageClass cleanup
deletes the volume. The library contains the user photo and video data and
must be included in backups before changing or removing this application.

The `photos` [`User` claim](../../Operations/SSO/User/README.md) creates the
Immich PostgreSQL role and database through the site-local Crossplane providers.
The workload consumes its generated `photos` connection Secret and connects to
`psql-local.<cluster>.<datacenter>.<region>.mylogin.space`. Immich requires a
PostgreSQL vector extension; this deployment selects `pgvector`, so the target
site-local PostgreSQL image must provide that extension. Immich uses the
site-local authenticated `dragonfly-core` service for its job queue and cache.
Because Immich's Redis client is configured for plaintext Redis, the server pod
includes a pinned [HAProxy](https://hub.docker.com/_/haproxy) sidecar. Immich
connects to the sidecar on `127.0.0.1:6379`; HAProxy forwards the connection to
the in-cluster Dragonfly service using TLS, the system CA bundle, and the
site-local Dragonfly hostname for certificate verification. The proxy is
configured using [HAProxy's TLS server options](https://docs.haproxy.org/3.2/configuration.html#5.2-ssl).
The proxy readiness check connects to its loopback listener from inside the
sidecar because the listener is intentionally bound to `127.0.0.1`.
Each `mlrunners` entry creates a dedicated machine-learning Deployment and
Service. The `intel` runner retains the `photos-machine-learning` name; other
runner names receive a suffix such as `photos-machine-learning-cuda`. Each
runner inherits its configured node selector, affinity, tolerations, resources,
hardware-appropriate Immich image tag, and the shared `photos-redis-proxy`
ConfigMap. All runners share a dedicated 30 GiB ReadWriteMany PVC named
`photos-ml-cache` for cached ML models. Immich receives all runner URLs through
the generated config.

Immich OAuth is automated with an Authentik OIDC provider and one generated
`photos-oidc` connection Secret. The Authentik Terraform Workspace generates
both the client ID and client secret, writes them and the
client ID and client secret outputs to the `photos-oidc` Secret, while the
non-secret Immich configuration is stored in the chart-generated
`photos-immich-config` ConfigMap. The common-library workload mounts the
ConfigMap and reads the OAuth credentials from the Secret. No OIDC credential is
stored in Git. The provider allows the Immich web and mobile redirect URIs and
is restricted to the configured `Media Consumers` group. See [Immich OAuth configuration](https://docs.immich.app/administration/oauth/)
and [Authentik OAuth2 providers](https://docs.goauthentik.io/add-secure-apps/providers/oauth2/).
The connection Secret is published by the [Crossplane Terraform provider](https://github.com/crossplane-contrib/provider-terraform)
Workspace rather than by a separate OIDC password generator.

The Intel machine-learning Deployment is pinned to the `laptop2` Kubernetes
node and uses Immich's `v3.2.2-openvino` image with the host `/dev/dri` device
directory. CUDA runners use the `v3.2.2-cuda` image and inherit their configured
NVIDIA resource and scheduling constraints. See Immich's [ML hardware acceleration documentation](https://docs.immich.app/features/ml-hardware-acceleration/).
The Dragonfly password is pulled into the namespace by an
[ExternalSecret](https://external-secrets.io/latest/api/externalsecret/)
from the site-specific CoreVault path, with logical database `133` reserved in the
[Dragonfly allocation registry](../../Storage/Dragonfly/CoRE/README.md). The
deployment does not run a chart-local Valkey instance.

The route is protected by the repository's Authentik Envoy external-authorization
path and the `Media Consumers` group. Verify the `User` claim, generated
Secret, PostgreSQL role/database and vector extension, PVC `Bound` status,
Immich server and machine-learning readiness, the websocket-enabled HTTP
Service, HTTPRoute `Accepted` status,
and an authenticated upload/download through the public hostname after Argo CD
reconciliation. See [Immich's Kubernetes guidance](https://docs.immich.app/install/kubernetes/)
and [database environment variables](https://docs.immich.app/install/environment-variables)
for upstream operational requirements.
