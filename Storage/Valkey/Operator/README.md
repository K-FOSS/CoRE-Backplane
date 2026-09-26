# Valkey operator

This stack installs the [official Valkey operator v0.7.0](https://github.com/valkey-io/valkey-operator/blob/v0.7.0/README.md)
without creating database instances. Its API is `ValkeyCluster` and `ValkeyNode`
in `valkey.io/v1alpha1`. It supports **Cluster mode only**, not standalone or
Sentinel. Installation does not establish compatibility with RTPEngine's
numbered databases or move any RTPEngine consumer. See the
[upstream quickstart and limitations](https://github.com/valkey-io/valkey-operator/blob/v0.7.0/docs/quickstart.md).

## Ownership, selection and rendering

The [ApplicationSet](../../../Apps/Storage/Valkey/Operator.yaml) is discovered
by the recursive Apps application. It selects registrations with tenant
`core.mylogin.space`, compute type `baremetal` and node type `infra`: currently
`core-home1-talos-prod` and `core-dc1-talos-prod`. Future registrations matching
these labels are included; there is no environment filter. Bootstrap `init`
and the legacy K3s cluster are not targets.

Applications belong to project `core` and target `valkey-operator-system`, with
server-side apply and namespace creation. No Helm values are injected. Sync is
manual; ApplicationSet deletion preserves resources. Repository `HEAD` is the
mutable fleet desired-state reference.

The [Lovely renderer](https://github.com/crumbhole/argocd-lovely-plugin#readme)
combines the minimal Helm chart and Kustomize unit. Helm has no dependencies
or workload templates; Kustomize imports the
[official installation configuration](https://github.com/valkey-io/valkey-operator/tree/v0.7.0/config/default)
at commit `0da91fef78d926f403c6a26d75d915dccde975a5` (v0.7.0). Local patches
restrict the watch and RBAC scope. The operator
[image build source](https://github.com/valkey-io/valkey-operator/blob/v0.7.0/Dockerfile)
is pinned to the verified GHCR digest in `kustomization.yaml`.
The upstream manager Kustomization still references `v0.0.1`; the local image
override deliberately replaces it with the v0.7.0 digest. GitHub access is
required for rendering and GHCR access for node image pulls.

This uses the v0.7.0 upstream manifests rather than the Helm repository's
currently published 0.6.0 chart to keep controller and CRDs aligned. It retains
upstream controller manifests instead of reconstructing them with BJW-S, to
preserve the operator installation contract and CRD/RBAC ordering.

## Prerequisites and security

v0.7.0 requires Kubernetes 1.32 or newer because the CRDs use the CEL format
library; both selected clusters were observed at v1.36.3. Argo CD project `core`
must permit the destination namespace and cluster-scoped CRDs/RBAC. There must
be no other owner of these CRDs or competing controller for these instances.
Review the [v0.7.0 release and migration notes](https://github.com/valkey-io/valkey-operator/releases/tag/v0.7.0)
before upgrades.

The controller watches only `valkey-operator-system` with the upstream
[`--watch-namespace` option](https://github.com/valkey-io/valkey-operator/blob/v0.7.0/cmd/main.go).
Its workload ClusterRole and ClusterRoleBinding are converted into a Role and
RoleBinding in that namespace. Thus its credentials cannot mutate workloads
or read Secrets in legacy namespaces even if the watch is later misconfigured.
Future managed instances must be in this namespace; widening it requires a
coordinated watch/RBAC review.

Cluster permissions bound to the controller only support TokenReview and
SubjectAccessReview for authenticated HTTPS metrics on port 8443. The metrics
reader and Valkey admin/editor/viewer roles are not bound to users by this stack.
The pod runs as non-root with RuntimeDefault seccomp, a read-only root filesystem,
no privilege escalation and dropped capabilities. No public endpoint, DNS record,
application identity, password or Secret is created. Metrics scraping is not
configured by this deployment.

Legacy KeyDB (`Apps/Storage/Redis.yaml`, `Storage/KeyDB/KeyDBChart`, `keydb-core`),
the separate KeyDB operator work, and shared Dragonfly allocations are untouched.
Application onboarding must separately declare its required `User` claim and
stable connection Secret, review authentication and grants, and pin its database
image. Do not treat an operator installation as provisioning an application identity.

## Reconciliation and verification

Argo CD installs both CRDs at sync wave `-1`, then controller resources. The
complete render contains 16 resources: Namespace, two CRDs, ServiceAccount,
two Roles, two RoleBindings, five ClusterRoles, one ClusterRoleBinding, metrics
Service and Deployment. No ValkeyCluster, ValkeyNode, StatefulSet, PVC or Secret
is emitted. For future instances, the operator reconciles
[ValkeyCluster topology and configuration](https://github.com/valkey-io/valkey-operator/blob/v0.7.0/docs/valkeycluster.md)
into ValkeyNodes and downstream workload/storage resources.

Validate from the repository root:

```bash
helm dependency build Storage/Valkey/Operator
helm lint Storage/Valkey/Operator
helm template valkey-operator Storage/Valkey/Operator --namespace valkey-operator-system
kustomize build Storage/Valkey/Operator > /tmp/valkey-operator.yaml
git diff --check -- Apps/Storage/Valkey/Operator.yaml Storage/Valkey/Operator Storage/README.md
```

Helm intentionally emits no resources. Inspect Kustomize output for the pinned
image, watch namespace, RoleBinding references, CRD ordering, retained Namespace
and CRDs, and absence of credentials. Publish only the reviewed stack through Git,
then use [Argo CD resource-selective sync](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-options/#selective-sync)
on the Apps parent to install this ApplicationSet, followed by sync of just the
two generated applications. Avoid syncing unrelated fleet changes.

For each target context, verify after reconciliation:

```bash
kubectl get crd valkeyclusters.valkey.io valkeynodes.valkey.io
kubectl -n valkey-operator-system rollout status deployment/valkey-operator-controller-manager
kubectl -n valkey-operator-system get role,rolebinding,service
kubectl -n valkey-operator-system get valkeyclusters,valkeynodes
```

Both CRDs must be Established. The manager must acquire its leader lease,
start both controllers without cache/RBAC errors and remain ready. No instances
are expected for the operator alone. For future instances, validate actual
authentication, replication, persistence, failover, and client write/read along
with the [controller conditions](https://github.com/valkey-io/valkey-operator/blob/v0.7.0/docs/status-conditions.md);
Argo CD health alone is insufficient. Do not print Secret values during inspection.

## Upgrade, rollback and deletion

Update the manifest commit, appVersion and image digest together. Apply CRDs
before controller upgrades; v0.7.0 adds required fields and pod deletion RBAC
and may recreate StatefulSets during a roll. Review the release notes and inspect
all instances before any upgrade. Roll back through Git to verified pins;
CRD downgrade and data compatibility require separate review once instances exist.

The CRDs and Namespace use `Prune=false,Delete=false` to prevent accidental
cascading deletion through Argo CD. Deliberate uninstall must account for these
retained resources. Remove instance claims only after assessing backups,
owner references, finalizers and storage reclaim policies, while keeping the
operator available to finish cleanup. Persistence
[`reclaimPolicy`](https://github.com/valkey-io/valkey-operator/blob/v0.7.0/api/v1alpha1/persistence_types.go)
defaults to `Retain`; `Delete` enables node-finalizer cleanup of PVCs. Retained
PVCs are not backups or proof of recoverability. Never delete the Namespace or
CRDs as a routine operator uninstall while instances/data remain.
