# Storage Base chart

This chart deploys Longhorn and CoRE storage classes, UI routing and
authentication policy. It is owned by `Apps/Storage/Base.yaml`.

## Components

- Longhorn manager, engine and supporting components.
- Default and SSD-oriented storage classes.
- Deployment-specific non-redundant storage class.
- Authentik/security policy and HTTPRoute for the Longhorn UI.

## Prerequisites

Nodes require supported disks/filesystems, mount and iSCSI tooling, sufficient
free capacity and correct topology labels. Backup targets require independent
S3 credentials and reachability.

## Operational risks

Storage-class parameters are inherited by newly created volumes and may differ
from existing volumes. Replica count does not protect against correlated site,
power, filesystem or operator failure.

Before node maintenance, verify volume robustness, replica placement, rebuild
headroom, snapshots/backups and workload disruption. Test restoration from the
configured backup target; do not use successful replica rebuilds as evidence
that backups work.
