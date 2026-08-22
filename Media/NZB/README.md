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
requests reach its Service, then FileBrowser uses Authentik's forwarded
username for proxy authentication. Password authentication is disabled, and
auto-provisioned users receive browse/download-only defaults. The
SecurityPolicy is fail-closed. FileBrowser's local database and cache are
ephemeral pod state and do not contain download data, so browser preferences,
proxy users, and indexes are rebuilt after pod replacement.

The FileBrowser Quantum image is pinned to stable release `1.5.3` and its
registry digest. Its [Docker documentation](https://filebrowserquantum.com/en/docs/getting-started/docker-v1.5.x/),
[source configuration](https://filebrowserquantum.com/en/docs/advanced/source-configuration/sources/),
and [proxy-authentication documentation](https://filebrowserquantum.com/en/docs/configuration/authentication/proxy/)
describe the mounted paths and why the identity header must not be accepted
from a path that bypasses the gateway policy.

## Verification and rollback

After Argo CD reconciliation, verify the Terraform Workspace and all three
Authentik applications and providers, then confirm all HTTPRoutes are
`Accepted` and the SecurityPolicy resolves and attaches to each route. An
unauthenticated request to every hostname must redirect to Authentik; a
`Media Consumers` member must be admitted and an account outside that group
must be denied. In the explorer, download a representative completed file and
confirm upload, rename, and delete operations fail. Check the FileBrowser pod
can read the downloads claim and its own PVC before treating pod readiness as
end-to-end success.

Rolling back the FileBrowser controller, Service, route, config, and
application removes browser access without deleting the shared downloads
claim. Removing an Authentik application from the inline Terraform module
causes Terraform to destroy that provider, application, entitlement, and
bindings on reconciliation. The ApplicationSet preserves resources on
deletion, so confirm Terraform destruction and gateway detachment before
manually removing finalizers or retained resources.
