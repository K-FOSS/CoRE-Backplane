# Shared media services

This rendering unit deploys shared media storage, FlareSolverr, Bazarr, and
[Scraparr](https://github.com/thecfu/scraparr) through the
[`bjw-s/common` library chart](https://github.com/bjw-s-labs/helm-charts/tree/main/charts/library/common).
[`Apps/Media/Common.yaml`](../../Apps/Media/Common.yaml) owns the Argo CD
ApplicationSet and injects the cluster, tenant, and environment values.

## Scraparr

Scraparr is an internal Prometheus exporter for Sonarr, Radarr, Prowlarr, and
Bazarr. The deployment uses the immutable upstream release tag `3.1.0`, listens
on port `7100`, and exposes only a ClusterIP Service plus a ServiceMonitor; it
has no public route. See the upstream [configuration guide](https://github.com/thecfu/scraparr/blob/main/docs/configuration.md)
and [connector reference](https://github.com/thecfu/scraparr/blob/main/docs/connectors.md)
for the configuration contract.

Before reconciliation, create the namespaced `scraparr-api-keys` Secret with
`SONARR_API_KEY`, `RADARR_API_KEY`, `PROWLARR_API_KEY`, and `BAZARR_API_KEY`.
The Secret is intentionally not managed here and its values must not be
committed. Scraparr reads the keys through environment variables while the
non-secret URLs and scrape settings are rendered into its ConfigMap.

After reconciliation, verify the Secret, Scraparr pod, ServiceMonitor target,
and `scraparr_services_up` metrics in Mimir. Removing Scraparr removes only
the exporter and ServiceMonitor; it does not delete the shared media claims or
the *arr applications.
