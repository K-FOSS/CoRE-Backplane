# CoRE-Backplane Lab/Storage Stack

This stack keeps the existing lab request-writer and file-browser test workload
and adds a replicated Garage object store plus an independent site-local Garage
in each of YVR and YXL. It is
owned by the [Lab Storage ApplicationSet](../../Apps/Lab/Storage.yaml) and
renders into `core-testing`. The Garage operator and CRDs remain owned by the
[Garage Operator ApplicationSet](../../Apps/Storage/S3/Garage-Operator.yaml).

## Ownership, targets, and rendering

The ApplicationSet targets the selected bare-metal tenant clusters. Garage is
enabled only when the cluster region is `yvr` or `yxl`; the existing k3s lab
target remains on the request-writer/file-browser path only. ApplicationSet
values inject the cluster domain, site region, storage classes, Vault
references, and the YVR hub selection into this chart. The complete rendering
unit is this chart plus its `garage-ui` dependency, rendered by the Lovely Helm
plugin. Chart defaults and configurable common settings are defined in
[`templates/_helpers.tpl`](templates/_helpers.tpl) and `values.yaml`; the
ApplicationSet overlay supplies the target cluster, site, storage classes and
federation peer data.

## Garage topology and data flow

Each site creates a three-node Auto-managed replicated Garage tier and a
separate three-node Auto-managed site-local Garage tier, each with a 20Gi data
PVC and 2Gi metadata PVC. Garage uses replication factor `3`, consistent
layouts, at-least-two-zone redundancy, retained PVCs, and the site pod CIDR for
its advertised RPC address range. The YVR cluster is the layout writer and
hosts the only Garage UI at `https://lab-garage-ui.mylogin.space`; YXL is the
follower. Both replicated sites use the same Vault-backed `AdminToken` and
`RPCSecret` from `Garage/LabStorage`; each local site uses a distinct Vault path
under `Garage/LabStorageLocal-<region>`. The local tier has no remote cluster
and its buckets are not part of the cross-site layout. A future backup job may
archive the local tier into the replicated tier or another off-site target.

Cross-site RPC is advertised with one identity-specific headless Service per
Auto-managed storage ordinal at each site and the site ExternalDNS controller.
The Services select the Garage node pods and publish
their routable pod addresses; no node-address or LoadBalancer dependency is
introduced. The public Admin API routes are site-specific:
`lab-garage-admin.<datacenter>.<region>.mylogin.space`. The S3 route is
`lab-garage-s3.core-testing.<cluster-domain>`.

