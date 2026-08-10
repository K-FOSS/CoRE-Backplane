# CoRE Backplane agent guidance

This file applies to the entire repository. More specific `AGENTS.md` files may
add rules for a subtree, but must not weaken these repository-wide requirements.

## Repository and deployment model

- Treat this repository as the live, site-specific desired state for a
  multi-site private cloud, not as a generic Kubernetes example repository.
- Start deployment investigations in `Apps/`. Identify the owning Argo CD
  ApplicationSet, its cluster selectors, injected values, renderer settings,
  and every target cluster before changing an implementation directory.
- A Lovely deployment directory may combine Helm, Kustomize, raw YAML, remote
  resources, patches, and ApplicationSet-injected values. Inspect the complete
  rendering unit; never infer its deployed resources from `templates/` alone.
- Follow reconciliation through every responsible layer: Argo CD, Kubernetes,
  operators, Crossplane providers/functions, Terraform Workspaces, Cluster
  API, Tinkerbell, Talos, or external services. `Synced`, an accepted manifest,
  or a composite `Ready` condition alone does not prove the outcome is healthy.
- Normal changes flow through Git and Argo CD. Direct live-cluster mutations
  are incident actions only and must be recorded and reconciled back to Git or
  deliberately removed afterward.

## Documentation

- Documentation for every external chart, image, plugin, controller, provider,
  API, remote manifest, or other dependency must include direct links to its
  authoritative upstream documentation.
- For plugins and nested monorepo components, link to the closest
  component-specific README and its repository or source subdirectory. Do not
  rely only on a homepage, search page, registry page, or monorepo landing page
  when more specific documentation exists.
- Put links next to the component or behavior they support. Use descriptive
  Markdown link text rather than bare URLs and keep links valid when rendered
  from the document's repository location.
- Describe current behavior separately from desired behavior. Manifests and
  observed controller state are authoritative when documentation differs.
- Document prerequisites, ownership, target selection, reconciliation/data
  flow, values, generated resources, operational verification, rollback or
  deletion behavior, and non-obvious security or recovery effects.
- Keep commands and examples aligned with current templates and representative
  ApplicationSet-injected values. Clearly identify literals, mutable upstream
  references, unsafe examples, and values that are not actually consumed.
- Update the nearest relevant README or runbook when a change alters an
  operator workflow, dependency, recovery step, public endpoint, access model,
  or destructive behavior.

## Secrets and identity

- Never add, decode, print, log, document, or commit production credentials,
  tokens, private keys, Secret values, or private provider configuration.
- Prefer Vault/CoreVault references, ExternalSecret, PushSecret, and
  Crossplane connection secrets. A reference stored in Git is not itself a
  secret, but still review rendered output for literal or generated disclosure.
- Do not introduce deployable placeholder/default passwords. New deployments
  should fail validation when required secret references are absent.
- Treat Authentik groups, Kubernetes RBAC subjects, gateway security policies,
  OIDC redirect URIs, provider scopes, and entitlement bindings as one access
  control path. Review coordinated changes for accidental privilege expansion
  or lockout.
- Preserve emergency access that does not depend on Authentik, Eclipse Che,
  public ingress/DNS, the primary cluster, Vault application credentials, or a
  single site.

## Dependency and supply-chain policy

- Pin Helm dependencies, images, remote Kustomize resources, operators, and
  downloaded tools to immutable versions or digests where supported. Avoid
  moving branches and `latest` tags unless their mutability is intentional and
  documented.
- Verify a version against the authoritative upstream chart index, repository,
  release, values, and migration notes before changing it. Do not infer current
  value keys or API compatibility from an older release.
- Review remote resources for mutability, availability, ownership, and trust;
  the custom renderer and remote fetches are part of the supply chain.
- `Chart.lock` and vendored `charts/` directories are ignored. Resolve them
  locally for validation, but do not force-add generated dependency artifacts.
- Treat `setup.sh` as a convenience rather than a trusted reproducible
  bootstrap until moving downloads are pinned and checksums are verified.

## Safe infrastructure changes

- Before modifying physical provisioning, resolve the exact site, cluster,
  machine, hardware identity, installation disk, network, workflow state, and
  deletion/retry behavior. Rendering success is not a safety check.
- Never restart or retry an unidentified Tinkerbell/Talos provisioning failure;
  doing so may repeat destructive disk operations.
- Review namespaces, selectors, ownership references, finalizers, deletion
  policies, Argo CD preserve behavior, sync waves, and replacement semantics
  before changing resource identity or lifecycle fields.
- Preserve bootstrap and recovery ordering. Do not make recovery of a service
  depend solely on credentials or infrastructure that the same service must
  create.
- Avoid broad fleet resyncs during an unknown control-plane, network, storage,
  identity, or secret failure.

## Implementation and validation

- Keep changes narrowly scoped and preserve unrelated worktree edits. Do not
  reformat, revert, stage, or include another author's changes.
- Prefer values-driven templates for environment-specific behavior. Retain a
  literal only for a deliberate compatibility reason and document it.
- Validate every parser boundary touched by a change, including Helm templates,
  Kustomize output, Crossplane Go templates, embedded Terraform HCL, scripts,
  Talos configuration, and Kubernetes YAML.
- For Helm/Lovely changes, resolve dependencies, run `helm lint`, render with
  representative values and injected layers, and inspect affected resources.
- Validate Kubernetes API versions and CRDs against the controllers installed
  on target clusters. Stable-looking API names are not evidence of support.
- Run `git diff --check` scoped to files changed for the task and review the
  final diff for secrets, private data, namespaces, selectors, privileges,
  deletion behavior, and physical impact.
- After reconciliation, observe downstream controller conditions and validate
  the user-facing workflow; pod readiness and Argo CD health are supporting
  evidence, not the entire health model.

