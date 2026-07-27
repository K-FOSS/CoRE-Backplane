# Cluster Operations chart

This Helm chart installs the APIs and controllers used to create Kubernetes
clusters and provision their bare-metal nodes. The current implementation is
alpha-quality and is tailored to Talos Linux, Cluster API, Tinkerbell, Kamaji,
and Crossplane.

## What the chart installs

- Cluster API Operator and infrastructure/bootstrap/control-plane provider
  definitions.
- Kamaji and its configured datastore integration.
- Crossplane composite resource definitions (XRDs) and pipeline Compositions
  for `Cluster`, `ClusterNode`, and `Tenant`.
- Tinkerbell infrastructure provider configuration.
- Example production `Cluster` and `ClusterNode` claims under
  `templates/prod`.

The Crossplane API defaults are configured in `values.yaml`:

| API | Default group/version | Purpose |
| --- | --- | --- |
| `Cluster` | `resolvemy.host/v1alpha1` | Describes a Kubernetes cluster and its shared configuration. |
| `ClusterNode` | `resolvemy.host/v1alpha1` | Describes one machine, its hardware selection, networking, and node-specific configuration. |
| `Tenant` | `mylogin.space/v1alpha1` | Associates cluster resources with a tenant. |

## Architecture

```text
Cluster claim
  -> XCluster / cluster-init Composition
  -> Cluster API Cluster, control plane, machine templates
  -> kubeconfig, Talos config, and provider configuration

ClusterNode claim
  -> XClusterNode / cluster-node Composition
  -> observe its Cluster claim and matching Tinkerbell Hardware
  -> Talos Image Factory schematic and machine configuration
  -> Tinkerbell workflow and machine
  -> Kubernetes Node and node-local networking resources
```

Crossplane uses `function-go-templating` to render the composed resources. Some
Talos resources are managed through Terraform provider workspaces, while
Kubernetes objects are managed through Crossplane Kubernetes provider
configurations.

## Prerequisites

Before installing this chart, the management cluster must provide:

- Crossplane with the Go templating function referenced by
  `crossplane.functionsRef.gotemplate.name`.
- Crossplane Kubernetes and Terraform providers, including the provider
  configurations referenced by the Compositions (`local-k8s`, `tf-talos`, and
  generated per-cluster configurations).
- cert-manager.
- A reachable Tinkerbell stack with its hardware inventory populated.
- Network services required for PXE/iPXE provisioning, including DHCP and the
  Tinkerbell endpoint.
- A PostgreSQL datastore and TLS/authentication secrets matching the Kamaji
  settings when the bundled defaults are used.
- Registry access for Talos, Kubernetes, Tinkerbell, and system-extension
  images.

Review every environment-specific value before deployment. In particular,
`tinkerbell.ip`, Kamaji datastore endpoints and secrets, registry mirrors,
provider versions, namespaces, and example production claims are not portable
defaults.

## Installation and validation

Fetch dependencies and render the chart before applying it:

```sh
helm dependency build
helm lint .
helm template ops-clusters . > rendered.yaml
```

Install or upgrade it with the environment's values file:

```sh
helm upgrade --install ops-clusters . \
  --namespace core-prod \
  --create-namespace \
  --values values.yaml
```

This repository also contains Argo CD tracking annotations and sync waves. In
GitOps environments, prefer reconciliation through the owning Argo CD
application instead of invoking Helm directly.

## Cluster-wide sysctls

Set `spec.sysctls` on a `Cluster` claim to apply a kernel sysctl to every node
in that cluster:

```yaml
apiVersion: resolvemy.host/v1alpha1
kind: Cluster
metadata:
  name: example
  namespace: core-prod
spec:
  sysctls:
    - name: net.core.bpf_jit_harden
      value: "1"
    - name: vm.max_map_count
      value: "262144"
```

`ClusterNode.spec.sysctls` is applied after the cluster list. A node value with
the same name therefore overrides the cluster value. Values are strings
because that is the format expected by the Talos machine configuration.

Treat sysctl changes as operating-system changes: validate them against the
deployed Talos version and test them on a non-critical node first.

## Creating resources

Start with a `Cluster` claim containing its tenant, environment, Talos and
Kubernetes versions, control-plane endpoint, network ranges, and compute type.
Then create one or more `ClusterNode` claims that reference it through
`spec.clusterRef`.

The manifests under `templates/prod` are deployment-specific examples, not a
stable public API reference. The authoritative schemas are:

- `templates/CrossplaneOps/ClusterResource.yaml`
- `templates/CrossplaneOps/ClusterNodeResource.yaml`
- `templates/CrossplaneOps/Tenant.yaml`

## Operations and troubleshooting

Follow reconciliation from the claim down to the composed resources:

```sh
kubectl describe cluster.resolvemy.host -n <namespace> <cluster>
kubectl describe clusternode.resolvemy.host -n <namespace> <node>
kubectl get composite,object,workspace -A
kubectl get clusters,machines,tinkerbellclusters,tinkerbellmachines -A
kubectl get hardware,workflow -A
```

Useful failure boundaries are:

1. The claim is not accepted by its XRD: inspect schema validation and the
   selected Composition.
2. A Composition is not ready: inspect composed `Object` and `Workspace`
   conditions and provider configuration.
3. No hardware is selected: compare the `Hardware` labels with the node and
   machine-template selectors.
4. A workflow does not start or complete: inspect Tinkerbell controller,
   boots, DHCP, and workflow task status.
5. Talos boots but never joins: inspect generated machine configuration,
   control-plane reachability, time synchronization, and Kubernetes/Talos
   version compatibility.

See [Bare Metal Provisioning](BMPS.md) for the provisioning lifecycle and
[TODO](TODO.md) for known gaps.
