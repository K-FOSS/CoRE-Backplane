# IPAM and DCIM

This rendering unit deploys CoRE's site-specific DHCP, authoritative DNS, and
NetBox IPAM/DCIM integration. NetBox is intended to become the source of truth
for network and bare-metal inventory, but that automation is not complete; the
current gaps and desired state are tracked in [TODO](TODO.md).

## Ownership and targets

The [Network/IPAM ApplicationSet](../../Apps/Network/IPAM.yaml) owns this chart.
It selects registered Argo CD clusters labelled with tenant
`core.mylogin.space` and compute type `baremetal`, then merges only these named
targets:

- `core-dc1-talos-prod`
- `dc1-k3s-node1`
- `core-home1-talos-prod`

Argo CD renders `Network/IPAM` with the
[Lovely plugin](https://github.com/crumbhole/argocd-lovely-plugin). The
ApplicationSet injects the environment, cluster identity, topology, EFI boot
server, enabled Kea server types, DHCP secret volume, NetBox enablement, and
per-cluster Dragonfly host. It also injects the target cluster domain into
Kea's local PGPool Service name. DHCPv4 and DHCP-DDNS are enabled on all three
targets; DHCPv6 is disabled on both DC1 targets and enabled on Home1.
Applications are deployed to `core-prod`; deleting an ApplicationSet-generated
Application preserves its resources because `preserveResourcesOnDeletion` is
enabled. The source revision is the mutable `HEAD` reference, so Git history
and the rendered Argo CD revision must be used together during an audit.

## Components and reconciliation flow

- [bjw-s common library 3.6.1](https://github.com/bjw-s-labs/helm-charts/tree/common-3.6.1/charts/library/common)
  renders the Kea and PowerDNS workload, Services, ConfigMaps, and volumes.
- [ISC Kea 3.2](https://kea.readthedocs.io/en/kea-3.2.0/) serves DHCP and
  renders PXE paths for [Tinkerbell](https://tinkerbell.org/docs/). DHCP
  configuration is assembled by this chart and synchronized through External
  Secrets. DHCPv4, DHCPv6, and DHCP-DDNS use pathless UNIX control-socket names,
  which Kea resolves beneath its required `/var/run/kea` runtime directory.
  The container entry script restricts that memory-backed directory to mode
  `0750` before starting Kea, as required by Kea's control-socket checks.
  The removed Kea Control Agent is not configured; local management uses each
  daemon's control socket. Hook libraries use the Debian amd64 multiarch path
  supplied by the site image; both DHCP daemons load `libdhcp_pgsql.so` to
  register the PostgreSQL lease backend. The optional Netconf agent is disabled
  because it is not included in that image. Both DHCPv4 and DHCPv6 store leases
  through the site-local `psql` ClusterIP Service, which selects the local
  PGPool replicas in `core-prod`; database credentials and the port remain
  sourced from the secret store. The memory-backed Kea runtime directory lasts
  for the lifetime of the pod, including individual container restarts. On
  every container start, the entry script removes stale Kea PID files and
  control sockets before invoking `keactrl`; this prevents an unclean daemon
  exit from blocking recovery without deleting unrelated runtime files.
- [PowerDNS Authoritative Server 5.1.3](https://doc.powerdns.com/authoritative/changelog/5.1.html#change-5.1.3)
  serves DNS from the external PostgreSQL backend using the
  [official PowerDNS container](https://github.com/PowerDNS/pdns/blob/master/Docker-README.md),
  pinned to its multi-architecture manifest digest. The upgrade from 4.8.4
  follows the [PowerDNS upgrade notes](https://doc.powerdns.com/authoritative/upgrading.html):
  PostgreSQL must be 9.5 or newer for the 5.1 default TSIG replacement query,
  API record representations may be normalized differently, and updates to
  LUA records remain disabled because this deployment does not enable them.
- [NetBox chart 5.0.23](https://github.com/netbox-community/netbox-chart/tree/netbox-5.0.23/charts/netbox)
  deploys the [NetBox](https://netboxlabs.com/docs/netbox/en/stable/) web and
  worker components using the site image and enabled plugins.
- [External Secrets Operator](https://external-secrets.io/latest/) reads
  runtime credentials from `mainvault-core`; hub-mode `User` and `PushSecret`
  resources create and publish service identities. Home1 is the IPAM hub and
  creates the Kea identity and publishes its username and password. The
  generated username is also the PostgreSQL role and database name. Kea reads
  that database name and the site-managed host and port from Vault. The other
  targets are spokes and consume the published identity.
- An [HTTPRoute](https://gateway-api.sigs.k8s.io/api-types/httproute/) attaches
  NetBox to the shared Gateway. An [Envoy Gateway SecurityPolicy](https://gateway.envoyproxy.io/latest/api/extension_types/)
  applies OIDC credentials synchronized from the secret store.
- External PostgreSQL stores NetBox and PowerDNS data. The cluster's shared
  authenticated, TLS-enabled `dragonfly-core` supplies two dedicated logical
  databases: DB `80` for NetBox tasks and DB `81` for NetBox caching; see
  [Dragonfly compatibility](https://www.dragonflydb.io/docs/category/managing-dragonfly).
- A Crossplane Terraform `ProviderConfig` configures the
  [NetBox Terraform provider](https://registry.terraform.io/providers/e-breuninger/netbox/latest/docs).
  It depends on the
  [Upbound Terraform provider](https://github.com/upbound/provider-terraform)
  and a synchronized NetBox token.
- S3 settings are generated from an ExternalSecret for NetBox object storage.
  [Django storage configuration](https://netboxlabs.com/docs/netbox/en/stable/configuration/system/#storages)
  describes the settings consumed by NetBox.

The controller path is Git -> Argo CD/ApplicationSet -> Lovely/Helm ->
Kubernetes and External Secrets -> Vault-backed secrets -> NetBox, Kea,
PowerDNS, PostgreSQL, Dragonfly, Gateway/OIDC, S3, and Crossplane/Terraform.
Argo CD `Synced`, pod readiness, or a Crossplane `Ready` condition alone does
not verify that this complete path works.

## Values and secrets

[`values.yaml`](values.yaml) contains site overrides only. Defaults come from
the two pinned dependencies in [`Chart.yaml`](Chart.yaml), while cluster values
come from the owning ApplicationSet. `dhcp.servers.dhcp4`, `dhcp6`, and
`dhcpDdns` control the corresponding `keactrl` process flags per target. The
PowerDNS sidecar uses the same `dhcpDdns` flag and is omitted when DHCP-DDNS is
disabled. The custom Kea and NetBox image tags are mutable and use `Always`;
this is deliberate current behaviour and should be replaced by immutable
release tags or digests when the site images have a versioned publication
process.

No credential values belong in Git. `netbox-secret`, `netbox-creds`,
`dragonfly-core-password`, the DNS secret, pull credentials, OIDC
configuration, S3 credentials, and Terraform tokens are references to
controller-managed Secrets. NetBox reads the same generated Dragonfly password
as other local clients. A password rotation requires the NetBox web and worker
pods to be restarted after the updated Secret is available. Keep an emergency
access path independent of NetBox, Authentik, the public Gateway, Vault
application credentials, and any single cluster.

## Validation and operations

Before merging a change:

```sh
helm dependency build .
helm lint . \
  --set persistence.configs.volumeSpec.emptyDir.medium=Memory
helm template netbox-ipam . \
  --namespace core-prod \
  --set netbox.enabled=true \
  --set persistence.configs.volumeSpec.secret.secretName=core-dc1-talos-prod-network-ipam-prod-dhcp-config
git diff --check -- Network/IPAM
```

Also render each ApplicationSet target with its injected values. Inspect the
DHCP boot server and artifact paths, IP-address uniqueness and overlap, Gateway
parent references, secret names and keys, LDAP groups, database endpoints, and
Crossplane provider configuration. The example secret name above is a literal
representative value, not a credential.

After Argo CD reconciliation, verify all of the following:

1. ExternalSecret and PushSecret conditions, without printing Secret data.
2. Kea configuration load, lease allocation, PXE for the intended firmware,
   and Tinkerbell boot artifact retrieval on each target network. Also restart
   only the Kea container after an unclean daemon exit and verify it removes
   stale PID and control-socket files and returns ready without replacing the
   pod.
3. Kea lease reads and writes through
   `psql.core-prod.svc.<cluster-domain>`, plus PowerDNS PostgreSQL connectivity
   and authoritative TCP/UDP answers. After a PowerDNS upgrade, also verify a
   harmless RFC 2136 update and rollback of that test record, TSIG operations,
   zone transfer/notification flow, and representative API consumers.
4. NetBox migrations, web and worker health, TLS-authenticated Dragonfly
   connectivity to DBs `80` and `81`, PostgreSQL connectivity, OIDC login and
   group entitlement, API access, plugins, and S3 operations.
5. Gateway attachment and policy status, then the user-facing NetBox workflow.
6. Crossplane provider conditions and a harmless NetBox provider read.

After rotating `dragonfly-core-password`, reconcile or restart both NetBox
Deployments and verify that task processing and cache access recover. Secret
volume updates alone do not make the running NetBox processes reconnect with
the new password.

Inventory changes may eventually drive physical provisioning. Resolve the
exact site, cluster, machine, hardware identity, install disk, network, and
workflow state before retrying or applying a provisioning action. Never retry
an unidentified Tinkerbell/Talos failure.

Rollback through Git and let Argo CD reconcile the prior desired state. A chart
rollback does not roll back PostgreSQL contents, DHCP leases, Vault records,
S3 objects, or Terraform-created state. Back up NetBox and test restoration
before treating it as provisioning authority; explicitly assess those external
side effects before reverting or deleting resources.
