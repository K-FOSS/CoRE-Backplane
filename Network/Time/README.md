# CoRE-Backplane Network/Time Stack

This chart is a fresh-install design for a horizontally scalable [Chrony](https://chrony-project.org/documentation.html) NTP/NTS service. It is rendered through the [BJW-S common library chart](https://github.com/bjw-s-labs/helm-charts/tree/common-5.0.1/charts/library/common) and owned by [`Apps/Network/Time.yaml`](../../Apps/Network/Time.yaml). It does not migrate, copy, or import state from an existing installation.

## Topology

The default installation contains one singleton `key-authority` Deployment, two `chrony` StatefulSet replicas (each with a local chrony-exporter), one retained RWX PVC containing only canonical `ntskeys`, one retained RWO PVC per serving replica, and one retained RWO PVC plus memory-backed `/tmp` for the singleton NTP Dashboard. It also creates a public PureLB/anycast LoadBalancer for UDP/123 and TCP/4460, a private ClusterIP `chrony-command` Service for UDP/323, an internal metrics Service, and the existing ServiceMonitor/Grafana path.

The public Service selects only serving Chrony pods and keeps `externalTrafficPolicy: Local`. A PureLB node must therefore have a local Ready serving endpoint to accept externally routed traffic correctly. The key authority has no Service and is never selected by either public or command Service.

## NTS cookie-key authority

TLS certificate/private-key material authenticates NTS-KE. The `ntskeys` file is separate symmetric cookie-key material used after NTS-KE. Sharing the TLS Secret alone cannot make replicas interoperate.

The singleton key authority runs the pinned [NTS-enabled Chrony image](https://github.com/simonrupf/docker-chronyd#enable-network-time-security-nts-separate--nts-image) with automatic rotation and writes the retained `ntskeys` file to the dedicated RWX PVC. It is loopback-bound, has no public NTP/NTS endpoint, receives no ingress, and has no network Service. Only this workload mounts the canonical PVC read-write. The PVC must be an actual RWX claim, including when `existingClaim` is used.

Each serving pod mounts that PVC read-only. Its key-sync sidecar validates ownership, mode, non-empty content, and generation; copies the file through a fsynced temporary file and atomic rename; calls local `chronyc rekey`; and records only generation/status data. The first successful load is required for readiness. A temporary authority outage does not restart a pod or discard its already-loaded keyset.

`ntsrotate: 0` is enforced for serving replicas, preventing independent rotation, concurrent canonical writers, and cross-replica NTS failures. The authority retains Chrony's current, previous, and subsequent rotation keys. Canonical key material is sensitive secret material and requires protected, tested backups. Losing it invalidates existing NTS cookies but does not affect time correctness; clients must repeat NTS-KE.

## Per-replica state and security

`/var/lib/chrony` is not shared RWX: it contains writable drift, upstream NTS client cookies, source histories, local cookie-key state, and PID-related state. A per-replica RWO claim gives those paths independent ownership. The runtime directory `/run/chrony` is a memory-backed emptyDir for the Unix command socket and PID/runtime files. The local socket is used by `chronyc rekey`, health checks, and the exporter; it is never mounted by the Dashboard.

All workloads are tokenless, rootless, read-only-rootfs where applicable, capability-dropped, and use RuntimeDefault seccomp. No SSH server, SSH key, password, sudo configuration, command adapter, migration Job, or legacy compatibility resource is created.

## Chrony command interface and policies

Serving pods use:

    bindcmdaddress 0.0.0.0
    bindcmdaddress /run/chrony/chronyd.sock
    cmdport 323
    cmdallow <configured dashboard pod CIDR>
    opencommands tracking sources clients

The command Service exposes UDP/323 only, uses `ClientIP` session affinity, and has the configurable timeout `dashboard.commandService.sessionAffinityTimeoutSeconds`. NetworkPolicy allows UDP/323 only from the Dashboard pod and allows the Dashboard only DNS, that command Service path, and its existing Authentik ingress dependencies. `cmdallow` is address-level Chrony authorization; NetworkPolicy supplies workload-identity enforcement. Configure the narrowest pod CIDR that can be used by the Dashboard. UDP/323 and exporter metrics are never public, and public ingress remains UDP/123 plus TCP/4460.

`tracking` and `sources` describe the selected Chrony replica. `clients` is only the client list observed by that replica, not an aggregate cluster-wide list. Prometheus/Mimir remains authoritative for aggregate metrics. If the selected replica disappears, Kubernetes may move the Dashboard's command traffic to another Ready replica.

## Dashboard status and verified image limitation

The [NightHawkATL NTP Dashboard](https://github.com/NightHawkATL/ntp-dashboard) remains a separate singleton Recreate Deployment, with its retained data PVC, dedicated memory-backed `/tmp`, `https://dash.syncmy.date`, fail-closed Authentik protection, and Server Admins restriction. The TICC-DASH workload and `clients.syncmy.date` route/resources are absent. The Dashboard has no Chrony state, canonical-key, or Unix socket mount.

Before editing, the exact pinned Dashboard image was inspected. Its source supports only local `chronyc` subprocess mode or SSH mode; its `config.json` schema has no remote Chrony host/port setting, and the image does not contain a native UDP command-port client. The pinned image bundles Chrony/chronyc 4.8, which matches the pinned Chrony image (also 4.8), but that does not solve the Dashboard transport limitation. No unsupported environment variable or SSH fallback has been introduced. Therefore remote Dashboard tracking, sources, and clients are a material operator-blocked acceptance item until an approved Dashboard image with native UDP/323 support replaces this digest.

## Installation and verification

The owning ApplicationSet/certificate stack supplies the NTS TLS Secret named by
`nts.secretName`; it is not a chart-local Secret or a manual credential input.
Configure the canonical PVC with an RWX storage class or
`keyAuthority.canonicalKey.existingClaim`. The repository's
[`Lab/Storage` RWX example](../../Lab/Storage/README.md) shows the local
Longhorn RWX pattern; use the storage class available to the target cluster.
The actual Dashboard source pod CIDR belongs in
`ntp.dashboardCommandCidrs`. Review PureLB annotations/address allocation and
upstream firewall rules for UDP/123 and TCP/4460. Install as a new Argo
application; sync waves are storage/references (0), authority (1), serving
pods (3), Services (4), Dashboard (5), and monitoring (6).

After installation, verify through an approved administrative path:

    chronyc authdata
    chronyc ntpdata syncmy.date

Expected steady state is Mode NTS, Atmp 0, NAK 0, Cook 8, Authenticated Yes, Leap status Normal, and increasing valid responses. A fresh one-shot test is:

    sudo chronyd -Q -t 10 'server syncmy.date iburst nts'

The existing test client must be re-keyed or restarted; old cookies are expected to become invalid. Do not treat a normal load-balanced request as proof of which replicas handled NTS-KE and NTP.

## Cross-replica and rotation test plan

Use a temporary per-pod Service, direct pod networking, or an NTS client that can choose separate NTS-KE and NTP destinations. Do not run this from Git or against a live cluster as part of chart validation. Deliberately establish NTS-KE through replica A, send authenticated NTP to B, then reverse B-to-A; repeat after authority rotation, after every pod reports a new key generation, and after restarting one replica. Confirm each pod loads the current keyset and becomes Ready only after local `chrony rekey` succeeds. Separately verify that network commands that change Chrony state remain rejected.

The command Service's session affinity normally keeps Dashboard requests on one backend. A readiness loss or endpoint change is the expected failover mechanism.

## Monitoring, recovery, and uninstall

Chrony-exporter remains beside every serving replica and is scraped through the internal ServiceMonitor. Alert on authority readiness, canonical key age, sync/rekey failures, key-generation mismatch, NTS-KE failures, NAKs, unsynchronized replicas, invalid leap status, and public local-endpoint loss.

Back up the canonical key PVC as sensitive material and separately back up the certificate Secret through the repository's secret-management system. The [Chrony 4.8 NTS directives](https://chrony-project.org/doc/4.8/chrony.conf.html#ntsservercert) define the cookie-key rotation and reload behavior. If the canonical store is lost, provision a fresh authority/keyset and re-key clients; do not restore it into Git, a ConfigMap, logs, or values. Chrony time service remains correct while clients repeat NTS-KE.

Uninstall removes workloads and Services according to Helm/Argo ownership but retained PVCs remain for deliberate operator cleanup. Never delete canonical keys or Dashboard data until backup, client re-keying, and service retirement are confirmed. No migration or blue/green cutover is provided.
