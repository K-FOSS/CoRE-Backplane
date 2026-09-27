# Resource operations deployment

This deployment installs Goldilocks and Descheduler and exposes Goldilocks
through Authentik/Gateway policy. It is owned by
`Apps/Infra/Resources.yaml`.

Each selected infrastructure cluster creates its own Terraform
[`authentik_provider_proxy` and `authentik_application` resources](https://registry.terraform.io/providers/goauthentik/authentik/2025.10.1/docs)
through a Crossplane `Workspace`. The application is filed under the
`<datacenter>-<cluster>` Authentik group and grants access to the existing
`Server Admins` group. The generated provider host and application slug include
the cluster identity, so reconciliation remains scoped to that cluster. The
ApplicationSet supplies `cluster.domain` for in-cluster DNS and separately sets
the public `domain` to `resolvemy.host` for the Goldilocks route and Authentik
proxy provider. The proxy provider name is scoped by environment, region, and
cluster, while the application display name remains `Goldilocks`.

The Goldilocks `HTTPRoute` is protected by an Envoy Gateway
[`SecurityPolicy` external-authorization check](https://gateway.envoyproxy.io/v1.8/tasks/security/ext-auth/)
against the shared Authentik proxy service in `core-prod`. Source-IP consistent
hashing keeps a client on the same proxy replica so Authentik's local
authorization/session cache can be reused. Successful authorization responses
forward Authentik identity, authorization, redirect, and cookie headers to
Goldilocks.

Goldilocks/VPA recommendations are advisory unless another process applies
them. Descheduler can evict workloads across the cluster. Review policies,
eviction limits, PDBs, priority classes, local storage and maintenance windows
before enabling new strategies.

Verify the Terraform `Workspace` is `Ready`, then confirm the Authentik proxy
provider, application grouping, entitlement, and policy bindings. Verify the
`SecurityPolicy` is accepted and attached to the Goldilocks `HTTPRoute`, and
test both an authorized `Server Admins` session and an unauthorized session
through the public hostname. Removing the release removes the Kubernetes
workspace and policy; allow the Terraform workspace deletion to finish so its
Authentik resources are destroyed before forcing finalizer removal.

Validate recommendations against observed workload behavior and canary
descheduling on non-critical workloads before fleet rollout.

## Initial live sizing sweep (2026-09-27)

The first Talos inventory checked regular containers in `Running` Pods using
the Pod specifications in the YVR `logged-user` context and the YXL
`core-dc1-talos-prod` context. Counts below are **container instances**, so a
three-replica workload contributes three instances. The sweep did not include
init containers. It flags absent request or limit fields only; an absent limit
is not by itself a sizing defect, and a present value is not proof that it is
appropriate. The `core-*` figures are the application-namespace subtotal; the
all-namespace total also includes system and operator workloads.

| Site / context | Running regular container instances with a request or limit missing (all namespaces) | Missing both requests and limits (all namespaces) | `core-*` instances with any missing resource field | `core-*` instances missing both |
| --- | ---: | ---: | ---: | ---: |
| YXL / `core-dc1-talos-prod` | 217 | 166 | 77 | 71 |
| YVR / `logged-user` | 318 | 253 | 120 | 105 |

Every flagged instance lacked a memory or CPU limit (or both); 166 YXL and 253
YVR instances lacked both requests and limits. These counts are an initial
inventory, not a workload-by-workload remediation list. Workload ownership,
controller defaults, actual demand over time, and whether a limit is
appropriate still need review before changing values.

At the time of the sweep neither cluster had any `VerticalPodAutoscaler`
objects, and the inspected `core-*` namespaces were not opted in to Goldilocks
with `goldilocks.fairwinds.com/enabled: 'true'`. Goldilocks is installed, but
there are no namespace recommendations to use as a sizing signal yet. Its
[FAQ](https://goldilocks.docs.fairwinds.com/faq/) describes namespace opt-in;
the [advanced usage guide](https://goldilocks.docs.fairwinds.com/advanced/)
documents its VPA recommendation setup. Kubernetes explains the distinction
between resource requests and limits in its
[container resource management documentation](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
and the VPA object and recommendation model in the
[Vertical Pod Autoscaling guide](https://kubernetes.io/docs/concepts/workloads/autoscaling/vertical-pod-autoscale/).

The next review should group flagged Pod instances by owning controller, then
compare requests with representative CPU and memory history and application
behavior. A single `kubectl top` sample is useful for finding workloads to
inspect, but it is not a capacity baseline. Treat shared databases, storage,
networking, telemetry, AI/voice services, and VM launcher containers as
separate reviews: their ownership and safe resource controls differ, and
operator-managed or guest-memory sizing must be understood before editing
their templates. Record the owning chart or operator, the evidence window,
proposed values, and post-change observations here as each review is completed.

### Current usage sample (2026-09-27)

To add usage evidence, the Kubernetes Metrics API was sampled at
`2026-09-27T02:45:40Z` in YVR and `2026-09-27T02:45:49Z` in YXL. Its
measurement windows were about 23 and 20 seconds, respectively. For each
cluster, the following is the arithmetic mean of CPU and memory usage across
the listed running regular-container instances at that sample. “Any resource
field absent” means the container has no `requests` map or no `limits` map;
“neither set” means both maps are absent or empty. All instances in these
cohorts had a matching Metrics API sample.

| Site / context | Cohort | Containers averaged | Mean CPU | Mean memory |
| --- | --- | ---: | ---: | ---: |
| YVR / `logged-user` | Any resource field absent, all namespaces | 318 | 16.5m | 173.6Mi |
| YVR / `logged-user` | Neither requests nor limits set, all namespaces | 253 | 12.6m | 155.1Mi |
| YVR / `logged-user` | Any resource field absent, `core-*` namespaces | 120 | 11.3m | 185.4Mi |
| YVR / `logged-user` | Neither requests nor limits set, `core-*` namespaces | 105 | 12.9m | 210.5Mi |
| YXL / `core-dc1-talos-prod` | Any resource field absent, all namespaces | 216 | 38.2m | 551.9Mi |
| YXL / `core-dc1-talos-prod` | Neither requests nor limits set, all namespaces | 165 | 36.6m | 589.2Mi |
| YXL / `core-dc1-talos-prod` | Any resource field absent, `core-*` namespaces | 76 | 60.2m | 1,199.3Mi |
| YXL / `core-dc1-talos-prod` | Neither requests nor limits set, `core-*` namespaces | 70 | 65.4m | 1,300.9Mi |

These are cross-container averages from one short Metrics API sample, **not**
per-workload averages over time, percentiles, or recommended requests and
limits. Large-memory workloads can pull up the mean; use per-workload history
and representative peak/idle behavior before drawing sizing conclusions. The
initial Pod-spec counts above are a separate earlier snapshot and can differ
slightly as Pods roll or workloads change.

The full YVR/Home1 snapshot, grouped by namespace, owning workload, and
container, is recorded in the
[YVR running-workload usage report](YVR-Home1-Usage-2026-09-27.md). It includes
the request values, current usage mean and maximum across replicas, and the
usage-to-request ratio where a uniform request is present.
