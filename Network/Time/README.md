# Public YXL NTP

This rendering unit deploys a two-replica [chrony](https://chrony-project.org/documentation.html)
NTP server through the [BJW-S common library chart](https://github.com/bjw-s-labs/helm-charts/tree/common-5.0.1/charts/library/common).
It is owned by [`Apps/Network/Time.yaml`](../../Apps/Network/Time.yaml) and is
currently selected only for `core-dc1-talos-prod` in YXL.

The Service is UDP/123 only, uses PureLB's `anycast` service group, explicitly
requests `66.165.222.123`, and uses `externalTrafficPolicy: Local`. The pod is
non-root, read-only-rootfs, capability-free, tokenless, and has a default-deny
NetworkPolicy: public clients can send only NTP; egress is limited to DNS and
UDP/123 upstream time servers. `NOCLIENTLOG=true` avoids retaining client
addresses in chrony client logs. Kubernetes applies `fsGroup: 101` to the
memory-backed configuration/runtime volumes and reapplies the ownership on
every pod start. The rootless `100:101` user can also write the retained 1Gi
`ReadWriteOnce` PVC mounted at `/var/lib/chrony`; see the Kubernetes
[`fsGroupChangePolicy` documentation](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/#set-the-security-context-for-a-pod).

The image is the immutable amd64 digest of the upstream
[`simonrupf/docker-chronyd`](https://github.com/simonrupf/docker-chronyd) image,
using its separate [NTS-enabled image variant](https://github.com/simonrupf/docker-chronyd#enable-network-time-security-nts-separate--nts-image).
The default Alpine 3.24 image omits NTS support. The NTS variant runs chronyd
as a non-root `chrony` user and supports the chart's runtime. The chart bypasses the image entrypoint because it attempts a
privileged `chown` on `/run/chrony`; instead, the rootless user writes the
generated config to `/etc/chrony` and starts chronyd without system-clock
control. A short-lived init container assigns the memory-backed directories to
UID/GID `100:101` and provides a writable `/run` memory volume; the rootless
process creates `/run/chrony` itself with Chrony's required `0770` permissions
before starting. This preserves the chart's `NTP_SERVERS`,
`NOCLIENTLOG`, and `LOG_LEVEL` settings while allowing writes to the volumes.

NTS is enabled for `syncmy.date`: Chrony serves NTS Key Establishment on
TCP/4460 using the cert-manager-generated `syncmydate-default-certificates`
Secret. The certificate and private key are mounted read-only and are
readable by Chrony's UID/GID `100:101`; NTS cookie keys are persisted in the
existing PVC. Chrony requires `ntsservercert` and
`ntsserverkey` to enable the NTS-KE port; see the upstream
[`chrony.conf` NTS directives](https://chrony-project.org/doc/4.8/chrony.conf.html#ntsservercert).

## Reconciliation and verification

Argo CD renders this chart with the ApplicationSet merge and applies it to
`core-prod`. PureLB must have an `anycast` service group/pool containing the
requested address, and upstream routing/firewall policy must permit public UDP
123. After sync, verify the Service address and local endpoints, then inspect
chrony state with `chronyc tracking` and `chronyc sources` in the pod. From an
external network, query `66.165.222.123` with an NTP client; a healthy server
should not report stratum 16.

The source configuration uses Cloudflare and Google time services. Change the
`ntp.servers` value through Git if upstream policy changes. Roll back through
Git and Argo CD; removing the Application does not remove the upstream route,
PureLB pool allocation, or external firewall rules. The state PVC is retained
when this release is removed; delete it deliberately only after confirming
Chrony drift and NTS-cookie data is no longer needed. NTS clients also require
TCP/4460 to be permitted to the public service in upstream firewall policy.

## Metrics and Grafana

Each Chrony pod also runs the pinned amd64 build of the
[`chrony_exporter`](https://github.com/SuperQ/chrony_exporter) beside Chrony.
The exporter reads `/run/chrony/chronyd.sock` as UID/GID `100:101` and exposes
TCP/9123 only through the internal `*-metrics` ClusterIP Service. The
NetworkPolicy permits that port only from `core-prod`, where the central
[Grafana Alloy ServiceMonitor receiver](../../Observability/Collectors/README.md)
scrapes it and forwards the metrics to Mimir. The exporter image is
[published on Docker Hub](https://hub.docker.com/r/superque/chrony-exporter-linux-amd64)
and is pinned by digest in `values.yaml`.

The `ServiceMonitor` is Git-managed and the dashboard ConfigMap has the
`grafana_dashboard` label used by the deployed
[Grafana dashboard sidecar](https://github.com/grafana/helm-charts/tree/main/charts/grafana#sidecar-for-dashboards),
so the `Chrony NTP` dashboard is imported automatically. It covers the
exporter's tracking stratum, offset, root dispersion, and root delay metrics.
The upstream [Chrony dashboard 19186](https://grafana.com/grafana/dashboards/19186-chrony/)
is an alternative import if a richer dashboard is preferred.

After Argo sync, verify the `ServiceMonitor` target and the `chrony_*` series
in Grafana/Mimir. A failed target usually means the pod is not listening on
the Unix socket or the metrics ingress rule is being evaluated by the CNI;
the public NTP Service intentionally does not expose TCP/9123.

## NTPinfo

NTPinfo is not included in this change. The upstream
[NTPinfo project](https://github.com/NTPinfo/NTPinfo) is a multi-component
application requiring PostgreSQL, RIPE Atlas API credentials, a MaxMind
GeoLite dataset, and its compiled `ntp-nts` submodule/toolchain; it does not
provide a suitable immutable public runtime image that can be deployed here
without inventing production secrets or an unreviewed build. Provisioning
`ntpinfo.syncmy.date` therefore requires a Vault-backed secret mapping for
those credentials plus an approved pinned image/build artifact. The hostname
is not added to the existing public NTP Service because NTPinfo is an HTTP
application and needs its own Gateway route and application lifecycle.
