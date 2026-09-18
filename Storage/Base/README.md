# Storage Base chart

This chart deploys Longhorn and CoRE storage classes, UI routing and
authentication policy. It is owned by `Apps/Storage/Base.yaml`.

## Components

- Longhorn manager, engine and supporting components.
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
also publishes `AWS_ENDPOINTS` for Longhorn.

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
