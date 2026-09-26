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
