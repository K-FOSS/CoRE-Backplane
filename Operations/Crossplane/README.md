# CoRE-Backplane Operations/Crossplane Stack

This stack installs Crossplane, provider packages, functions, and provider configurations for CoRE. It is owned by the [Crossplane ApplicationSet](../../Apps/Infra/Crossplane/Crossplane.yaml) and is part of the [Operations deployment set](../README.md).

The stack uses the official [Crossplane Helm chart](https://github.com/crossplane/crossplane/tree/main/cluster/charts/crossplane) and follows the upstream [Crossplane installation guide](https://docs.crossplane.io/latest/software/install/).

## Ownership and targets

The ApplicationSet selects registered clusters with tenant `core.mylogin.space` and renders [this deployment](.). It injects the cluster name, domain, environment, and Crossplane namespace. It sets a Terraform reconcile rate of `8` and explicit resources on YVR (`core-home1-talos-prod`) and Talos DC1/YXL (`core-dc1-talos-prod`). Other targets use the chart default rate of `1` and receive no added CPU or memory requests or limits; this keeps the legacy DC1 runtime's lower concurrency intact.

The provider and its runtime settings are declared in [`TerraformProvider.yaml`](templates/Providers/Terraform/TerraformProvider.yaml). Argo CD applies the `DeploymentRuntimeConfig` before the Terraform `Provider` through the provider's sync wave. A change to the runtime configuration rolls the provider deployment; it does not replace Terraform-managed external resources.

## Terraform provider runtime and workload

The runtime configuration sets:

- `--sync=2h` and `--poll=30m` for periodic resynchronization and external drift checks.
- On YVR and YXL, `--max-reconcile-rate=8`, allowing a burst rate for new or changed Workspaces while bounding provider CPU use. Other targets use rate `1` unless the fleet owner changes the selection in the ApplicationSet.
- On YVR and YXL, a `1 CPU` and `1Gi` memory request, with `8 CPU` and `8Gi` limits. The Terraform provider runs Terraform subprocesses, so its resource use can exceed the controller's steady-state usage during plans and applies.
- No shared Terraform plugin cache. Multiple Workspace reconciles can run Terraform initialization at once, and HashiCorp documents that a shared plugin cache is not concurrency-safe.

The upstream [Terraform provider documentation](https://github.com/crossplane-contrib/provider-terraform#further-configuration) explains that polling runs `terraform plan` for existing Workspaces, while changes to a Workspace specification are reconciled immediately. It also notes that a reconcile rate above one can use a similar number of CPUs. This configuration therefore leaves immediate application provisioning event-driven, reduces repeated drift scans, and caps a YVR/YXL burst at eight CPUs. The cap is above the observed YVR peak of about 1.4 CPUs and leaves node capacity for Crossplane, GitOps, and other workloads. The `30m` poll interval only changes how quickly out-of-band drift is detected; it does not wait 30 minutes to reconcile a changed Workspace specification.

Terraform installs provider plugins in each Workspace's working directory. The shared cache stays disabled because concurrent `terraform init` operations have undefined behavior when they write to it; see HashiCorp's [Terraform CLI plugin cache documentation](https://developer.hashicorp.com/terraform/cli/config/config-file#provider-plugin-cache). This trades repeated downloads for safe concurrent configuration. If registry traffic becomes material, use a provider installation mirror or another design with single-writer cache semantics. The provider container remains bounded at `8Gi` so Terraform subprocesses retain working memory during plans and applies.

## Configuration and data flow

Applications create Crossplane claims and composed managed resources. Terraform-backed managed resources reference `ProviderConfig` objects, which select the provider credentials and Terraform backend. The provider turns Workspace specification changes into Terraform operations and periodically checks existing Workspaces for external drift. Connection outputs are published through the resource's configured Kubernetes Secret reference; never inspect or print Secret values while troubleshooting.

### Garage resources composed by User claims

On `core-dc1-talos-prod`, Crossplane composes the Garage `GarageBucket` and
`GarageKey` resources requested by the `mylogin.space` User Composition. Its
controller needs cluster-wide `get`, `list`, and `watch` access because its
composed-resource cache lists these namespaced kinds at cluster scope. The
additional writer Role grants `create`, `update`, `patch`, and `delete` only in
`core-prod`, where Garage-backed User claims are allowed. The
[Crossplane RBAC model](https://docs.crossplane.io/latest/concepts/pods/#crossplane-clusterroles)
and [Garage resource reference](https://rajsinghtech.github.io/garage-operator/reference/custom-resources/)
describe the relevant controllers and resource kinds.

The Crossplane ApplicationSet enables this narrow permission set only for
`core-dc1-talos-prod`; other clusters render no Garage RBAC resources. The
Garage operator remains responsible for reconciling bucket and key status.
Verify the read grant is available to the Crossplane service account, that
Garage writes are allowed in `core-prod`, and that writes are denied in other
namespaces:

```sh
kubectl --context core-dc1-talos-prod auth can-i list garagebuckets.garage.rajsingh.info --as=system:serviceaccount:crossplane-system-prod:crossplane
kubectl --context core-dc1-talos-prod auth can-i create garagekeys.garage.rajsingh.info -n core-prod --as=system:serviceaccount:crossplane-system-prod:crossplane
kubectl --context core-dc1-talos-prod auth can-i create garagekeys.garage.rajsingh.info -n default --as=system:serviceaccount:crossplane-system-prod:crossplane
```

## Authentik provider upgrades

The shared [`authentik` Terraform ProviderConfig](templates/Providers/Terraform/Authentik/AuthentikTerraformConfig.yaml) pins `goauthentik/authentik` for all Workspaces that reference it and sets `pluginCache: false`. Each Workspace maintains its own Terraform dependency lock. Updating the pin alone does not upgrade an existing lock; Terraform initialization fails with a locked-version mismatch until that Workspace runs [`terraform init -upgrade`](https://developer.hashicorp.com/terraform/cli/commands/init#upgrade).

For a provider upgrade, verify the selected [Authentik Terraform provider release](https://github.com/goauthentik/terraform-provider-authentik/releases) and its compatibility with the deployed server, then keep the version constraint exact. Apply `forProvider.initArgs: ['-upgrade']` temporarily to every Authentik Workspace source, including composed `User` Workspaces and consumer repositories. Reconcile in scoped cohorts and monitor Workspace `Synced` and `Ready` conditions; provider initialization can also update other unpinned providers required by a module. After all existing Workspaces have initialized successfully and their plans are healthy, remove the temporary argument and reconcile the same sources. New Workspaces use the exact provider constraint without needing an upgrade flag.

An Authentik provider version change can expose real plan differences. Review those as Terraform drift or provider/API compatibility issues; a successful `init` alone is not evidence that managed Authentik objects remained unchanged. Keep the remote Kubernetes Terraform state backend and Workspace identities stable throughout the upgrade.

## Operations and verification

After changing the provider runtime configuration, reconcile only the affected Crossplane child applications. Confirm the `DeploymentRuntimeConfig` arguments and resource requests and limits, then observe provider CPU and memory alongside node utilization. Verify that new Workspace changes begin reconciling promptly and that existing Workspace conditions settle.

Useful read-only checks include:

```sh
kubectl --context logged-user -n crossplane-system-prod get deploymentruntimeconfig provider-terraform -o yaml
kubectl --context logged-user -n crossplane-system-prod get deployment -l pkg.crossplane.io/provider=provider-terraform
kubectl --context logged-user -n crossplane-system-prod top pods
kubectl --context logged-user get workspaces.tf.upbound.io -A
```

Use the target cluster context when checking YXL or another cluster. Provider readiness alone does not prove each Workspace succeeded; inspect Workspace `Ready` and `Synced` conditions and diagnose failed Terraform runs before retrying them.

## Security and recovery

The Terraform runtime may receive provider credentials through referenced Secrets and may access network services while initializing modules and providers. Keep credentials in Secret references, retain TLS mounts injected by the installed Crossplane package runtime, and do not copy Secret values into logs or manifests. To roll back a runtime change, publish a corrective Git commit and reconcile the affected child application; this rolls the provider deployment but does not delete Terraform-managed infrastructure.
