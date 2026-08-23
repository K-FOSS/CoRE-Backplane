# Media Gaming

This Helm rendering unit deploys
[Questarr](https://github.com/Doezer/Questarr), its persistent SQLite data,
shared media mounts, Service, public Gateway API route, and Authentik access
resources through the
[`bjw-s/common` library chart](https://github.com/bjw-s-labs/helm-charts/tree/main/charts/library/common).
`Apps/Media/Gaming.yaml` owns the Argo CD ApplicationSet. It currently selects
only `core-home1-talos-prod`, injects the `augy` media tenant, and deploys the
release into `core-media`.

## Runtime, storage, and permissions

The deployment pins the upstream
[`v1.4.2` release](https://github.com/Doezer/Questarr/releases/tag/v1.4.2)
from the authoritative
[Questarr GHCR package](https://github.com/Doezer/Questarr/pkgs/container/questarr)
by its multi-architecture manifest digest. Questarr listens on port `5000`;
Kubernetes checks its documented `/api/health` endpoint during startup and for
readiness and liveness. The upstream
[`docker-compose.yml`](https://github.com/Doezer/Questarr/blob/v1.4.2/docker-compose.yml)
and [`Dockerfile`](https://github.com/Doezer/Questarr/blob/v1.4.2/Dockerfile)
define the same port and `/app/data` data path.

The `questarr-config` ReadWriteOnce PVC persists `/app/data`, including the
SQLite database, generated JWT signing secret, credentials-encryption key, and
application settings. Questarr's
[`SECRETS.md`](https://github.com/Doezer/Questarr/blob/v1.4.2/docs/SECRETS.md)
documents how those generated keys and configured downloader/indexer
credentials are protected. Back up and restore the entire PVC as one unit;
restoring only the database or only generated keys can invalidate sessions or
make stored credentials unusable.

The pod mounts the existing tenant claims at `/downloads` and `/Media`, matching
the other Media stacks. Configure Questarr downloader path mappings to use
those exact in-container paths and choose a library destination below
`/Media`. They are separate PVC filesystems, so imports between them cannot be
atomic renames and may fall back to a copy-and-delete workflow. Verify free
space and the completed import before deleting source data.

Questarr's upstream container entrypoint starts as root only to remap a Docker
bind-mount user and correct ownership before launching `npm run start`. This
chart bypasses that Docker permission shim because Kubernetes supplies the
established Media identity directly: the process runs as non-root UID/GID
`911`, the volumes use `fsGroup=911`, and all Linux capabilities are dropped.
Service account token mounting and privilege escalation are disabled, and the
pod uses the runtime-default seccomp profile. Restored files must remain
writable by `911:911`; validate that before reconciliation because the
container cannot repair ownership itself. The pod participates in the shared
Media storage scheduling preference described in
[`STORAGE_AFFINITY.md`](../STORAGE_AFFINITY.md).

## Access and application setup

Questarr is exposed at `https://games.mylogin.space`. A fail-closed Envoy
Gateway SecurityPolicy sends requests through the shared Authentik proxy, and
the Terraform Workspace grants the Authentik `Media Consumers` group access to
the application and its `media-access` entitlement. See
[`AUTHENTIK.md`](../AUTHENTIK.md) for the shared access path, prerequisites,
and emergency-access requirements.

Authentik protects the route but does not replace Questarr's own accounts.
After first reconciliation, an authorized operator must create the initial
Questarr administrator, then configure IGDB, indexers, downloaders, path
mappings, and application-level users in the UI. Store third-party credentials
only in Questarr's encrypted persistent settings or introduce an approved
Vault/ExternalSecret integration; do not put them in Helm values.

## Verification, rollback, and deletion

After Argo CD reconciliation, verify the Deployment becomes Available, all
three health probes succeed, and the config and shared claims are mounted with
UID/GID `911` write access. Confirm the Terraform Workspace is Ready and its
downstream Authentik provider, application, entitlement, and group bindings
exist. Then verify the HTTPRoute is Accepted, the SecurityPolicy is attached,
an unauthenticated request is redirected, a `Media Consumers` member can pass
Authentik, and a non-member is denied. Finally test Questarr login, an indexer
search, downloader submission, completed-download path mapping, and import
into `/Media`; pod readiness alone does not prove that workflow.

Rollback by reverting the chart and ApplicationSet through Git. Removing the
release stops Questarr but does not itself prove that the retained PVC or
Authentik resources were deleted: the ApplicationSet preserves resources on
deletion, and the PVC contains the application database and encrypted
credentials. Confirm any Terraform destroy and take or deliberately expire a
backup before deleting the PVC or finalizers.
