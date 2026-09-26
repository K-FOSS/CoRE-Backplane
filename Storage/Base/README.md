# Storage Base chart

This chart deploys Longhorn and CoRE storage classes, UI routing and
authentication policy. It is owned by `Apps/Storage/Base.yaml`.

## Components

- Longhorn **1.12.1** manager, engine and supporting components, pinned through
  the [upstream Helm chart](https://github.com/longhorn/charts/tree/longhorn-1.12.1/charts/longhorn).
  See the [release notes](https://github.com/longhorn/longhorn/releases/tag/v1.12.1)
  and [versioned Helm values](https://longhorn.io/docs/1.12.1/references/helm-values/).
- Default and SSD-oriented storage classes.
- Deployment-specific non-redundant storage class.
- Authentik/security policy and HTTPRoute for the Longhorn UI.
- Longhorn backup `User` claims for local and Matrix-configured peer S3
  ProviderConfigs.

## Prerequisites

Nodes require supported disks/filesystems, mount and iSCSI tooling, sufficient
free capacity and correct topology labels. Backup targets require independent
S3 credentials and reachability.

The owning [Base ApplicationSet](../../Apps/Storage/Base.yaml) merges cluster
metadata with local and peer S3 providers. For each merged target this chart
creates a `User` claim that creates a long-lived service account and writes its
AWS-compatible credential Secret to `longhorn-system`. The S3 User composition
also publishes the full `AWS_ENDPOINTS` URL and explicitly selects
path-style S3 addressing with `VIRTUAL_HOSTED_STYLE=false`.

The local target is configured through Longhorn’s `defaultBackupStore`; peer
targets are registered as named `BackupTarget` resources. Longhorn 1.11
recurring jobs use the default target, so peer targets are available for
explicit backup or restore workflows rather than being written by the same
recurring job.

The DC1 local target uses the `dc1/` object prefix in its existing bucket.
The optional `prefix` on the ApplicationSet's first backup target is consumed
by `defaultBackupStore.backupTarget`; other targets retain their existing URLs.
Longhorn [rejects duplicate backup target URLs](https://github.com/longhorn/longhorn-manager/blob/v1.11.3/datastore/longhorn.go)
even when different credential Secrets select different S3 endpoints. Without
this prefix, `default` conflicts with `peer-home1` and the manager cannot apply
the local target configuration. An empty prefix retains the bucket root, as
currently configured for Home1. This changes DC1's local discovery path, not
the peer path: any older local backups at the bucket root must be restored
from their original URL, not assumed to appear under `dc1/`. No such backups
were recorded in DC1's Longhorn API during the 2026-09-26 preflight.

Before rolling managers, selectively sync `longhorn-default-resource` in the
DC1 storage-base application and wait for `BackupTarget/default` to become
available. The installed 1.11.3 manager watches this ConfigMap; no restart is
needed. Check the target condition separately from the backup `User` claims,
because healthy identities do not prove usable backups. Home1/YVR S3 was
reported offline due to disk capacity during this preflight; do not retry or
reconcile that site's storage as part of the DC1 upgrade. A local S3 target
backed by this same Longhorn cluster is not an independent site recovery copy.

## Operational risks

Storage-class parameters are inherited by newly created volumes and may differ
from existing volumes. Replica count does not protect against correlated site,
power, filesystem or operator failure.

Before node maintenance, verify volume robustness, replica placement, rebuild
headroom, snapshots/backups and workload disruption. Test restoration from the
configured backup target; do not use successful replica rebuilds as evidence
that backups work.

## Upgrade to 1.12.1

The desired chart version is 1.12.1. The dc1 manager and volume engines were
observed at 1.11.3 before this change; editing Git does not upgrade running
volumes. The ApplicationSet uses the Lovely Helm renderer and selects registered
CoRE bare-metal infrastructure clusters. Its explicit backup metadata covers
`core-dc1-talos-prod` and `core-home1-talos-prod`; verify the generated applications
and destination clusters before syncing. It preserves resources on application
deletion and does not configure automated sync.

Follow the [upstream upgrade procedure](https://longhorn.io/docs/1.12.1/deploy/upgrade/):
upgrading from 1.11.x to 1.12.1 is supported, skipping minor versions is not.
Kubernetes 1.25 or newer is required. Verify each target's installed version,
node readiness, replica placement, free capacity, backing-image health and
recoverable backups before reconciling. Investigate faulted or unexpectedly
unknown volumes first. Create a system backup and confirm a data backup can be
restored independently. This chart enables V1 and disables V2; if live state
contains V2 volumes, detach them and stop their replicas before upgrading.

The Argo CD pre-upgrade Job remains disabled, while manager version checks stay
enabled. Reconcile through Git and the owning Argo CD application, then check
manager/CSI rollout and logs, engine-image readiness, volume robustness and
workload read/write access. Existing volume engines require a separate
[engine upgrade](https://longhorn.io/docs/1.12.1/deploy/upgrade/upgrade-engine/).
Verify local and peer backup-target availability, perform a backup/restore test,
and confirm the authenticated UI and Prometheus scraping still work.

Version 1.12.1 enables
[internal network restrictions](https://longhorn.io/docs/1.12.1/advanced-resources/security/network-policy/)
by default, independently of `networkPolicies.enabled`. This chart explicitly
sets `networkPolicies.restrictInternalTraffic: false` to preserve the existing
connectivity model during this upgrade, including cross-namespace Prometheus
scraping. Enabling restrictions requires validating Talos/CNI compatibility and
adding scoped monitoring access as described in the
[monitoring guide](https://longhorn.io/docs/1.12.1/monitoring/prometheus-and-grafana-setup/).

A successful upgrade cannot be rolled back by reverting the chart pin:
Longhorn does not support downgrades. Recovery requires the upstream restoration
procedure and verified backups. Do not uninstall or enable the deletion
confirmation setting as an upgrade recovery step; removing storage resources
can destroy volume data. Retain backup claims and their credential references
until restoration is verified.

### DC1 rollout preflight, 2026-09-26

The requested 1.11.3 to 1.12.1 rollout passed Helm lint, representative rendering
with the live application's injected values, and non-persistent API validation
using Argo CD's existing field manager. There were no immutable-field or
admission failures. Both published backup configuration syncs were restricted
to DC1's `longhorn-default-resource`; the parent sync selected only the storage
ApplicationSet. No Home1 storage application was synced.

DC1 had three ready nodes and 32 V1 volumes: 25 attached/healthy and seven
detached/unknown. The detached volumes had previously healthy, stopped replicas;
none was faulted. Four volumes had a single replica, including one detached
volume. No V2 volumes or backing images were present. All managers and engines
were still 1.11.3; automatic engine upgrades were disabled (per-node limit `0`).

The duplicate backup URL was corrected through Git and Argo CD. The local
`default` target subsequently reported `available: true`. Home1's peer remained
offline, consistent with the owner's report of disk capacity problems. No
`Backup`, `BackupVolume` or `SystemBackup` resources were recorded. DC1 MinIO's
500 GiB Longhorn volume had approximately 211 GiB free during inspection; it
shares the upgraded storage system's failure domain. These observations do not
establish recoverability. The manager rollout was held pending the owner's
decision on proceeding without verified backups; enabling a target alone is
not backup/restore verification. Recheck these observations before resuming.
