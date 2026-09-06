# Kapowarr

The Kapowarr deployment is owned by `Apps/Media/Comics.yaml`, which selects
bare-metal production clusters for the media tenant and renders this chart
through the Lovely Argo CD plugin.

The [Kapowarr Docker installation documentation](https://casvt.github.io/Kapowarr/installation/docker/)
documents the `mrcas/kapowarr` image and its `PUID`/`PGID` environment variables.
The image entrypoint must start as root to apply those values, so this chart
sets `PUID` and `PGID` to `911` but does not set pod-level `runAsUser` or
`runAsGroup`; the entrypoint drops to that identity itself. `fsGroup` remains
`911` for mounted-volume access.

The image is pinned by digest in `values.yaml`. After reconciliation, verify
the generated pod starts without `/etc/group` or `/etc/passwd` permission
errors, runs Kapowarr on port `5656`, and can read/write `/app/db`,
`/app/temp_downloads`, and `/comics`.
