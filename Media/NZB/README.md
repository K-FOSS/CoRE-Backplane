# NZB download services

This Helm rendering unit deploys [SABnzbd](https://sabnzbd.org/wiki/),
[Prowlarr](https://wiki.servarr.com/prowlarr), and
[FileBrowser Quantum](https://filebrowserquantum.com/en/docs/) through the
[`bjw-s/common` library chart](https://github.com/bjw-s-labs/helm-charts/tree/main/charts/library/common).
`Apps/Media/NZB.yaml` owns the Argo CD ApplicationSet, selects the
`core-home1-talos-prod` bare-metal infrastructure cluster, injects the `augy`
tenant, and deploys into `core-media`.

## Public access and data flow

SABnzbd is available at `nzb.mylogin.space`, Prowlarr at
`prowlarr.mylogin.space`, and the download explorer at
`downloads.mylogin.space`. Each public HTTPRoute has a separate Authentik
single-application forward-auth provider and application restricted to the
`Media Consumers` group. See [`../AUTHENTIK.md`](../AUTHENTIK.md) for the
shared access path, prerequisites, and recovery behavior.

SABnzbd writes fetched files to the existing `augy-downloads` persistent
volume. FileBrowser Quantum mounts that same claim at `/downloads` read-only,
so authenticated users can browse and download files but cannot upload,
rename, or delete them through the explorer. Envoy enforces Authentik before
requests reach its Service. FileBrowser application-side authentication is
disabled with `noauth`, making the fail-closed SecurityPolicy and Authentik
`Media Consumers` entitlement the sole public authentication boundary.
FileBrowser's local database and cache are ephemeral pod state and do not
contain download data, so browser preferences and indexes are rebuilt after
pod replacement.
The container runs as UID and GID `911:911`, matching the download service's
filesystem identity; its ephemeral writable state is kept under `/tmp` rather
than the image's UID-1000-owned home directory.
Prowlarr's LinuxServer container is configured with `PUID=911` and `PGID=911`
so its process-created files and persistent config use the same media service
identity.

SABnzbd, Prowlarr, and FileBrowser participate in the shared hostname-level
pod preference documented in [`../STORAGE_AFFINITY.md`](../STORAGE_AFFINITY.md).
The same selector is used by every workload that mounts the media or downloads
claims.

The FileBrowser Quantum image is pinned to stable release `1.5.3` and its
registry digest. Its [Docker documentation](https://filebrowserquantum.com/en/docs/getting-started/docker-v1.5.x/),
[source configuration](https://filebrowserquantum.com/en/docs/advanced/source-configuration/sources/),
and [no-auth documentation](https://filebrowserquantum.com/en/docs/configuration/authentication/noauth/)
describe the mounted paths and why the Service must not be exposed through a
path that bypasses the gateway policy.

## Verification and rollback

After Argo CD reconciliation, verify the Terraform Workspace and all three
Authentik applications and providers, then confirm all HTTPRoutes are
`Accepted` and the SecurityPolicy resolves and attaches to each route. An
unauthenticated request to every hostname must redirect to Authentik; a
`Media Consumers` member must be admitted and an account outside that group
must be denied. In the explorer, download a representative completed file and
confirm upload, rename, and delete operations fail. Check the FileBrowser pod
can read the downloads claim before treating pod readiness as end-to-end
success.

Rolling back the FileBrowser controller, Service, route, config, and
application removes browser access without deleting the shared downloads
claim. Removing an Authentik application from the inline Terraform module
causes Terraform to destroy that provider, application, entitlement, and
bindings on reconciliation. The ApplicationSet preserves resources on
deletion, so confirm Terraform destruction and gateway detachment before
manually removing finalizers or retained resources.
