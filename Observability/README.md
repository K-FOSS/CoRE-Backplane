# Observability stack

The CoRE Backplane observability area contains the platform's collection,
storage, visualization, and service-level monitoring workloads. Components are
deployed independently by Argo CD ApplicationSets under
[`Apps/Observability`](../Apps/Observability/) and are joined through their
network endpoints, generated credentials, and shared labels rather than by one
umbrella chart.

## Component map

| Path | Role | Current implementation |
| --- | --- | --- |
| [`Collectors`](Collectors/) | Receives, discovers, enriches, and forwards telemetry. | Grafana Alloy and Vector. |
| [`Logs`](Logs/) | Stores and queries logs. | Grafana Loki in one-replica `SingleBinary` mode with S3 storage. |
| [`Metrics`](Metrics/) | Stores and queries metrics. | Grafana Mimir. |
| [`Traces`](Traces/) | Stores and queries distributed traces. | Grafana Tempo in monolithic mode. |
| [`Dashboards`](Dashboards/) | Visualization and interactive exploration. | Grafana with Authentik and LDAP integration. |
| [`Exporters`](Exporters/) | Exposes Kubernetes and platform metrics for collection. | `kube-prometheus-stack`. |
| [`Kubernetes`](Kubernetes/) | Kubernetes-specific observability configuration. | Helm-managed cluster monitoring values. |
| [`SLO`](SLO/) | Service-level objective resources. | Helm chart; coverage remains incremental. |
| [`Status`](Status/) | Publishes service status and related credentials/routes. | Helm and Kustomize resources. |

For component-specific behavior, start with the [Loki logs guide](Logs/README.md),
[traces guide](Traces/README.md), or [exporters guide](Exporters/README.md).

## Telemetry flow

```text
Kubernetes workloads, nodes, and network devices
  -> Collectors / Exporters
  -> Loki (logs), Mimir (metrics), Tempo (traces)
  -> Grafana dashboards and queries

External Grafana and operator requests
  -> shared Envoy Gateway
  -> HTTPRoute + SecurityPolicy
  -> telemetry backend
```

Collectors add cluster and datacentre labels using values injected by their
ApplicationSet. Loki pods carry the `logs=loki-myloginspace` label, which is
also selected by Alloy's Kubernetes log discovery. Grafana accesses backend
APIs using gateway-mediated Authentik JWTs; backend SecurityPolicies forward
the `orgID` claim as `X-Scope-OrgID` where configured.

The current Alloy log writer points at a fixed Loki address in
[`Collectors/values.yaml`](Collectors/values.yaml), while the public query API
uses Loki's cluster-specific Gateway hostname. Treat that address as an
operational dependency when moving Loki or changing service networking. A
service-discovery-based destination would reduce this coupling but is not the
current implementation.

## Deployment model

Each component has its own ApplicationSet. The ApplicationSets select clusters
by platform labels and inject cluster name, environment, region, datacentre,
and component-specific settings through `LOVELY_HELM_MERGE`. This keeps fleet
selection in `Apps/Observability` and workload implementation in
`Observability`.

The principal deployment entry points are:

- [`Apps/Observability/Collectors.yaml`](../Apps/Observability/Collectors.yaml)
- [`Apps/Observability/Dashboards.yaml`](../Apps/Observability/Dashboards.yaml)
- [`Apps/Observability/Logs.yaml`](../Apps/Observability/Logs.yaml)
- [`Apps/Observability/Metrics.yaml`](../Apps/Observability/Metrics.yaml)
- [`Apps/Observability/Traces.yaml`](../Apps/Observability/Traces.yaml)

Change cluster selection and fleet-specific overrides in those ApplicationSets.
Change component behavior and versions in the corresponding chart. Deploy
through Argo CD rather than applying an implementation chart directly.

## Shared dependencies

Depending on the component, target clusters require:

- Grafana Alloy/Vector and Prometheus-compatible discovery or exporters;
- Gateway API and Envoy Gateway SecurityPolicy CRDs;
- Authentik and Crossplane Terraform provider configuration;
- platform `User` compositions for generated S3 identities and credentials;
- regional S3 services and provider configs;
- External Secrets or PushSecret controllers for synchronized credentials; and
- the backend-specific operator or Helm dependency pinned by each chart.

Credentials are generated or synchronized at runtime. References and Secret
names are committed to Git, but secret values must not be.

## Operating and changing the stack

Before merging a change:

1. Identify the owning ApplicationSet and every selected cluster.
2. Build Helm dependencies and render the affected chart with representative
   injected values.
3. Check generated routes, service ports, issuer URLs, storage providers, and
   Secret references together.
4. Review downstream `User`, Terraform Workspace, operator, and External
   Secrets conditions—not only the parent Argo CD health state.
5. Confirm ingestion and query paths after reconciliation in a target cluster.

When troubleshooting, follow the signal in order: source or exporter,
collector, backend readiness and storage, Gateway authorization, then Grafana.
A healthy dashboard does not prove ingestion is current, and a healthy Argo CD
Application does not prove every downstream Crossplane resource is ready.

## Current limitations

- Loki and Tempo currently use single-node deployment models and are not
  highly available.
- The Alloy-to-Loki destination is a fixed network address.
- Repository-wide rendering and schema validation are not automated.
- SLO coverage and component runbooks are incomplete.
- Several charts rely on cluster-specific CRDs and provider configs that are
  not installed by the component chart itself.

These constraints should be reviewed before topology, retention, endpoint, or
fleet-selection changes.
