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

## Standing Git and reconciliation authorization

- The repository owner authorized this workflow on 2026-09-26 after the Valkey
  operator deployment. For requested implementation work, agents may validate,
  create narrowly scoped commits, and push them to the repository's intended
  branch without asking again. For deployment requests, continue through
  scoped Argo CD reconciliation and downstream verification. Do not default
  to handing Git operations back to the user. A request to review only, leave
  changes uncommitted, use a PR, or defer deployment overrides this allowance.
- Apply this authorization only to the requested task. Preserve unrelated
  staged and unstaged edits, untracked files, and unpublished commits. Inspect
  the index and outgoing commit range before publishing; use an isolated
  worktree when needed to avoid including unrelated work. Never use blanket
  staging, force-push, or rewrite another author's history under this allowance.
- Confirm the intended remote and branch, fetch before publishing, review the
  exact outgoing diff, and use a normal fast-forward push. Respect branch
  protections and required checks; use the required PR workflow when applicable.
- Keep published history immutable. Never amend or rebase a commit that may
  have reached a remote; publish corrections as follow-up commits. After
  fetching, confirm the intended upstream tip is an ancestor of `HEAD` and
  review the complete outgoing range to ensure it contains only this task's
  commits. If the upstream is not an ancestor of `HEAD`, follow the
  canonical-checkout procedure in `docs/OPERATIONS.md`; do not force-push or
  rewrite published history.
- Use the canonical workspace's configured Git authentication and askpass flow.
  Never print, read, copy, or replace stored credentials, disable askpass, or
  switch credential helpers to work around a missing prompt. If the configured
  askpass integration cannot communicate, stop retrying, preserve outgoing
  commits, and report that the workspace authentication prompt must be restored.
- Reconcile the reviewed, published commit through the owning Argo CD layers.
  Select only the necessary parent ApplicationSet resources and affected child
  applications. Inspect sync hooks and dependency ordering before choosing
  resource-selective sync; it skips hooks. Do not broadly resync the fleet or
  enable automated sync as an incidental change.
- Requesting an Argo CD refresh or sync through its CLI/API or an Application
  `operation` using kubectl is permitted normal reconciliation. It is distinct
  from directly applying or modifying the managed workloads. Read-only cluster
  checks and non-persistent server dry runs are also permitted without a new
  user confirmation; existing secret-handling rules still apply.
- Diagnose failed reconciliation before retrying. A scoped retry of the same
  reviewed commit is permitted when the cause is understood and replay is safe.
  This does not authorize unidentified provisioning retries, destructive data
  actions, force/replacement syncs, bypassing protections, or broader incident
  mutations. Obtain specific authorization for actions outside the requested
  scope after preparing the concrete change and explaining its effects.
