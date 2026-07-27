# CoRE Backplane

CoRE Backplane is the declarative source of truth for a solo-operated,
multi-site private cloud. It contains the Argo CD applications, Helm charts,
Kustomize overlays, Crossplane APIs, and deployment-specific configuration
used to run the platform.

The environment spans YVR and YXL in two Canadian provinces. It includes
enterprise Dell compute, Cisco data-centre switching, Kubernetes and Talos
clusters, centralized identity, storage, databases, observability, and
browser-based Eclipse Che development environments. Detailed physical
inventory and failure-domain context are maintained in
[Operations/Clusters/ENVIRONMENT.md](Operations/Clusters/ENVIRONMENT.md).

This is a live operations repository. Many manifests contain site-specific
names, private addresses, domains, and secret-store references. It is not a
generic Kubernetes distribution and should not be applied to another
environment without a complete review.

## Platform goals

- Describe infrastructure and services as version-controlled desired state.
- Use Argo CD to select target clusters and reconcile applications.
- Use Crossplane to expose higher-level APIs for clusters, nodes, identities,
  databases, object storage, and provider configuration.
- Provision physical Kubernetes nodes through Tinkerbell and Talos.
- Centralize human and service identity in Authentik.
- Keep secret values in Vault and synchronize them at runtime through External
  Secrets rather than storing them directly in Git.
- Preserve remote management and recovery access when an individual site
  fails.
- Observe and back up the platform as first-class workloads.

## Control flow

```text
Git commit
  -> Argo CD ApplicationSet
  -> target-cluster selection from labels
  -> argocd-lovely-plugin / Helm / Kustomize rendering
  -> Kubernetes resources and operators
  -> Crossplane, CAPI, or application-specific reconciliation
  -> physical infrastructure and user-facing services
```

Argo CD ApplicationSets under `Apps/` are the principal fleet-level entry
points. They select registered clusters by labels such as tenant, environment,
region, datacentre, compute type, and node type, then deploy the corresponding
chart directory.

Crossplane adds a second reconciliation layer for resources that benefit from
a higher-level API or span multiple providers. The cluster and bare-metal path
adds Cluster API, Terraform workspaces, Tinkerbell, and Talos reconciliation.
See [Architecture](docs/ARCHITECTURE.md) for the component and dependency map.

## Major platform areas

| Area | Repository path | Responsibility |
| --- | --- | --- |
| Fleet deployment | `Apps/` | Argo CD ApplicationSets and per-cluster value injection. |
| Argo CD | `ArgoCD/` | GitOps controller configuration and rendering plugin integration. |
| Identity and access | `AAA/`, `Operations/SSO/` | Authentik, user/service identities, SSO application APIs, LDAP, RADIUS, and OIDC. |
| Cluster lifecycle | `Operations/Clusters/` | Crossplane cluster/node APIs, CAPI, Talos, Tinkerbell, and Kamaji. |
| Crossplane platform | `Operations/Crossplane/` | Crossplane installation, providers, functions, and provider credentials. |
| Secrets and PKI | `Operations/Secrets/`, `Operations/TLS/`, `Hashicorp/` | External Secrets, Vault, certificate material, and bootstrap secret paths. |
| Networking | `Network/` | CNI, ingress, DNS, IPAM, bare metal, routing, tunnels, TLS, and network services. |
| Data services | `Databases/`, `Storage/` | PostgreSQL, MySQL, MongoDB, object storage, caches, and persistent storage. |
| Observability | `Observability/` | Metrics, logs, traces, dashboards, collectors, exporters, SLOs, and status. |
| Backup and recovery | `Backups/` | Velero and service-specific backup integration. |
| Development | `Development/`, `IDE/`, `Lab/` | Eclipse Che, developer services, virtual machines, and experiments. |
| Policy and security | `Security/`, `QoS/` | Authentication policy, scanning, TLS, and workload priority. |

