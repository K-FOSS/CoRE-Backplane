# TODO

This backlog records known gaps in the Cluster chart and Bare Metal
Provisioning System. Items are grouped by priority rather than intended
implementation order.

## P0: safety and correctness

- [ ] Replace unconditional
  `gotemplating.fn.crossplane.io/ready: "True"` annotations with readiness
  checks based on each composed resource's actual conditions.
- [ ] Define and test deletion/reclaim behavior for clusters, nodes,
  Tinkerbell workflows, hardware reservations, provider configurations, and
  generated secrets.
- [ ] Add a hardware reservation/locking mechanism that prevents two
  `ClusterNode` claims from selecting the same physical host.
- [ ] Validate installation-disk selection before allowing a destructive
  workflow.
- [ ] Add explicit safeguards, audit metadata, and a documented approval path
  for `wipeOnReboot` and future reprovision operations.
- [ ] Ensure credentials and generated kubeconfig/Talos configuration secrets
  have explicit ownership, rotation, retention, and least-privilege policies.
- [ ] Define recovery behavior for partially completed workflows and make
  retries idempotent.

## P1: API and reconciliation

- [ ] Add Composition tests for missing/partial observed status so templates
  cannot dereference absent fields during early reconciliations.
- [ ] Add OpenAPI and CEL validation for addresses, CIDRs, version strings,
  sysctl names, duplicate sysctl entries, mutually exclusive settings, and
  required fields for each compute/control-plane mode.
- [ ] Publish complete `Cluster`, `ClusterNode`, and `Tenant` API examples and
  document which fields are stable, experimental, or deprecated.
- [ ] Establish a versioning and conversion strategy before promoting the
  XRDs beyond `v1alpha1`.
- [ ] Refactor the large inline Go templates into smaller, testable
  Composition functions or reusable template fragments.
- [ ] Remove hard-coded namespaces, provider configuration names, registry
  endpoints, labels, and environment assumptions.
- [ ] Report useful conditions on claims: hardware selected, image ready,
  workflow running, Talos reachable, and node joined.
- [ ] Replace free-form or deeply nested danger/override structures with
  smaller typed APIs and clear defaults.
- [ ] Finish tenant integration and propagate tenant ownership consistently to
  all generated resources.

## P1: BMPS inventory and networking

- [ ] Integrate IPAM and NetBox so addresses, prefixes, VLANs, interfaces, and
  hardware inventory are allocated from a source of truth instead of repeated
  in claims.
- [ ] Define how hardware is enrolled, labeled, tested, quarantined, released,
  and retired.
- [ ] Validate that hardware selectors resolve to exactly one eligible host
  before starting a workflow.
- [ ] Add preflight checks for DHCP/PXE reachability, Tinkerbell endpoints,
  registry access, NTP, control-plane reachability, and installation disks.
- [ ] Define support and validation for bonded, bridged, VLAN, SR-IOV, IPv6,
  and multi-NIC configurations.
- [ ] Finish the MSTP/system-container work and document when it is required.
- [ ] Make workflow timeout, retry, and cancellation policies configurable and
  observable.
- [ ] Add a supported deprovision/reimage workflow that scrubs state and
  safely returns hardware to inventory.

## P2: lifecycle and upgrades

- [ ] Automate Talos, Cluster API provider, Tinkerbell provider, Terraform
  provider, and chart dependency updates with Renovate or equivalent tooling.
- [ ] Add compatibility checks for Kubernetes, Talos, CAPI, Tinkerbell, and
  provider versions.
- [ ] Define cluster and node upgrade sequencing, including control-plane
  quorum, worker rollout, rollback, and one-off node version overrides.
- [ ] Decide whether Kamaji, Talos control plane, and alternative compute types
  are separate Composition selections instead of branches in one mixed
  implementation.
- [ ] Implement the documented behavior for removing Talos system extensions,
  not only adding them.
- [ ] Define backup and restore procedures for Kamaji datastore state,
  Crossplane state, generated secrets, and hardware inventory.

## P2: testing and delivery

- [ ] Add CI that runs `helm dependency build`, `helm lint`, and
  `helm template` with representative values.
- [ ] Validate rendered resources with kubeconform against Kubernetes,
  Crossplane, CAPI, Tinkerbell, and Talos provider schemas.
- [ ] Unit-test Go-template rendering for empty, minimal, dual-stack,
  control-plane, worker, sysctl-override, and hardware-override cases.
- [ ] Add an ephemeral or virtual BMPS integration test covering claim
  creation through workflow completion and node registration.
- [ ] Add upgrade tests that render the previous and current chart versions
  and detect breaking XRD/schema changes.
- [ ] Package example claims as opt-in examples or move them out of the
  default template path so installing the chart cannot create
  environment-specific production resources unexpectedly.

## P3: observability and operator experience

- [ ] Generate the compute and switch inventory in `ENVIRONMENT.md` from
  NetBox/IPAM so production, spare, quarantined, and retired assets cannot
  silently diverge from documentation.
- [ ] Report installed, powered, Kubernetes-ready, failover-reserved, and
  unavailable CPU/memory capacity separately.
- [ ] Define service-level indicators for Authentik login, Eclipse Che
  workspace startup, management access, Kubernetes APIs, reconciliation, and
  bare-metal provisioning.
- [ ] Define the critical-service behavior expected during a single-site
  outage, including active/active, active/passive, and restore-on-demand
  services.
- [ ] Test and document an emergency access path that does not depend on
  Authentik, Eclipse Che, or the primary Kubernetes cluster.
- [ ] Add dashboards and alerts for reconciliation errors, hardware
  availability, workflow duration/failure, PXE failures, and nodes that fail
  to join.
- [ ] Emit structured events containing cluster, node, hardware, workflow, and
  reconciliation identifiers.
- [ ] Document log locations and diagnostic commands for every provisioning
  boundary.
- [ ] Add a readiness/status summary suitable for a Backoffice or self-service
  interface.
- [ ] Provide a support bundle command that collects relevant resources,
  conditions, events, and controller logs while redacting secrets.
- [ ] Document SLOs for provisioning time, retry behavior, and recovery from
  management-plane outages.
