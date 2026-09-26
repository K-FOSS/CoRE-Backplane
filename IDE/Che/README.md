# Eclipse Che operator

This Lovely rendering unit deploys the [upstream Eclipse Che Helm chart](https://github.com/eclipse-che/che-operator/blob/7.122.0/README.md),
pinned to 7.122.0, with a Kustomize patch for two operator replicas and a
16m CPU request. The Helm chart installs the operator, its RBAC, and CheCluster
CRD directly; this chart does not create an OLM Subscription.

[`Apps/Development/CheIDE.yaml`](../../Apps/Development/CheIDE.yaml) selects
production clusters for tenant `core.mylogin.space`: Home1 Talos, DC1 Talos,
and DC1 K3s. The ApplicationSet uses the Lovely renderer with no injected values
and targets `eclipse-che`. Only the Home1 Development application currently
enables a CheCluster. Its workspace settings and Codex activity policy are
owned by [`Development`](../../Development/README.md#eclipse-che).

Version 7.122.0 is required for the native CLI activity tracker. See the
[release notes](https://github.com/eclipse-che/che/releases/tag/7.122.0),
[operator source](https://github.com/eclipse-che/che-operator/tree/7.122.0), and
[CLI watcher configuration](https://github.com/eclipse-che/che-machine-exec/blob/7.122.0/timeout/CLI-WATCHER.md).
Reconcile the operator and established CRD before applying the Development
CheCluster policy. Validate operator availability, the installed CRD fields,
CheCluster Active status, editor definitions, and workspace startup.
Existing workspace editor contributions may retain older images; plan restarts
and select the released editor through the dashboard before relying on the
watcher. Do not restart running Codex sessions for this rollout.

Disable activity tracking in the Development CheCluster to roll back the
feature. Avoid downgrading the CRD/controller while its new fields are in use.
Removing this operator does not establish that workspace storage was removed;
inspect CheCluster and DevWorkspace finalizers and PVC retention before deletion.
