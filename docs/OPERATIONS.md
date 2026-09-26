# Operations and recovery

This document defines operating principles for CoRE Backplane. It is not yet a
complete disaster-recovery runbook; commands and verified recovery times must
be added as recovery procedures are exercised.

## Normal change path

1. Make a narrowly scoped Git change.
2. Render and validate the affected chart with the same value layers used by
   its ApplicationSet.
3. Review the resulting diff for namespaces, selectors, secrets, privileges,
   deletion behavior, and physical impact.
4. Commit and push through the normal repository workflow.
5. Reconcile the owning Argo CD application.
6. Observe the downstream controller—not only Argo CD—until the intended
   outcome is healthy.
7. Record any unexpected behavior or manual intervention.

Direct changes to managed workloads with `kubectl` are emergency actions. If
used, record them and either represent them in Git or deliberately remove them
after recovery. Read-only inspection, server dry runs, and requesting an Argo CD
Application sync with kubectl are part of the normal procedure below.

## Agent Git and Argo CD procedure

On 2026-09-26, the repository owner approved continuing the process used for the
[Valkey operator deployment](../Storage/Valkey/Operator/README.md), commit
`f6bf06660`. The standing authorization is recorded in
[AGENTS.md](../AGENTS.md#standing-git-and-reconciliation-authorization).
Agents may commit and push validated changes for the requested task and, when
deployment is requested, reconcile and verify them without a separate handoff
or repeated permission question. A narrower instruction from the user overrides
this authorization. Permission to publish a change is not permission to include
other work or perform unrelated deployment, deletion or incident actions.

### Prepare and validate

1. Start with the owning ApplicationSet in `Apps/`. Identify the entire render
   unit, injected values, selectors, every actual target registration, dependency
   controllers, and current resource ownership. Read cluster registration names
   and labels without printing their Secret data.
2. Inspect the worktree, index, current branch, remote, and unpublished commits.
   Record which files/hunks belong to this task. Preserve all unrelated work,
   including edits from earlier requests that have not been published.
3. Verify upstream releases, value keys, API requirements, image availability
   and migration behavior. Pin dependencies. Review access scope, lifecycle,
   finalizers, persistence and legacy resources before implementation.
4. Render every parser boundary and the complete deployment with representative
   injected layers. Resolve Helm dependencies locally, lint, inspect generated
   resources, and check supported APIs on the targets. Use server dry runs where
   useful; they validate admission without persisting the resources. Follow the
   [Kubernetes dry-run behavior](https://kubernetes.io/docs/reference/using-api/api-concepts/#dry-run),
   and do not submit or print production Secret values.
5. Review the task diff and run scoped whitespace checks. For an isolated
   operator, verify watch scope, RoleBinding references, pinned images and CRD
   ordering as well as the absence of unintended instances or credentials.

### Publish only the reviewed change

Fetch the intended remote branch and inspect the entire commit range that the
push would publish, not only the latest commit. Stage explicit task paths or
hunks, then review the staged diff and its file list. A path-limited commit is
safe only when the selected paths contain no unrelated edits. Do not disturb
another author's staged work. Use an isolated worktree based on the remote
branch when the shared index, mixed file edits, or existing local commits make
the outgoing change ambiguous.

Use an explicit destination and a normal fast-forward
[Git push](https://git-scm.com/docs/git-push). This repository currently publishes
desired state to `origin/main`; confirm that remains the intended destination
for the task. Do not force-push, discard work, rewrite unrelated commits, or
bypass branch protections. If the remote advances, incorporate the change in
the isolated task branch and repeat affected validation before publishing. Use
a PR when repository protection or the user requires one.

### Reconcile through Argo CD

Record the full published commit SHA and sync that revision. Inspect any
existing operation first; do not overwrite an active operation belonging to
another change. For a new ApplicationSet, sync only that resource in the Apps
parent, wait for its generated applications, verify their target selection,
then sync only the affected applications. Leave pruning disabled unless removal
is part of the reviewed task and its lifecycle effects are understood.

[Argo CD resource-selective sync](https://argo-cd.readthedocs.io/en/stable/user-guide/selective_sync/)
skips hooks and does not create the normal sync history entry. Use it on a
parent only when the selected resource does not require those hooks; record the
revision and selected resources for recovery. Sync the affected child application
normally when its hooks or waves are needed. Review
[sync phases and waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
and avoid broad fleet reconciliation.

Use the Argo CD CLI/API, or the documented
[Application operation through kubectl](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-kubectl/).
An operation requests the controller to apply Git desired state; it does not
substitute direct workload mutation for GitOps. The Valkey deployment used a
JSON patch file with `operation.sync.revision` set to the published full SHA,
`prune: false`, and an explicit resource selector for the parent ApplicationSet.
The two child applications then received revision-scoped sync requests without
a resource filter. No controller workload was directly applied with kubectl.

### Diagnose, verify and report

Observe the operation for the requested revision, each responsible controller,
and the user-facing outcome. Check CRD establishment, controller startup,
downstream conditions and effective RBAC where relevant. Check connection Secret
key names and references without printing values. For operator-only installation,
healthy controllers and established CRDs are the intended outcome; do not create
an unrequested database or claim that an application migration was validated.

If reconciliation fails, inspect task messages and downstream conditions before
retrying. In the Valkey deployment, the initial operations failed while Argo CD
reported the newly installed CRDs as not established. Both clusters subsequently
showed `Established=True`; a scoped retry of the same commit completed. This is
evidence for that diagnosed retry, not a general instruction to retry CRD or
provisioning failures. Replays that could erase disks, delete data, replace
resources, or repeat an unidentified external operation need separate assessment
and specific authorization when outside the task's approved scope.

Rollback normally means publishing a scoped corrective or revert commit and
reconciling it through the same owners. Assess schema and data compatibility
first; Git reversal alone cannot restore data. Direct incident mutations remain
subject to the existing incident record and reconciliation requirements.

Report the commit, target clusters/applications, checks actually performed,
controller and workflow results, limitations and any blockers. Distinguish
published, synced and verified states. Documentation-only commits need no live
sync. If platform approval review blocks an action, identify the rejected action
and reason; do not treat this standing authorization as bypassing that control.

## Health model

For a deployment to be healthy:

```text
Git desired state is correct
  AND Argo CD rendered the intended manifests
  AND Kubernetes accepted the manifests
  AND each responsible controller reconciled successfully
  AND the service works from the user's perspective
```

For Crossplane and bare-metal resources, additionally verify:

- Claim and composite conditions.
- Function and provider health.
- Managed `Object` and `Workspace` conditions.
- CAPI cluster/machine conditions.
- Tinkerbell hardware and workflow status.
- Talos and Kubernetes node health.

Some existing Compositions mark resources ready unconditionally. Until that is
removed, composite readiness is supporting evidence rather than proof.

## Emergency access

Maintain an access path that does not depend on:

- Authentik.
- Eclipse Che.
- Public ingress or public DNS.
- The primary Kubernetes cluster.
- Vault application credentials.
- A single site's switching or carrier connection.

Emergency access may include out-of-band server management, switch console
access, break-glass Kubernetes credentials, CoreVault bootstrap material, and
an independently stored copy of the relevant runbooks. Store and audit those
credentials outside the systems they are intended to recover.

Test emergency access periodically. A credential that has not been used since
several certificate, firmware, routing, or identity changes is not a reliable
recovery mechanism.

## Recovery priorities

During an outage:

1. Preserve evidence and determine the failure domain.
2. Establish safe management access.
3. Stop automated reconciliation only when it is actively worsening the
   incident; record what was paused.
4. Restore power, network, DNS, storage, and API prerequisites.
5. Restore bootstrap secrets and controllers.
6. Restore data-bearing services before stateless dependants.
7. Re-enable reconciliation in dependency order.
8. Validate user journeys, not merely pod readiness.

Avoid bulk re-syncing every Argo CD application during an unknown control-plane
or secret failure. That can turn a contained fault into simultaneous
reconciliation across the fleet.

## Bootstrap dependency notes

The intended high-level bootstrap chain is:

```text
network and management access
  -> bootstrap Kubernetes cluster
  -> Argo CD and custom renderer
  -> CoreVault bootstrap credential
  -> External Secrets
  -> storage/databases and Vault
  -> Authentik and platform credentials
  -> Crossplane/providers/functions
  -> clusters and ordinary applications
```

The existing secret documentation describes manually introducing the
CoreVault token. Never place the real token in a shell history, repository,
ticket, or shared transcript. Prefer a protected input method and rotate the
credential after bootstrap when supported.

## Backup domains

Back up and restore-test each domain according to its consistency model:

| Domain | Examples | Recovery concern |
| --- | --- | --- |
| Git | Desired state and documentation | Repository availability, protected history, and deploy keys. |
| Kubernetes API | CRDs and cluster-scoped/namespaced resources | Ordering, generated resources, and controller compatibility. |
| Persistent volumes | Application filesystem state | Snapshot consistency and site/storage failure. |
| Databases | PostgreSQL, MySQL, MongoDB | Transaction-consistent native backups and point-in-time recovery. |
| Object storage | S3 data and backup targets | Off-site copies, credentials, retention, and immutability. |
| Vault/Consul | Secrets and storage backend | Unseal/bootstrap material and quorum. |
| Crossplane | Claims, managed resources, connection secrets, Terraform state | External-resource ownership and state reconciliation. |
| Network devices | Switch/router configuration and firmware | Offline access and hardware replacement. |
| Bare-metal inventory | NetBox/Tinkerbell hardware and allocation state | Correct machine identity and prevention of destructive reuse. |

A successful backup job is not proof of recoverability. Record the date,
scope, result, and measured duration of restore tests.

## Site failure

YVR and YXL are separate site failure domains. Each site has one Nexus
92160YC-X rather than a locally redundant Nexus pair; YXL also contains the
N3K-C3172TQ-10GT. Treat failure of a site's primary switching path separately
from total loss of the site.

During a site failure, determine:

- Whether routing converged and management access remains.
- Which quorum members and storage replicas were lost.
- Whether the surviving site has reserved capacity for critical services.
- Whether DNS, identity, secret, and certificate dependencies remain
  reachable.
- Whether backup storage is independent of the failed site.
- Which services are intended to remain active and which are
  restore-on-demand.

Do not claim site-level high availability solely from cross-site hardware
placement. Measure each critical service's dependency graph.

## Bare-metal incident boundaries

Before restarting a provisioning workflow, identify whether failure occurred
in:

1. Hardware selection or reservation.
2. DHCP/PXE.
3. Image generation or download.
4. Tinkerbell workflow execution.
5. Disk selection or installation.
6. Talos configuration and bootstrap.
7. Control-plane networking.
8. Kubernetes node registration.

Re-running an unidentified failure may repeat destructive disk operations. See
[the BMPS runbook](../Operations/Clusters/BMPS.md).

## Availability measurement

Current availability observations are informal. Establish service-level
indicators for:

- Authentik login.
- Eclipse Che workspace startup.
- DNS and gateway reachability.
- Kubernetes API availability.
- Crossplane reconciliation delay and failure.
- Remote and out-of-band management access.
- Bare-metal provisioning success/duration.
- Backup and restore success.

Separate planned maintenance, total outage, partial degradation, and
single-service failure. Aggregate platform uptime can otherwise hide failures
in the user journeys that matter.

## Incident record template

Record at least:

```text
Start/end time:
Detected by:
Affected sites/clusters/services:
User-visible impact:
Failure domain:
Immediate cause:
Contributing conditions:
Automated actions:
Manual actions:
Data loss or security impact:
Recovery validation:
Follow-up owner/date:
```

For a solo-operated platform, concise incident notes are a substitute for the
memory that will otherwise be lost between rare failures.