The remote node identity registry is intentionally empty in this review
change. Auto-managed node IDs are generated from the PVC-backed node
identities and must not be invented. After the first YVR/YXL bootstrap, record
each remote site's observed node ID, zone, capacity, and ExternalDNS hostname in
`garage.federation.remoteStorageNodes`; that registry creates the writer's
external `GarageNode` objects and the follower's headless RPC Services. Until
that registry is populated, the two site-local clusters are prepared but
cross-site layout replication is not complete. This is the required
identity-safe bootstrap described by the [Garage Operator federation
guide](https://rajsinghtech.github.io/garage-operator/how-to/federation/).

The optional `garage.user` values render a namespaced
[`mylogin.space/User`](../../Operations/SSO/User/README.md) claim. It requests
Garage service-account credentials and writes them to a stable Secret, using
the same Garage endpoint and cluster identity that the observability claims
use. Keep it disabled in the shared lab deployment unless a lab consumer and
its bucket names are deliberately assigned.

The [site-local provider template](templates/Garage/SiteLocal/SiteLocalGarageCrossplane.yaml)
creates a Garage operator-managed
[`GarageKey`](https://rajsinghtech.github.io/garage-operator/reference/api/garagekey-v1beta1/)
and a Crossplane Terraform
[`ProviderConfig`](https://github.com/crossplane-contrib/provider-terraform#providerconfig)
named `lab-garage-local-s3` in each YVR/YXL cluster. The key writes its S3
credentials to a Secret in `core-testing`; the ProviderConfig reads that Secret
and configures the pinned [Terraform AWS provider](https://registry.terraform.io/providers/hashicorp/aws/5.100.0/docs)
to use Garage's in-cluster S3 endpoint with path-style requests. Workspaces can
select `providerConfigRef.name: lab-garage-local-s3` for site-local S3 work.
This provisioner can create buckets and has owner, read, and write access to
every bucket in the independent lab store. Limit its use to trusted lab
infrastructure; application consumers should use bucket-scoped Garage keys.
The MinIO Crossplane provider is not used because its MinIO admin API is not
the Garage S3 API.

## Prerequisites and security

Before reconciliation, verify that the Garage operator is healthy in both
clusters, Longhorn is available, the `main-gw` HTTPS listener is reachable,
ExternalDNS watches headless Services, and the `mainvault-core`
`ClusterSecretStore` can read/write `Garage/LabStorage`. The Vault properties
are `AdminToken` and `RPCSecret`; no credential values belong in Git. The UI
route is protected by the Authentik forward-auth outpost and grants access
only to the `Server Admins` group.
The Terraform provider controller must be able to read the generated
`lab-garage-local-crossplane-credentials` Secret in `core-testing` and reach
`lab-garage-local` on port `3900`.

The deployment uses [Garage](https://garagehq.deuxfleurs.fr/), the
[Garage Kubernetes Operator](https://rajsinghtech.github.io/garage-operator/),
the operator's [GarageCluster API](https://rajsinghtech.github.io/garage-operator/reference/api/garagecluster-v1beta2/),
the operator's [federation guide](https://rajsinghtech.github.io/garage-operator/how-to/federation/),
the [Noooste Garage UI Helm chart](https://github.com/Noooste/garage-ui/tree/main/helm/garage-ui),
and [ExternalDNS Service sources](https://kubernetes-sigs.github.io/external-dns/latest/sources/service/).
The lab test workloads are generated by the [BJW-S common library chart](https://bjw-s-labs.github.io/helm-charts/docs/common-library/).

## Operations and verification

Resolve dependencies and render both site variants before review:

```bash
helm dependency build Lab/Storage
helm lint Lab/Storage
helm template lab-storage-yvr Lab/Storage --namespace core-testing \
  --set cluster.name=core-home1-talos-prod \
  --set cluster.domain=k8s.home1.resolvemy.host \
  --set datacenter=home1 --set region=yvr \
  --set garage.enabled=true --set garageUI.enabled=true \
  --set garage-ui-web.enabled=true
```

After the identity registry is populated and Argo CD reconciles, verify the
Vault-backed ExternalSecrets, three PVC-backed nodes per site, Garage layout
health, headless Service endpoints, ExternalDNS records, HTTPRoute
`Accepted`/`ResolvedRefs`, and the YVR UI Authentik Workspace. Confirm an
object written through either site is readable after layout convergence.
For the local provider, check that `GarageKey/lab-garage-local-crossplane` is
Ready, the credential Secret exists without printing its values, and the
Terraform `ProviderConfig/lab-garage-local-s3` is present. A Workspace must
still be tested against its intended bucket workflow before claiming S3
provisioning is healthy.

The federated Garage tier uses `Drain` to retire a site from its surviving
layout. The independent site-local tier uses `Destroy`: it has no remote
clusters to drain into, so deleting its GarageCluster tears down that store's
operator-managed workloads and identity records. Both tiers set PVC retention
to `Retain` on deletion and scale-down. Removing the chart retains those PVCs
and the Vault path. Treat them as recovery material and delete them only after
consumers and retained data have been reviewed. See the operator's
[deletion and recovery guidance](https://rajsinghtech.github.io/garage-operator/operations/maintenance-and-recovery/).
Removing the site-local GarageKey revokes its provisioner access; review the
generated Secret and any dependent Workspaces before deletion. Existing
buckets and object data require separate review.

## Existing lab test workload

The [Lab storage ApplicationSet](../../Apps/Lab/Storage.yaml) renders this
chart with the Lovely Helm plugin and deploys it to every selected bare-metal
tenant cluster. Its destination namespace is `core-testing` for the current
ApplicationSet values.

## Current behavior

The chart creates an RWX `PersistentVolumeClaim`, a one-replica request-writer
Deployment and Service, and a separate one-replica file-browser Deployment and
Service. The request writer mounts the claim at `/data`; each HTTP connection
accepted on port 8080 creates a unique `request-XXXXXX` file containing the
HTTP request line and responds with `201 Created`. TCP health probes deliberately
do not issue HTTP requests, so they do not add files.

The `<release>-file-browser` Service targets only the file-browser pod. It
mounts the same claim read-only and exposes an NGINX directory index at port
8080. The listing and the linked files are reachable only inside the cluster
through that ClusterIP Service; do not add ingress or expose this Service unless
the resulting file disclosure is intended.

The Deployment uses the [Docker Official BusyBox image](https://hub.docker.com/_/busybox)
pinned to a multi-architecture manifest digest. Its small `nc`-based listener
is intentionally a test workload, not an internet-facing or authenticated
application. The browser uses the [Docker Official NGINX image](https://hub.docker.com/_/nginx/)
pinned to a multi-architecture manifest digest and enables NGINX's
[autoindex module](https://nginx.org/en/docs/http/ngx_http_autoindex_module.html).

## Prerequisites and verification

The target cluster's default StorageClass must provide `ReadWriteMany` storage;
this chart does not select a StorageClass. After Argo CD reconciles, verify the
claim is bound and the Deployment is available, then from the same namespace:

```sh
kubectl -n core-testing run request-writer-check --rm -i --restart=Never \
  --image=docker.io/library/busybox@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0 -- \
  wget -qO- http://<release>-request-writer:8080/
kubectl -n core-testing exec deploy/<release>-request-writer -- ls -1 /data
kubectl -n core-testing run file-browser-check --rm -i --restart=Never \
  --image=docker.io/library/busybox@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0 -- \
  wget -qO- http://<release>-file-browser:8080/
```

The request command should return a created filename, the subsequent list
should include that file, and the final command should return an HTML directory
listing containing it. Replace `<release>` with the Argo CD application's Helm
release name. The commands use the [Kubernetes Service DNS model](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/).

## Rollback and deletion

Removing the Deployment and Service stops new writes. PVC lifecycle remains
controlled by the ApplicationSet's `preserveResourcesOnDeletion: true` policy;
do not delete the claim unless its retained test data is intentionally no
longer needed.
