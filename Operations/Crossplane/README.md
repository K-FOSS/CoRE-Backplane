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
- A memory-backed plugin cache capped at `4Gi`. The cache is ephemeral and is repopulated after a provider restart.

The upstream [Terraform provider documentation](https://github.com/crossplane-contrib/provider-terraform#further-configuration) explains that polling runs `terraform plan` for existing Workspaces, while changes to a Workspace specification are reconciled immediately. It also notes that a reconcile rate above one can use a similar number of CPUs. This configuration therefore leaves immediate application provisioning event-driven, reduces repeated drift scans, and caps a YVR/YXL burst at eight CPUs. The cap is above the observed YVR peak of about 1.4 CPUs and leaves node capacity for Crossplane, GitOps, and other workloads. The `30m` poll interval only changes how quickly out-of-band drift is detected; it does not wait 30 minutes to reconcile a changed Workspace specification.

The plugin cache directory is mounted at `/tf/plugin-cache` and selected with `TF_PLUGIN_CACHE_DIR`. Keep the memory volume limit below the container memory limit so Terraform processes retain room for plan and apply working memory. A provider restart loses the cache but not remote Terraform state; Workspaces must use their configured remote state for durable state.

## Configuration and data flow

Applications create Crossplane claims and composed managed resources. Terraform-backed managed resources reference `ProviderConfig` objects, which select the provider credentials and Terraform backend. The provider turns Workspace specification changes into Terraform operations and periodically checks existing Workspaces for external drift. Connection outputs are published through the resource's configured Kubernetes Secret reference; never inspect or print Secret values while troubleshooting.

## Operations and verification

After changing the provider runtime configuration, reconcile only the affected Crossplane child applications. Confirm the `DeploymentRuntimeConfig` arguments, resource requests and limits, cache mount, and resulting provider deployment. Observe provider CPU and memory alongside node utilization, then verify that new Workspace changes begin reconciling promptly and that existing Workspace conditions settle.

Useful read-only checks include:

```sh
kubectl --context logged-user -n crossplane-system-prod get deploymentruntimeconfig provider-terraform -o yaml
kubectl --context logged-user -n crossplane-system-prod get deployment -l pkg.crossplane.io/provider=provider-terraform
kubectl --context logged-user -n crossplane-system-prod top pods
kubectl --context logged-user get workspaces.tf.upbound.io -A
```

Use the target cluster context when checking YXL or another cluster. Provider readiness alone does not prove each Workspace succeeded; inspect Workspace `Ready` and `Synced` conditions and diagnose failed Terraform runs before retrying them.

## Security and recovery

The Terraform runtime may receive provider credentials through referenced Secrets and may access network services while initializing modules and providers. Keep credentials in Secret references, retain TLS mounts injected by the installed Crossplane package runtime, and do not copy Secret values into logs or manifests. To roll back a runtime change, publish a corrective Git commit and reconcile the affected child application; this rolls the provider deployment and clears its in-memory plugin cache, but does not delete Terraform-managed infrastructure.
