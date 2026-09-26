# Cilium policy enforcement rollout

## Current state and ownership

[`Apps/Network/Base.yaml`](../../Apps/Network/Base.yaml) owns Cilium on
`core-home1-talos-prod` and `core-dc1-talos-prod`. Its cluster-secret selector
requires the CoRE tenant, bare-metal compute, and infra node-type labels; its
list generator supplies the two site configurations. Lovely combines this
chart, Kustomize, and the ApplicationSet's Helm and Kustomize merge layers.

The checked-in Helm values set `cilium.policyEnforcementMode: 'default'` with
`cilium.policyAuditMode: true` and BPF policy verdict events enabled for both
selected sites. Policies are evaluated, but audit mode permits traffic that
would otherwise be denied. Hubble and the host firewall remain disabled.
Read-only inspection on 2026-09-26, before these changes were reconciled,
confirmed both sites still had `enable-policy: never` and no daemon audit
setting. Repository intent is not proof that live agents have adopted it.

The intended first enforcement mode is `default`: only selected endpoints and
directions become isolated. `always` would also isolate workloads without
policies and is outside this initial rollout. See Cilium's
[policy enforcement modes](https://docs.cilium.io/en/v1.20/security/policy/intro/).
Audit mode is an observation phase, not an enforced security boundary.

## Inventory before changing the agent

Inventory both clusters separately. Include chart- and operator-generated
policies, Cilium policies, and node overrides; Git searches alone miss them.
Use an explicit kubeconfig context for the intended site:

```console
kubectl --context CONTEXT get networkpolicies.networking.k8s.io -A -o yaml
kubectl --context CONTEXT get ciliumnetworkpolicies.cilium.io -A -o yaml
kubectl --context CONTEXT get ciliumclusterwidenetworkpolicies.cilium.io -o yaml
kubectl --context CONTEXT get ciliumnodeconfigs.cilium.io -A -o yaml
kubectl --context CONTEXT get pods -A -o wide
```

`CONTEXT` is a literal placeholder to replace with a verified context. Do not
export Secrets or credentials with the inventory. Match each policy selector
against actual pod labels, named container ports, and namespace labels. Review
the union of all policies selecting a pod in each direction, rather than
assuming one policy alone describes its effective permissions.

Observed Home1 policies needing review include:

| Consumer | Existing behavior when enforcement becomes active | Verification |
| --- | --- | --- |
| CyberChef and IT Tools | Egress selected with no allow rules | Load assets and exercise tools; distinguish browser requests from server egress. |
| Insight | Ingress restricted to the main Gateway's Envoy pods | Validate actual Envoy labels, HTTP backend port, public authentication, and direct-access rejection. |
| Tempo operator | Deny-all plus API, metrics, and webhook exceptions | Exercise reconciliation and admission; verify API destination ports after service translation and any DNS dependency. |
| Kafka | Operator-generated ingress policies | Check controller and broker traffic, clients from other namespaces, metrics, and cross-site consumers. |
| Dragonfly | Application and operator policies | Verify Redis and Memcached consumers, operator management traffic, and the additive union of policies. |
| ExternalDNS | Ingress limited to metrics; egress allowed | Verify metrics collection and actual DNS provider reconciliation. |

These observations are an initial inventory, not a complete fleet audit. Policies
and workload placement can change. Trace each consumer to its owning `Apps/`
ApplicationSet and full renderer before editing its implementation.

## Audit, then enforce one site

### DC1 candidate restrictions

`policyRollout` in [`values.yaml`](values.yaml) and
[`WorkloadRestrictions.yaml`](templates/Policy/WorkloadRestrictions.yaml) add
three candidate CCNPs only when the ApplicationSet-injected `cilium.cluster.name`
is in `policyRollout.clusters` (initially DC1 only). Helm fails for that target
unless policy mode is `default` and daemon audit mode is enabled. This is a
render-time safety check, not an admission control or proof of live settings.
Check every agent before syncing; individual endpoint overrides must also be
inventoried. Keep Home1 outside this first batch.

| Candidate | Selected direction | Allowed dependencies |
| --- | --- | --- |
| Envoy Gateway controller | Egress | Local Kubernetes API entity TCP/443,6443; selected CoreDNS pods UDP/TCP/53. Controller ingress, including xDS, is unchanged. |
| Longhorn manager | Ingress | Longhorn namespace TCP/9500–9503; API-server entity TCP/9501,9502 for webhooks; site Alloy collectors TCP/9500 for metrics. |
| Longhorn UI | Ingress | Main Gateway's Envoy pods in `kube-system`, TCP/8000 (the Service exposes port 80). |

All selectors and ports are configurable. No L7 rules, explicit deny rules,
node firewall, or global default-deny are added. Unselected directions remain
unchanged. Existing policies contribute additive allowances and can broaden
the effective union. Node probes may be implicitly allowed by Cilium's host
behavior; these candidates do not isolate local node traffic.

Ownership is centralized in Network/Base for this initial Cilium-CRD audit
batch. Direct CCNP manifests are intentional: entity matching and audit
default-deny control are not supported by the common chart's ordinary
NetworkPolicy abstraction. Longhorn workload/chart ownership stays with
[`Apps/Storage/Base.yaml`](../../Apps/Storage/Base.yaml); collector identity is
owned by [`Apps/Observability/Collectors.yaml`](../../Apps/Observability/Collectors.yaml).
See [Envoy Gateway deployment modes](https://gateway.envoyproxy.io/v1.8/tasks/operations/deployment-mode/),
[Cilium entities](https://docs.cilium.io/en/stable/security/policy/layer3/),
and [policy audit mode](https://docs.cilium.io/en/stable/security/policy-creation/).

Read-only DC1 connection-tracking snapshots on 2026-09-26 showed controller API
connections on TCP/6443, Envoy xDS TCP/18000, Alloy-to-manager TCP/9500,
Longhorn webhook TCP/9502, instance-manager TCP/8501,8503, node iSCSI TCP/3260,
NFS TCP/2049, DNS, and external HTTPS. Connection-tracking entries can be stale
and include reverse and related entries; their counts are not request counts,
and raw tuple field names do not establish the connection initiator. This is
an IPv4 snapshot, not complete flow history or IPv6/recovery coverage.

Engine/replica, CSI, share-manager/NFS, backup traffic and all Longhorn egress
remain unrestricted by this batch. Manager admission and recovery traffic are
critical: verify both Kubernetes API entity classification and namespace
identities during provisioning, recurring jobs, rebuilds, and reattachment.
UI access must pass the existing Authentik/Gateway path; no authentication or
RBAC changes are made. Exercise controller reconciliation and Gateway config
updates rather than treating an established API watch as complete coverage.

After reconciliation, capture verdicts on all nodes using the commands below.
For local regression validation, run `bash tests/policy-rollout.sh DC1_VALUES
HOME1_VALUES` with locally generated ApplicationSet-injected values files and
resolved chart dependencies. The script requires Helm, `rg`, and jq-backed
`yq`; it tests both sites, disabled candidates, and unsafe-mode render failures.
It leaves generated render outputs in a private `/tmp/network-policy-tests.*`
directory; do not commit or publish rendered Secrets.

Any would-be denial requires mapping its local endpoint and peer identity to
the owning stack. Do not blindly allow denied traffic: reject probes/unwanted
access and allow only an established workload dependency. Exercise normal and
scheduled/recovery workflows over a representative operating interval before
graduating these policies. The initial short passive window is insufficient
to approve enforcement.

Disable individual candidate `enabled` switches, or `policyRollout.enabled`,
through Git to remove this batch from desired state. Ensure Argo actually
prunes the CCNPs; omitting them from a render alone does not delete live rules.
Rollback removes the candidate isolation, not workloads, storage, or the
separate additive API policy. Enforcement graduation requires a reviewed
change to the render guard and per-site controls; do not simply remove the
guard to clear a sync failure.

### Visibility and remaining backlog

Hubble and BPF trace events are currently disabled. Policy verdict monitoring
does not provide complete traffic discovery for unselected workloads. Use
read-only `cilium-dbg bpf ct list -o json` snapshots on each node to supplement
the pod/endpoint inventory, keeping metadata in restricted temporary storage.
Do not collect packet payloads, pod environment values, or Secrets. Flow
observability changes require a separate agent rollout and capacity/privacy
review; no observability agent setting is changed by these candidate policies.

Next batches should follow their own ApplicationSets: shared data services
and consumer identities, cert-manager/admission controllers, Argo/Crossplane
and remote API endpoints, telemetry scrapers/exporters, then application
ingress and egress. Preserve the storage recovery plane while exercising its
full matrix. This first batch is not complete coverage of the 214 endpoints
previously observed without policy enforcement in either direction.

The current shared values enable the audit stage on both sites. Sync and
observe each site's Application independently. Before any enforcement cutover,
add per-site rollout values to the owning ApplicationSet so one site can remain
audited while the other enforces. Do not turn off audit mode in the shared
values as the first enforcement step.

### Preserve controller API access

The base chart owns `core-network-api-access`, an additive
`CiliumClusterwideNetworkPolicy`. Its `apiAccessPolicy.clients` select Envoy
Gateway, ExternalDNS, Cilium components, PureLB, and FRR-K8s in `kube-system`.
The selectors use stable component labels, not pod names or release revisions.
It permits the `kube-apiserver` entity on TCP/443 and TCP/6443 and sets
`enableDefaultDeny.egress: false`; installing this policy alone does not isolate
the selected workloads. Existing isolating policies still require every other
dependency, including DNS, to be allowed. Explicit Cilium deny rules take
precedence over this allowance.

This CRD is a direct manifest because the policy needs Cilium entity matching
and `enableDefaultDeny`, beyond ordinary Kubernetes NetworkPolicy semantics.
See [Cilium entity policies](https://docs.cilium.io/en/v1.20/security/policy/layer3/)
and [default-deny control](https://docs.cilium.io/en/v1.20/security/policy/intro/).

For other API-driven services, add the pod-template label
`network.core.mylogin.space/api-client: 'true'` beside the consuming workload
in its owning rendering unit. This opt-in grants network reachability only;
it does not grant Kubernetes RBAC. Review admission to this label as part of
the workload's access model. Inventory Crossplane and its providers/functions,
Argo CD, External Secrets, cert-manager, CoreDNS, storage/CSI controllers,
operators, monitoring discovery, and backup controllers. Review their target
clusters and kubeconfig endpoints: remote APIs or API proxies are not
automatically covered by the local `kube-apiserver` entity.

Read-only Home1 inspection on 2026-09-26 found the Kubernetes Service listening
on TCP/443 with its EndpointSlice pointing to TCP/6443. Recheck both sites at
cutover; do not assume that allowing Service port 443 alone covers translated
traffic. Inspect Cilium's endpoint identities and audit verdicts to verify
`kube-apiserver` classification rather than adding broad node/world allowances.

Cilium agents and operators currently use host networking. The agent's Helm
configuration uses Talos KubePrism at `localhost:7445`. Keep the host firewall
disabled for this pod-policy rollout; a pod endpoint selector does not protect
or isolate this host path. Any future host-policy rollout must separately
preserve KubePrism and its upstream API traffic. See
[Cilium's Talos installation](https://docs.cilium.io/en/v1.20/installation/k8s-install-helm/)
and [host firewall recovery](https://docs.cilium.io/en/v1.20/security/host-firewall/).

Before leaving audit mode, verify every selected controller can create fresh
API connections and resume list/watch and leader-election operations. Exercise
Envoy Gateway route reconciliation and certificate generation, Cilium node and
endpoint reconciliation, and one reconciliation for each opted-in controller.
Verify API-to-webhook ingress separately; API egress does not allow admission
callbacks or Envoy xDS connections. A running pod or an existing watch is not
proof of recovery after connection loss. Remove opt-in labels on retirement;
delete the base policy only after replacing its grants at the consumers.

1. Review the complete generated Applications before syncing the audit stage.
   Add explicit per-site rollout values before enforcement so Home1 and DC1
   can advance independently; sites awaiting cutover remain in audit mode.
2. For the first site, render `policyEnforcementMode: 'default'` together with
   `policyAuditMode: true`. Enable `bpf.events.policyVerdict.enabled` and verify
   an observation path using `cilium-dbg monitor --type policy-verdict`, or
   configure Hubble with TLS and scoped access. Preserve normal drop events.
   Resolve and validate the exact Cilium 1.20.2 chart before relying on keys.
3. Sync that site's network Application through Argo CD. Verify the effective
   configuration on every agent, including node overrides, and wait for its
   controlled rollout. Other Applications must not roll out incidentally.
4. Exercise normal and recovery workflows while collecting audit verdicts:
   DNS over UDP/TCP, API access, Authentik, Vault/External Secrets, ingress,
   database access, storage, metrics, backup, jobs, and cross-cluster Services.
   Include pod recreation and scheduled jobs; passive observation of existing
   connections is insufficient. Review audit denials against intended access.
5. Correct policies beside their owning applications using the pinned BJW-S
   library where supported. Verify both permitted and prohibited traffic.
   Do not create a cluster-wide allow-all policy to hide missing dependencies.
6. Set `policyAuditMode: false` for this site while retaining `default`.
   Observe the rollout and repeat workflow checks and negative tests. Advance
   the second site only after the first site's acceptance checks pass.

Cilium documents the audit workflow, verdict observation, and its L3/L4 scope
in [creating policies from verdicts](https://docs.cilium.io/en/v1.20/security/policy-creation/).
Per-endpoint audit settings are temporary and reset with agent restarts; prefer
the Git-owned daemon setting for this rollout. Node-specific settings are
documented in [per-node configuration](https://docs.cilium.io/en/v1.20/configuration/per-node-config/).

## Policy boundaries and acceptance

Begin with application selectors, not a namespace-wide default deny. Under
`default`, unselected workloads remain open; track coverage explicitly rather
than describing this stage as complete tenant isolation.

For each workload, record ingress callers, egress dependencies, ports,
namespaces, identity labels, health probes, and operational/recovery callers.
Allow DNS deliberately when isolating egress. Use actual translated destination
ports and verify source identities through LoadBalancer, DSR, and Gateway paths.
Check both IPv4 and IPv6 at Home1 and remote ClusterMesh identities; namespace
and cluster scoping must match the intended caller. Validate negative tests
from an unrelated workload and from outside the intended namespace/site.

Keep host firewall adoption separate. Pod policies do not provide general host
or Multus/SR-IOV interface isolation; trace the actual datapath before claiming
coverage. See [policy troubleshooting](https://docs.cilium.io/en/v1.20/operations/troubleshooting/)
and [host firewall guidance](https://docs.cilium.io/en/v1.20/security/host-firewall/).

Acceptance requires effective agent configuration, selected endpoint policy
state, successful user/recovery workflows, expected denials, and no unexplained
policy drops. Pod readiness or Argo CD health alone is insufficient.

### Longhorn is a required cutover gate

Daemon audit mode covers L3/L4 policy, not L7 proxy enforcement. Inventory any
HTTP, Kafka, or other L7 rules before reconciliation; do not treat this setting
as a dry run for those rules. See [Cilium policy audit mode](https://docs.cilium.io/en/stable/security/policy-creation/).

Longhorn is critical shared storage. Keep audit mode enabled until its normal
and recovery paths have been verified on the site being considered for
enforcement. Start from [`Apps/Storage/Base.yaml`](../../Apps/Storage/Base.yaml)
and the full [`Storage/Base`](../../Storage/Base/README.md) rendering unit.
Inspect actual engine, replica, manager, CSI, and application pod placement and
labels; pod readiness alone does not prove volume I/O or recovery works.

Verify controller API watches, fresh CSI provisioning and attachment, mounts
and read/write I/O from application pods, cross-node engine/replica traffic,
replica rebuilds, snapshots, configured backups, and volume reattachment after
application pod recreation. Schedule any disruptive rebuild/failover tests in
an approved maintenance window using a disposable test volume; do not delete
production replicas or detach production volumes merely to generate traffic.
Collect policy verdicts from every involved node during each workflow. Absence
of denials without exercising rebuild and recovery traffic is insufficient.

Compare results with Longhorn's [architecture](https://longhorn.io/docs/1.11.3/concepts/)
and [network requirements](https://longhorn.io/docs/1.11.3/references/networking/),
then verify against the installed version. Audit mode does not eliminate agent
rollout risk, replace storage backups, or enforce isolation for host-network
traffic. Any unexplained denied verdict or I/O/recovery failure blocks cutover.

### Verify daemon settings and observe verdicts

```console
kubectl --context CONTEXT -n kube-system get configmap cilium-config \
  -o jsonpath='{.data.enable-policy}{"\n"}{.data.policy-audit-mode}{"\n"}{.data.bpf-events-policy-verdict-enabled}{"\n"}'
kubectl --context CONTEXT -n kube-system get pods -l k8s-app=cilium -o wide
kubectl --context CONTEXT -n kube-system exec CILIUM_POD -c cilium-agent -- \
  cilium-dbg config
kubectl --context CONTEXT -n kube-system exec CILIUM_POD -c cilium-agent -- \
  cilium-dbg monitor --type policy-verdict
```

Replace `CONTEXT` and `CILIUM_POD` with verified site and pod names. Expected
ConfigMap values are `default`, `true`, and `true`. Verify effective daemon
configuration for every agent after rollout, not just the ConfigMap. The
monitor streams live events; these are not automatically persisted in normal
container logs. Capture a bounded observation interval in the operational
logging workflow and treat flow metadata as sensitive. Include allowed and
would-be denied flows; verify audit verdicts before relying on the stream.

## Recovery

Before enforcement, verify independent console/Talos and Kubernetes access and
the ability to reconcile Git without relying solely on an isolated workload.
Roll back the affected site's rollout values through Git and Argo CD to its
previous audited state. Audit mode permits traffic again but removes policy
protection; restoring `never` similarly disables enforcement. Agent rollout
and endpoint regeneration take time, so verify effective state on every node.

Do not delete the Application to roll back: resource preservation can leave
unmanaged policies and controllers. If an incident requires direct agent or
endpoint changes, record them and reconcile them back to Git. Explicitly
confirm audit mode is disabled again before declaring enforcement restored.
