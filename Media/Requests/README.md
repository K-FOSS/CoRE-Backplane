# Media requests

This rendering unit deploys [Seerr](https://docs.seerr.dev/) through the
[`bjw-s/common` library chart](https://github.com/bjw-s-labs/helm-charts/tree/main/charts/library/common).
`Apps/Media/Requests.yaml` owns the Argo CD ApplicationSet and injects the
selected media tenant and cluster values.

Seerr is published at `https://requests.mylogin.space` and protected by a
fail-closed Envoy Gateway `SecurityPolicy` backed by an Authentik forward
proxy. Access is restricted to the `Media Consumers` group. See the
[Seerr Docker documentation](https://github.com/seerr-team/seerr/blob/v3.4.1/docs/getting-started/docker.mdx)
for the image contract, port `5055`, `/app/config` persistence path, and
health endpoint.

The image is pinned to Seerr `v3.4.1` and its multi-architecture manifest
digest. The config PVC stores Seerr's SQLite database and application settings;
back it up before upgrades or removal. After first reconciliation, complete
Seerr's setup wizard and configure the media server, Radarr/Sonarr, and any
notifications in the application UI. Do not commit those credentials.

After reconciliation, verify the Deployment, config PVC, Service, HTTPRoute,
SecurityPolicy, and Authentik Workspace conditions. Then verify an
unauthenticated request redirects to Authentik, a `Media Consumers` member can
open Seerr, and a request reaches the configured *arr service and completes.
Removing the ApplicationSet preserves resources; removing the chart does not
by itself prove that the retained PVC or Authentik resources were deleted.
