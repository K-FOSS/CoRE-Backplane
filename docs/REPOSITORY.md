# Repository guide

CoRE Backplane is organized primarily by operational domain. It contains both
fleet-level Argo CD entry points and the charts/manifests those entry points
deploy.

## Directory map

| Path | Contents |
| --- | --- |
| `Apps/` | Argo CD ApplicationSets. Start here to learn where and how a subsystem is deployed. |
| `ArgoCD/` | Argo CD configuration and custom rendering integration. |
| `AAA/` | Authentik and shared authentication/authorization services. |
| `Operations/` | Foundational operators, Crossplane, cluster lifecycle, secrets, TLS, resources, and operational tooling. |
| `Network/` | Bare-metal networking, IPAM, DNS, ingress, routing, tunnels, CNI, and network appliances. |
| `Databases/` | Database operators and database service charts. |
| `Storage/` | Persistent storage, object storage, caches, search, and related data services. |
| `Observability/` | Metrics, logs, traces, dashboards, collectors, exporters, SLOs, and status. |
| `Hashicorp/` | CoreVault, Vault, unseal automation, and related configuration. |
| `Development/`, `IDE/` | Eclipse Che and developer-platform services. |
| `Security/` | Authentication policy, vulnerability/security tooling, and certificates. |
| `Backups/` | Velero and service-specific backup components. |
| `Media/`, `Gaming/`, `EventStream/`, `Management/` | Workload-domain applications. |
| `Lab/` | Experiments and validation workloads; do not assume production support. |
| `Libraries/` | Shared or reusable chart fragments/components. |
| `Meta/` | Locally downloaded operational CLI tools and helper scripts. |

## Finding the deployment owner

For a chart such as `Operations/Clusters`:

1. Search `Apps/` for `path: Operations/Clusters`.
2. Read the ApplicationSet generators and cluster-label selector.
3. Read the renderer/plugin values injected by the ApplicationSet.
4. Inspect the target chart and its dependencies.
5. Follow any Crossplane or operator custom resources to their controller
   installation under `Operations/`.

Useful searches:

```sh
rg -n "path: Operations/Clusters" Apps
rg -n "kind: ApplicationSet" Apps
rg -n "providerConfigRef:|functionRef:" Operations
rg -n "ExternalSecret|PushSecret" .
```

## Configuration layers

A rendered resource may be influenced by:

1. A chart's `values.yaml`.
2. Values injected by an ApplicationSet.
3. Helm templates.
4. Kustomize overlays.
5. The custom Argo CD renderer.
6. Crossplane Go templates and observed resource state.
7. Terraform modules embedded in a Composition.
8. Admission controllers or operators that default/mutate the resource.

When debugging, identify every layer before assuming the source file directly
matches the live object.

## Repository status categories

The repository does not yet label every directory consistently. Use these
working interpretations:

- `Apps/` reference plus an active target cluster selector: likely deployed.
- `templates/prod`: deployment-specific production manifest.
- `Lab/`, names containing `Test`, or commented ApplicationSet entries:
  experimental unless documented otherwise.
- Names containing `Old`, `Legacy`, or `Migrate`: transitional and should not
  be treated as the preferred implementation.
- A chart without an ApplicationSet reference may be a dependency, library,
  inactive component, or manual deployment.

This is heuristic, not a formal lifecycle policy. Establishing explicit
`active`, `experimental`, `deprecated`, and `archived` ownership metadata is
future work.

## Conventions

Common labels include:

| Label | Meaning |
| --- | --- |
| `mylogin.space/tenant` | Tenant ownership. |
| `resolvemy.host/env` | Environment such as production, staging, POC, or lab. |
| `resolvemy.host/dc` | Datacentre/site identifier. |
| `resolvemy.host/computetype` | Bare metal, virtual machine, or other compute type. |
| `resolvemy.host/nodetype` | Infrastructure, compute, or bootstrap/init role. |
| `resolvemy.host/priority` | Operational priority used by policy, backup, or scheduling. |
| `topology.kubernetes.io/region` | Geographic or operational region. |
| `topology.kubernetes.io/zone` | Failure-domain zone. |
| `cluster.kubernetes.io/domain` | Cluster DNS domain metadata. |

Argo CD sync waves express coarse dependency ordering, but they do not replace
real readiness checks.

## Secret handling

Expected secret patterns are:

- Vault-path placeholders consumed by the rendering process.
- `ExternalSecret` resources pulling values into Kubernetes.
- `PushSecret` resources publishing generated values.
- Crossplane connection secrets.

Do not add literal production credentials. Placeholder/default passwords are
also unsafe when the chart can deploy with them. New charts should fail
validation when required secret references are absent.

## Change checklist

- Determine every selected target cluster.
- Check the worktree for unrelated edits.
- Render with representative injected values.
- Validate API versions and CRDs against the target cluster.
- Review secrets and generated output for accidental disclosure.
- Check selectors, namespaces, ownership references, and deletion policy.
- Check whether a change affects bootstrap or recovery dependencies.
- For physical infrastructure, confirm exact target identity and disk/network
  impact.
- Reconcile through Argo CD and inspect downstream controller conditions.

Never interpret Argo CD `Synced` alone as proof that an external resource or
physical machine is healthy.
