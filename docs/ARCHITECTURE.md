# CoRE architecture

This document describes the major control planes and their dependencies. It is
an orientation map, not a complete inventory of every deployed application.

## Design model

CoRE is a GitOps-managed system of reconcilers. Git normally contains desired
state rather than imperative deployment steps. Argo CD renders and applies
that state, while Kubernetes operators, Crossplane providers, Cluster API,
Tinkerbell, and application controllers converge external or lower-level
resources.

```text
                           +----------------------+
                           | CoRE-Backplane Git   |
                           +----------+-----------+
                                      |
                                      v
                           +----------+-----------+
                           | Argo CD/ApplicationSet|
                           +----------+-----------+
                                      |
             +------------------------+------------------------+
             |                        |                        |
             v                        v                        v
      Helm/Kustomize          Crossplane APIs          Operator CRs
             |                        |                        |
             v                        v                        v
   Kubernetes workloads    Providers/Compositions      Managed services
                                      |
                       +--------------+--------------+
                       |              |              |
                       v              v              v
                    CAPI         Terraform       Kubernetes
                       |          Workspaces       Objects
                       v
                Tinkerbell/Talos
                       |
                       v
                Physical machines
```

The benefit is convergence and composability. The cost is that a resource may
pass through several controllers before its real-world outcome is known.
Operational health must therefore follow the whole dependency chain rather
than stop at Argo CD `Synced`.

## Reconciliation layers

### Fleet layer: Argo CD

ApplicationSets under `Apps/` select registered clusters using labels. Common
dimensions include:

- `mylogin.space/tenant`
- `resolvemy.host/env`
- `resolvemy.host/computetype`
- `resolvemy.host/nodetype`
- `resolvemy.host/dc`
- `topology.kubernetes.io/region`
- `topology.kubernetes.io/zone`
- `cluster.kubernetes.io/domain`

The selected metadata is injected into chart values, commonly through the
`argocd-lovely-plugin`. Most applications use server-side apply and many
preserve generated resources when an ApplicationSet entry disappears.

An Application being `Synced` proves only that its rendered Kubernetes objects
match Git. It does not prove that the workload, operator, Crossplane managed
resource, physical machine, or external service is healthy.

### Platform API layer: Crossplane

Crossplane provides:

- Kubernetes-object management across clusters.
- Terraform workspaces for providers not modeled directly.
- SQL, Vault, MinIO/S3, Authentik, and other provider integrations.
- Composite APIs for clusters, nodes, tenants, users, groups, SSO applications,
  database identities, and related platform services.

Pipeline Compositions use Go templating for newer APIs. Some templates embed
Terraform HCL, Talos configuration, scripts, and Kubernetes YAML. Every parser
boundary is a separate validation boundary.

### Cluster lifecycle layer

The cluster path combines:

- Crossplane `Cluster` and `ClusterNode` claims.
- Cluster API core resources.
- Tinkerbell infrastructure resources and workflows.
- Talos bootstrap/control-plane resources and Image Factory.
- Terraform provider workspaces.
- Per-cluster Kubernetes provider configurations.
- Cilium, FRR, and node-local networking configuration.

See the [Cluster chart](../Operations/Clusters/README.md) and
[BMPS](../Operations/Clusters/BMPS.md) for the detailed lifecycle.

### Identity and secret layer

Authentik is the identity source for users, services, and SSO integrations.
Envoy Gateway and security policies enforce authentication for applications
that do not integrate directly.

CoreVault contains bootstrap-tier material. Vault contains most application and
end-user secrets. External Secrets pulls data into Kubernetes; PushSecret and
Crossplane resources can publish generated credentials back to a secret store.

This creates a dependency chain:

```text
emergency credential
  -> CoreVault
  -> External Secrets
  -> Vault and platform credentials
  -> Authentik/databases/applications
```

Recovery plans must identify which credentials are available before DNS,
ingress, Authentik, Vault, or the main Kubernetes control plane is healthy.

### Data layer

PostgreSQL, MySQL, MongoDB, object storage, distributed cache/storage, and
persistent-volume systems live under `Databases/` and `Storage/`. PostgreSQL is
a particularly important dependency because it supports identity, platform,
and control-plane services.

Backups are not complete until restore procedures are tested. Kubernetes
resource backup, volume data, database-native backup, Vault state, Consul
state, and off-cluster object storage have different consistency requirements.

### Observability layer

The repository contains Grafana-oriented metrics, logs, traces, dashboards,
collectors, exporters, status, and SLO components. Monitoring should cover both
workloads and control-plane reconciliation:

- Argo CD sync and health.
- Crossplane claims, managed resources, and functions.
- Operator reconciliation errors.
- Kubernetes and Talos API health.
- Tinkerbell hardware/workflows.
- DNS, ingress, identity, and certificate paths.
- Backup completion and restore verification.
- Physical hardware, switching, power, and management reachability.

## Site and failure domains

CoRE spans YVR and YXL. Each site has a Cisco Nexus 92160YC-X; they are
site-separated switches, not a local redundant pair. YXL additionally has a
Cisco Nexus N3K-C3172TQ-10GT. The full known inventory is recorded in
[the environment document](../Operations/Clusters/ENVIRONMENT.md).

A site failure and a switch failure are different failure modes. Cross-site
placement does not remove a site's local switching, power, carrier, or
out-of-band-management dependencies.

## Critical dependency order

A useful conceptual recovery order is:

1. Power, switching, routing, DNS reachability, and out-of-band management.
2. A bootstrap Kubernetes/API path and Argo CD.
3. CoreVault bootstrap access and External Secrets.
4. Storage and database dependencies.
5. Vault and Authentik.
6. Crossplane, providers, functions, and provider configurations.
7. Cluster lifecycle and fleet applications.
8. User-facing applications and development environments.

The exact order varies by failure. The important rule is to avoid attempting
to recover a service through a dependency that the service itself must create.

## Architectural risks

- Multiple reconciliation layers can hide the real failure boundary.
- Custom rendering is part of the bootstrap chain.
- Moving Git revisions and image tags reduce reproducibility.
- Large inline Compositions are difficult to validate as a whole.
- Hard-coded site details limit portable recovery environments.
- Identity and secret automation can create circular recovery dependencies.
- Aggregate fleet capacity can hide insufficient capacity within one failure
  domain.

These are constraints to manage explicitly, not reasons to abandon the
architecture.
