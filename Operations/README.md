# CoRE Operations deployments

`Operations` contains the foundational controllers and platform APIs that make
the rest of CoRE deployable: Crossplane, secrets, TLS, cluster lifecycle,
operators, device discovery, virtual machines, resource policy and
multicluster management.

These are Lovely deployment directories. A directory can combine Helm,
Kustomize, remote HTTP resources, raw manifests, patches and Crossplane
templates.

## Deployment index

| Deployment | Purpose | Fleet owner |
| --- | --- | --- |
| [Clusters](Clusters/README.md) | CAPI, Talos, Tinkerbell, Kamaji and cluster/node APIs. | `Apps/Infra/Cluster.yaml` |
| [Crossplane](Crossplane/README.md) | Crossplane, providers, functions and credentials. | `Apps/Infra/Crossplane/Crossplane.yaml` |
| [Secrets](Secrets/README.md) | External Secrets and Vault stores. | `Apps/Infra/ExternalSecrets.yaml` |
| [TLS](TLS/README.md) | cert-manager, trust-manager and issuers. | `Apps/Security/TLS.yaml` |
| [Operators](Operators/README.md) | Operator Lifecycle Manager. | `Apps/Infra/Operators.yaml` |
| [Configuration](Configuration/README.md) | Stakater Reloader. | `Apps/Operations/Configurations.yaml` |
| [Devices](Devices/README.md) | GPU/device plugins, NFD, DRA, HAMi and Kepler. | `Apps/Operations/Devices.yaml` |
| [Resources](Resources/README.md) | Goldilocks and Descheduler. | `Apps/Infra/Resources.yaml` |
| [VirtualMachines](VirtualMachines/README.md) | KubeVirt, CDI and management UI. | `Apps/Infra/KubeVirt.yaml` |
| [Benchmarking](Benchmarking/README.md) | Storage benchmark jobs/classes. | `Apps/Operations/Benchmarking.yaml` |
| [Load](Load/README.md) | k6 Operator. | `Apps/Operations/Load.yaml` |
| [Provisioning](Provisioning/README.md) | Crossplane iDRAC and metal initialization APIs. | `Apps/Infra/Crossplane/Provisioning.yaml` |
| [SSO User](SSO/User/README.md) | User, group, tenant and S3 credential APIs. | `Apps/Infra/Crossplane/User.yaml` |
| [SSO Application](SSO/Application/README.md) | SSO application/route XRDs. | No direct ApplicationSet found. |
| [MultiClusters](MultiClusters/README.md) | OCM/Clusterpedia multicluster management. | No direct ApplicationSet found. |
| [Networks/Crossplane](Networks/Crossplane/README.md) | Network machine/prefix XRDs. | No direct ApplicationSet found. |
| [Rancher](Rancher/README.md) | Rancher management server. | No direct ApplicationSet found. |
| [S3](S3/README.md) | Generic S3 operator. | No direct ApplicationSet found. |
| [Base/EPIC](Base/EPIC/README.md) | EPIC/Marin3r resource model and Contour. | No direct ApplicationSet found. |
| [Base/Kuadrant](Base/Kuadrant/README.md) | Kuadrant subscription/resources. | No direct ApplicationSet found. |
| [Base/MCS](Base/MCS/README.md) | Open Cluster Management manager import. | No direct ApplicationSet found. |
| [Base/MultiClusterGateway](Base/MultiClusterGateway/README.md) | Empty/unfinished multicluster gateway boundary. | No direct ApplicationSet found. |
| [Base/Spoke](Base/Spoke/README.md) | OCM Klusterlet/spoke registration. | No direct ApplicationSet found. |

## Bootstrap sensitivity

Operations deployments are not peers. A useful dependency order is:

```text
Kubernetes and Argo CD/Lovely
  -> TLS and Secrets
  -> Operators and Crossplane
  -> device/storage/network foundations
  -> cluster/provisioning and multicluster APIs
  -> ordinary platform services
```

Remote Kustomize URLs and moving branches are part of the supply chain.
Inspect the complete rendered output and pin immutable releases where
reproducibility matters.

## Change safety

Controller changes can reconcile many resources at once. Before upgrading an
operator, CRD, Crossplane provider or composition, inventory all managed
resources, conversion versions, deletion policies, credentials and recovery
state. Argo CD `Synced` does not prove downstream reconciliation succeeded.