- Report the published commit, affected targets, actual verification results,
  material limitations, and any remaining blockers. Documentation-only changes
  do not require a cluster sync. Follow the detailed
  [Git and Argo CD operating procedure](docs/OPERATIONS.md#agent-git-and-argo-cd-procedure).

## Commit message conventions

- Write new commit subjects in Conventional Commit form:
  `type(scope): summary`. The two-year history most often uses `feat`,
  `chore`, and `fix`; `docs` and `test` are also established. Use a lowercase
  standard type that describes the change. Do not copy historical typos or
  nonstandard types such as `ffix`, `temp`, or `debug`.
- Apply casing by field: keep the type lowercase; preserve the established
  capitalization of scope components; write the summary in sentence case,
  starting with an uppercase word and preserving normal product names and
  acronyms. For example:
  `feat(Network.Base): Enable L2 announcements`. Do not lowercase the scope or
  force the summary to start lowercase.
- Include a useful summary after the colon that says what changed. Keep it
  concise and specific; summaries may use the repository's natural sentence
  style, but avoid placeholders such as `Fix`, `Tidy up`, or `Work on things`
  without the thing or outcome being identified. A commit body is optional;
  the subject must still make sense on its own. Add a body when rationale,
  operational impact, or other context needs more room.
- Use a scope that identifies the primary repository component or deployment
  layer. Scopes commonly use dotted component paths and preserve the
  component's capitalization. For the network platform stack, use
  `Network.Base` for implementation changes under `Network/Base/` and
  `Apps.Network.Base` for its fleet/ApplicationSet entry point under
  `Apps/Network/Base.yaml`. Use a narrower scope such as
  `Network.Base.Cilium` when that component is the focus.
- When one cohesive change intentionally spans components, list their scopes
  separated by commas, for example
  `feat(Apps.Network.Base, Network.Base): ...`. Keep the scope list limited to
  components actually changed. A primary scope is sufficient for routine
  coordinated edits when it clearly identifies the change.
- Use one subject for one cohesive change. Do not leave the type or scope out,
  and avoid bare subjects such as `fix` or `test` even though they appear in
  older history.

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

### Stack README structure and headings

- Title stack README files with `# CoRE-Backplane <path> Stack`, using the repository path and established component capitalization (for example, `# CoRE-Backplane Network/NATPuncher Stack`). For non-stack guides, use a concise title naming the component or operational purpose.
- Start with a short summary of what the stack does and link its owner (normally the ApplicationSet) and parent stack overview.
- Organize the body into clear, task-focused `##` sections. Cover ownership/targets/rendering, architecture or components, configuration and data flow, operations/verification, and security/recovery where relevant; include only sections that apply. Use `###` for topics within a section and do not skip heading levels.
- Keep headings specific to the content that follows. Avoid generic headings such as `Details` or `Miscellaneous`, and avoid turning every paragraph into a heading.
- Link repository files with relative Markdown links from the current document. Use descriptive link text; link the owner, related stack documentation, values/templates, and runbooks where they support the text. Use direct upstream links for external dependencies.
- Keep documentation focused on observed current behavior, then state desired behavior or TODOs separately. Align section order with the reader’s path from ownership and design through configuration to operation and verification.

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

## Shared application data services

- Treat the infrastructure PostgreSQL, MySQL, MongoDB, and site-local
  `dragonfly-core` deployments as shared platform services used by deployed
  applications, not as chart-private dependencies. Start changes at their
  fleet owners in `Apps/Storage/PSQL.yaml`,
  `Apps/Storage/Database/MySQL.yaml`, `Apps/Storage/Database/MongoDB.yaml`, and
  `Apps/Storage/Dragonfly/CoRE.yaml`, then trace every application consumer.
- Every deployed application service identity must be declared with the
  namespaced `User.mylogin.space/v1alpha1` claim provided by the `sso-user`
  Composition in `Operations/SSO/User`; do not create an unrelated database
  password or parallel identity path in an application chart. Keep the claim
  beside the consuming application, use its stable connection Secret, and
  review identity, database grants, buckets, and secret publication as one
  lifecycle.
- Do not infer database provisioning from fields merely accepted by the
  `User` XRD. The current Composition implements Authentik identity plus
  optional PostgreSQL and S3 resources; `spec.mysql` and `spec.mongodb` are
  currently schema-only. Extend and validate the Composition before relying
  on it to provision MySQL or MongoDB resources, and document current behavior
  separately from the intended shared model.
- Treat `Storage/Dragonfly/CoRE/README.md` as the allocation registry for
  shared Dragonfly logical databases. Every application that uses
  `dragonfly-core` must declare an explicit, unused database number where the
  client supports one and add or update the registry in the same change.
  Database `0` is legacy shared space, not the default allocation for a new
  consumer. Use a separate Dragonfly instance when credentials, capacity,
  lifecycle, recovery, or failure isolation must be independent.
- For application onboarding, changes, and removal, verify the `User` claim
  and composite, downstream provider resources, stable connection Secret,
  effective database grants, and any Dragonfly allocation. Removing a claim
  is not proof that external roles, databases, grants, buckets, or persisted
  Dragonfly data were deleted; inspect orphan and deletion policies explicitly.

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
- Prefer the pinned BJW-S common library chart over handwritten Kubernetes
  workload, Service, routing, persistence, ConfigMap, Secret, and NetworkPolicy
  resources when the library supports the required behavior. Use direct
  manifests for unsupported CRDs or when BJW-S cannot preserve required
  identity, lifecycle, ordering, or security semantics, and document the
  reason for the exception.
- In new or touched YAML, use single quotes for string scalars, including
  strings in flow sequences and mappings. Use double quotes only when YAML
  escape processing is required or a single-quoted value would be materially
  less clear. Quote numeric-looking identifiers so renderers preserve them as
  strings across YAML, templates, and generated JSON.
- As an exception to the general quoting rule, do not quote Kubernetes
  `apiVersion` or `kind` values. In Helm `Chart.yaml` files, do not quote
  `apiVersion`, `type: application`, the chart `version`, or dependency
  `version` values, or any env: or key/value YAML or related languages on the key/left side.
- Prefer values-driven templates for environment-specific behavior. Retain a
  literal only for a deliberate compatibility reason and document it.
- For every `Landing`/Forecastle-exposed service, add a
  `forecastle.stakater.com/appName` annotation with a friendly display name;
  do not rely on the generated resource name in the dashboard.
- Forecastle’s deployed instance name is `core`. To expose a service through
  Forecastle, add these annotations to the exposed `HTTPRoute` (or `Ingress`):
  `forecastle.stakater.com/expose: 'true'`,
  `forecastle.stakater.com/instance: 'core'`, and a friendly
  `forecastle.stakater.com/appName`. Add
  `forecastle.stakater.com/group` when the service belongs in a dashboard
  group such as `Tools` or `Security`; keep the route hostname and Gateway
  attachment valid as well.
- Routes intended to receive public DNS records must include the Kubernetes
  label `wan-mode: 'public'`. Site ExternalDNS selects public records using
  that label; a public hostname without it will not be published. Keep this
  label off private Authentik-only routes.
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