The [Repository guide](docs/REPOSITORY.md) describes conventions and how to
tell fleet entry points, implementation charts, examples, and experimental
areas apart.

## Identity and secrets

Authentik is the primary source of human and service identity. Applications
integrate through OIDC/OAuth2, LDAP, RADIUS, or gateway-mediated authentication
as appropriate.

The secret bootstrap chain is intentionally separate from ordinary
application reconciliation:

1. A CoreVault credential is introduced through an out-of-band bootstrap
   procedure.
2. External Secrets reads bootstrap secrets from CoreVault.
3. Vault uses CoreVault-backed mechanisms for its own initialization/unseal
   path.
4. Application credentials are generated or stored in Vault and synchronized
   to target namespaces.
5. Crossplane and PushSecret resources generate and publish credentials for
   databases, S3, identity providers, and other services.

Secret references in Git are not secret values. Nevertheless, all manifests
must be reviewed for literal default credentials before deployment. See
[Operations and recovery](docs/OPERATIONS.md) for bootstrap and emergency
access principles.

## Cluster and bare-metal lifecycle

The cluster chart defines `Cluster`, `ClusterNode`, and `Tenant` Crossplane
APIs. A cluster claim produces Cluster API and provider resources; a node claim
selects hardware, prepares a Talos image and configuration, and drives a
Tinkerbell provisioning workflow.

Start with:

- [Cluster chart documentation](Operations/Clusters/README.md)
- [Deployment environment](Operations/Clusters/ENVIRONMENT.md)
- [Bare Metal Provisioning System](Operations/Clusters/BMPS.md)
- [Cluster and BMPS backlog](Operations/Clusters/TODO.md)

Physical provisioning can erase disks. Never infer safety from a successful
template render: verify hardware identity, installation disk, workflow state,
and the destructive options on the node claim.

## Working in this repository

Before changing a chart:

1. Identify its owning ApplicationSet under `Apps/` and the clusters selected
   by that ApplicationSet.
2. Check for Helm dependency, custom renderer, CRD, operator, and secret-store
   prerequisites.
3. Render the chart with representative values.
4. Validate generated resources against the API versions installed in the
   target cluster.
5. Review deletion behavior, sync waves, namespace ownership, and generated
   secrets.
6. Apply through Argo CD unless an incident runbook explicitly calls for a
   direct operation.
7. Observe both the Argo CD application and any downstream operator or
   Crossplane conditions.

Common local setup utilities can be downloaded by `setup.sh`, but that script
currently downloads some moving releases and does not verify checksums. Treat
it as a convenience script, not a reproducible or trusted bootstrap mechanism.

## Current maturity

The platform is in active production use and supports the operator's daily
development workflow. It has also accumulated experimental, legacy, and
site-specific paths. Current availability experience is described in the
deployment environment document, but the repository does not yet define a
formal service-level objective.

Important limitations:

- Automated repository-wide chart rendering and schema validation are not yet
  present.
- Some Crossplane Compositions report readiness before checking the real
  downstream condition.
- Several bootstrap and recovery procedures still depend on operator knowledge.
- Active, experimental, and legacy directories are not uniformly marked.
- Some values and compositions contain unsafe example/default credentials.

These limitations are documented so that the repository does not imply a
stronger safety contract than it currently provides.

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Repository guide](docs/REPOSITORY.md)
- [Operations and recovery](docs/OPERATIONS.md)
- [Cluster Operations chart](Operations/Clusters/README.md)
- [Crossplane](Operations/Crossplane/README.md)
- [Secrets](Operations/Secrets/README.md)
- [Network ingress](Network/Ingress/README.md)
- [Network IPAM](Network/IPAM/README.md)
- [Observability traces](Observability/Traces/README.md)
- [PostgreSQL](Databases/PSQL/README.md)

Documentation describes both current behavior and intended direction. Where
the two differ, manifests and observed controller state are authoritative.
