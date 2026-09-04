# Private media

This Helm rendering unit deploys [MeTube](https://github.com/alexta69/metube)
and Whisparr using the
[`bjw-s/common` library chart](https://github.com/bjw-s-labs/helm-charts/tree/main/charts/library/common).
`Apps/Media/Private.yaml` owns the Argo CD ApplicationSet, injects the `augy`
media tenant for the current home cluster, and deploys the release into
`core-media`.

MeTube is published at `metube.mylogin.space` through the shared Gateway and
protected by Authentik single-application forward auth. Access is restricted
to the `Media Consumers` group. The route uses a fail-closed Envoy Gateway
SecurityPolicy and the shared Authentik proxy service; see the shared
[media forward-auth runbook](../AUTHENTIK.md) for prerequisites, reconciliation,
verification, and removal behavior. MeTube's container configuration and
runtime options are documented in its
[upstream README](https://github.com/alexta69/metube#configuration).

After reconciliation, verify the MeTube HTTPRoute is `Accepted`, the
SecurityPolicy is attached without resolution errors, the Authentik Workspace
is `Ready`, an unauthenticated request redirects to Authentik, and an authorized
`Media Consumers` member can use the application.
