# Private media

This Helm rendering unit deploys [MeTube](https://github.com/alexta69/metube)
and Whisparr using the
[`bjw-s/common` library chart](https://github.com/bjw-s-labs/helm-charts/tree/main/charts/library/common).
`Apps/Media/Private.yaml` owns the Argo CD ApplicationSet, injects the `augy`
media tenant for the current home cluster, and deploys the release into
`core-media`.

MeTube is published at `metube.accessmyporn.download`, and Whisparr at
`whisparr.accessmyporn.download`, through the shared Gateway. Both routes are
protected by separate Authentik single-application forward-auth providers.
Access is restricted to the `Media Consumers` group. Each route uses a
fail-closed Envoy Gateway SecurityPolicy and the shared Authentik proxy service;
see the shared
[media forward-auth runbook](../AUTHENTIK.md) for prerequisites, reconciliation,
verification, and removal behavior. MeTube's container configuration and
runtime options are documented in its
[upstream README](https://github.com/alexta69/metube#configuration).

After reconciliation, verify both HTTPRoutes and SecurityPolicies are accepted
and attached without resolution errors, the Authentik Workspace is `Ready`, an
unauthenticated request to each hostname redirects to Authentik, and an
authorized `Media Consumers` member can use both applications.
