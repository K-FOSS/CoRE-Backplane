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

Direct `kubectl` changes are emergency actions. If used, record them and either
represent them in Git or deliberately remove them after recovery.

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
