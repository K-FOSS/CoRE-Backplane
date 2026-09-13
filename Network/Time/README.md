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
memory-backed Chrony volumes and reapplies the ownership on every pod start,
so the rootless `100:101` user can write its configuration, runtime, and state
paths; see the Kubernetes [`fsGroupChangePolicy` documentation](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/#set-the-security-context-for-a-pod).

The image is the immutable multi-architecture digest of the upstream
[`simonrupf/docker-chronyd`](https://github.com/simonrupf/docker-chronyd) image,
which runs chronyd as a non-root `chrony` user and supports the chart's
runtime. The chart bypasses the image entrypoint because it attempts a
privileged `chown` on `/run/chrony`; instead, the rootless user writes the
generated config to `/etc/chrony` and starts chronyd without system-clock
control. A short-lived init container assigns the memory-backed directories to
UID/GID `100:101` and provides a writable `/run` memory volume; the rootless
process creates `/run/chrony` itself with Chrony's required `0770` permissions
before starting. This preserves the chart's `NTP_SERVERS`,
`NOCLIENTLOG`, and `LOG_LEVEL` settings while allowing writes to the volumes.

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
PureLB pool allocation, or external firewall rules.
