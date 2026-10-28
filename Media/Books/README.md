# CoRE-Backplane Media/Books Stack

This stack runs Chaptarr and provides its tenant-scoped books library volume.
The [`Books ApplicationSet`](../../Apps/Media/Books.yaml) owns the target and
volume size; the [Media/Common stack](../Common/README.md) owns the tenant
Longhorn StorageClass.

## Ownership, targets and rendering

The ApplicationSet targets `core-home1-talos-prod` in namespace `core-media`
and injects tenant `augy`. The chart uses the
[`bjw-s common` library](https://github.com/bjw-s-labs/helm-charts/tree/common-5.0.1/charts/library/common)
to render Chaptarr's workload, services, routes, and claims. Chaptarr follows
the [upstream container setup](https://github.com/Chaptarr/chaptarr#docker-recommended).

## Persistent storage

The new claim is named `media-augy-books`, uses `media-augy-storage`, requests
`ReadWriteMany`, and mounts at `/Books` in Chaptarr. The ApplicationSet's
`booksVolumeSize` value configures its size and is currently `100Gi`. The
chart's generic default leaves this claim disabled until an ApplicationSet
provides tenant-specific enablement and size.

The Chaptarr config claim remains mounted at `/config`. Chaptarr does not mount
the legacy `${tenant}-media` or `${tenant}-downloads` claims; those claims
remain owned by Media/Common and their data is not copied or deleted by this
change.

Media/Common provisions `media-augy-storage` with the Longhorn provisioner,
one replica, volume expansion enabled, and a `Delete` reclaim policy. Longhorn
serves RWX volumes through its NFS share-manager. This class has no second
Longhorn replica; keep a separate backup of any books that must survive loss
of its backing volume. See the upstream
[Longhorn 1.12.1 RWX volume documentation](https://longhorn.io/docs/1.12.1/nodes-and-volumes/volumes/rwx-volumes/)
and [StorageClass parameter reference](https://longhorn.io/docs/1.12.1/references/storage-class-parameters/).
Deleting the PVC deletes its backing volume, so back up its contents before
removing the claim or changing its lifecycle.

## Operations and verification

After reconciliation, verify `media-augy-books` is Bound with
`ReadWriteMany` and `storageClassName: media-augy-storage`, then confirm
Chaptarr mounts it at `/Books` and no legacy media or downloads claim is
mounted. Change the requested capacity through
`booksVolumeSize` in the ApplicationSet; the StorageClass allows expansion.
Shrinking the claim or moving files from an existing library requires a
separate data operation.
