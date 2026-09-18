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

### Talos compute-node configuration compatibility

The `cluster-node` Composition detects the installed Talos version with
[`talosctl version`](https://docs.siderolabs.com/talos/v1.12/reference/cli) and
compares it with the intended cluster version. It emits the separate
multi-document network/storage/device patches only when both versions are
Talos v1.12 or newer. Talos v1.12 introduced this multi-document model; older
nodes continue to receive the legacy machine configuration shape while they
are upgraded. If the version probe cannot reach a node, legacy mode is used
conservatively. Reconciliation after the node upgrade then switches it to the
multi-document patches.

This is implemented in
[`templates/CrossplaneOps/ClusterNodeComposition.yaml`](templates/CrossplaneOps/ClusterNodeComposition.yaml), using the
[Talos machine configuration apply resource](https://github.com/siderolabs/terraform-provider-talos/blob/main/docs/resources/machine_configuration_apply.md).

This chart is exercised by a real two-site, multi-province private cloud rather
than only a virtual test environment. See
[CoRE deployment environment](ENVIRONMENT.md) for the physical fleet, network
fabric, operator workflow, availability experience, and intended failure
domains. Those details describe this deployment and are not chart
prerequisites.

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

## Talos kernel modules and binfmt

Talos nodes that host containerized multi-architecture builds need the signed
`binfmt_misc` kernel module and the matching
[`siderolabs/binfmt-misc` system extension](https://factory.talos.dev/). The
DC1 Forgejo runner is pinned to `srv1` and `srv3`; their node claims declare
both settings in
[`templates/prod/DC1`](templates/prod/DC1/). The ClusterNode Composition passes
the extension to the Talos Image Factory and the module into the generated
machine configuration, so changing either setting requires the normal
image-generation and Talos upgrade/reboot flow.

After reconciliation, verify the generated machine configuration and confirm
that `/proc/sys/fs/binfmt_misc` is mounted on both nodes before retrying a
QEMU-dependent workflow. A successful `docker/setup-qemu-action` run is the
end-to-end check; the action installs QEMU through a privileged
`tonistiigi/binfmt` container. See Talos' [kernel module configuration
reference](https://docs.siderolabs.com/talos/v1.13/reference/configuration/v1alpha1/config)
and the [Docker Setup QEMU action](https://github.com/docker/setup-qemu-action)
for the upstream behavior.

Cilium agent configuration can be overridden for a cluster with
`Cluster.spec.networks.cni.cilium.configOverrides` and for an individual node
with `ClusterNode.spec.overrides.cni.cilium.configOverrides`. Both fields are
maps of Cilium configuration keys to string values. The node map is merged on
top of the cluster map and rendered as a `CiliumNodeConfig` selected by the
node's `kubernetes.io/hostname` label. `networkInterfaces`, when set on the
node, is rendered as the Cilium `devices` override.

## Talos Longhorn volumes

Configure a node's Longhorn storage volume with
`ClusterNode.spec.storage.longhornDisks`. Set `grow: true` to allow the Talos
user volume to expand to the available size of its selected disk; when omitted,
the current default remains `false`.

```yaml
spec:
  storage:
    longhornDisks:
      - grow: true
        maxSize: '900GB'
        selector:
          wwid: 'naa.5000c50090ca23fa'
```

This becomes a Talos `UserVolumeConfig` used for the Longhorn mount. Volume
provisioning settings are generally applied when the volume is first
provisioned; review the [Talos user volume documentation](https://www.talos.dev/v1.12/talos-guides/configuration/disk-management/user/)
before changing an existing node.

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

See [CoRE deployment environment](ENVIRONMENT.md) for deployment context,
[Bare Metal Provisioning](BMPS.md) for the provisioning lifecycle, and
[TODO](TODO.md) for known gaps.
