# Grafana dashboards

This chart deploys the pinned upstream
[Grafana Helm chart](https://github.com/grafana/helm-charts/tree/main/charts/grafana)
and CoRE identity resources. The
[`core-observability-dashboards` ApplicationSet](../../Apps/Observability/Dashboards.yaml)
targets the two infrastructure clusters and injects the cluster-local Alloy
OTLP address and Dragonfly-backed Grafana Live address.

Grafana is a single replica. LDAP is enabled using the existing
`grafana-core-ldap` Secret; the chart templates also manage Authentik/OIDC
configuration and generated credentials. Dashboard discovery is performed by
the chart sidecar watching ConfigMaps labelled `grafana_dashboard` in the
release namespace. This is one namespaced API watch, not the source of the
cluster-wide monitoring traffic described in the
[Collectors guide](../Collectors/README.md).

Prerequisites include Authentik, the platform `User` composition, Crossplane
Terraform provider configuration, Dragonfly, and any dashboard ConfigMaps.
Credentials are generated or synchronized at runtime.

After reconciliation, verify the Grafana health endpoint, LDAP login,
dashboard sidecar logs, datasource connectivity, and OTLP export to Alloy.
Render and lint with representative ApplicationSet values before merging.
Rollback is through Git/Argo CD; preserve-on-delete means Application deletion
does not guarantee resource cleanup.
