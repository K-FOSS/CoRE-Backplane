# Development Git HTTP routing

The [Development ApplicationSet](../Apps/Development/DevelopmentStack.yaml)
deploys a shared anonymous clone/fetch endpoint on both Forgejo-enabled
production sites. See the [Development stack overview](README.md) for the
parent stack and Forgejo's storage, identity, and mirror lifecycle.

## Ownership, targets, and rendering

`core-backplane-development` selects the Development fleet and injects
`gitHttp` values into the Lovely Helm/Kustomize rendering unit. The first
matrix list element contains sibling `repos` and `clusters` lists: `repos`
declares shared repository aliases; `clusters` declares deployment targets
and their Forgejo hostnames. Git HTTP is enabled wherever Forgejo is enabled:
`core-home1-talos-prod` and `core-dc1-talos-prod`, in `core-prod`. It is disabled
on `dc1-k3s-node1`.

Each enabled target renders a Deployment with two replicas, a Service, a
ConfigMap containing configuration and the router, an HTTPRoute, and a
PodDisruptionBudget. Resource names are `<Development release>-git-http`.
The Deployment, Service, ConfigMap, and route use the pinned
[BJW-S common 3.7.1 library](https://github.com/bjw-s-labs/helm-charts/tree/common-3.7.1/charts/library/common).
The PDB uses a direct manifest because that library version does not implement
PDBs. The [template](templates/Forgejo/GitHTTP.yaml) is merged into the existing
[common rendering entry point](templates/00-common.yaml).

The router uses a digest-pinned
[official Python slim image](https://github.com/docker-library/python/tree/master/3.13/slim-bookworm)
and the standard library's
[HTTP handler](https://docs.python.org/3.13/library/http.server.html) and
[HTTPS client](https://docs.python.org/3.13/library/urllib.request.html).
No new service identity, database, persistent volume, or Secret is required.
Prerequisites are the existing Gateway, Gateway API HTTPRoute support,
ExternalDNS, reachable HTTPS forge origins, and anonymous read access to each
allowed repository.

## Repository configuration

Add repositories beside `clusters` in the ApplicationSet's first matrix list
element. `owner` consistently means an organization or user namespace:

```yaml
repos:
  - repoName: 'CoRE-Backplane'
    path: '/CoRE/CoRE-Backplane.git'
    github:
      owner: 'K-FOSS'
      weight: 0
    clusters:
      - clusterName: 'core-home1-talos-prod'
        owner: 'CoRE'
        weight: 100
      - clusterName: 'core-dc1-talos-prod'
        owner: 'CoRE'
        weight: 100
```

`path` is the client-facing alias and defaults to `/<repoName>.git`. It may
also contain one owner component, independently of backend owners. Backends
use the same `repoName`; site URLs are derived from the deployment list's
`values.forgejo.hostname`. Repository `clusterName` values must match enabled
sites exactly. Omit `github` to disable that repository's GitHub fallback.
Each repository needs at least one backend; at most sixteen repositories fit
one HTTPRoute. Invalid or ambiguous configuration fails router startup.

For a standalone Helm deployment, configure `gitHttp.enabled`, `hostname`,
`sites`, and `repos` in [values.yaml](values.yaml). `sites` entries contain
`clusterName` and a credential-free HTTPS `url`; `repos` has the same shape as
the fleet list. Set `cluster.name` to the receiving site's identity.
Fleet-injected values take precedence over standalone defaults.

Selection is deterministic: the receiving site's Forgejo is first, peer
Forgejos follow, and GitHub is last. Higher weights are tried first within a
tier; equal weights retain configuration order. Weight zero remains eligible
as the lowest priority and does not disable a backend. Weights do not distribute
traffic between healthy sites or override site locality.

The router checks each candidate's anonymous smart Git advertisement, requiring
a successful Git content type and packet header. Authentication pages, HTTP
errors, TLS failures, and upstream redirects fail the check. Defaults are a
two-second timeout, five-second health cache, and thirty-two concurrent
connections per replica; these are values-driven. All failed candidates return
503. Reachability does not prove mirror freshness: compare advertised commits
and monitor Forgejo synchronization separately.

### Logs and metrics

The process writes one-line JSON events to container standard output. Normal
request events contain only the method, response status, allowlisted repository
name, fixed operation class, selected backend, and a bounded reason code. They
never include request paths, query strings, headers, cookies, redirect URLs, or
request bodies. The `CoRE-Git-HTTP` server access logger remains disabled for
the same reason. Startup events contain only the cluster name and configured
backend counts. Alloy's Kubernetes pod-log pipeline therefore sends these
events to the shared Loki service with the normal workload labels.

The internal Service exposes Prometheus text metrics at `/metrics`; the public
HTTPRoute has no `/metrics` match. A `ServiceMonitor` scrapes the endpoint every
30 seconds for Alloy, using the Prometheus Operator
[ServiceMonitor](https://prometheus-operator.dev/docs/api-reference/api/#servicemonitor)
resource. The bounded metric families are:

| Metric | Meaning |
| --- | --- |
| `git_http_requests_total` | Request method, fixed operation class, response status, and allowlisted repository. |
| `git_http_backend_probes_total` | Anonymous backend probe result by configured backend name. |
| `git_http_backend_selections_total` | Redirects that selected each backend. |
| `git_http_backend_healthy` | Last observed health result for each backend. |
| `git_http_repositories_configured` | Number of configured repository aliases. |

The router does not expose a public metrics or log-ingest route. Alert on
non-zero 5xx request rates, `git_http_backend_healthy == 0` for the local and
peer backends, absent `up` for the ServiceMonitor, and a sustained increase in
unhealthy probes. Correlate redirect events with Gateway access logs and the
selected Forgejo's own access and mirror logs; the router deliberately omits
client identity and URL details.

## Request and security boundaries

The public URL is:

```sh
git clone https://core-prod.writemy.codes/CoRE/CoRE-Backplane.git
```

The [Gateway API HTTPRoute](https://gateway-api.sigs.k8s.io/guides/user-guides/http-routing/)
matches only two exact paths for each allowed repository:

| Method | Suffix | Required operation |
| --- | --- | --- |
| GET | `/info/refs` | Query parameter `service=git-upload-pack`, with no additional parameters. |
| POST | `/git-upload-pack` | Git upload-pack request content type and no query. |

These are the smart clone/fetch operations defined by the
[Git HTTP protocol](https://git-scm.com/docs/http-protocol).
The router returns a temporary 307 redirect to the selected backend, preserving
the operation suffix and discovery query. Git's default
[`http.followRedirects=initial`](https://git-scm.com/docs/git-config#Documentation/git-config.txt-httpfollowRedirects)
follows initial discovery and uses the resulting forge URL for subsequent
requests. Failover happens before the redirect; a failed transfer after that
point requires a new client attempt. Redirects are not cached.

Push discovery, `git-receive-pack`, dumb HTTP object access, Git LFS, web pages,
APIs, unlisted repositories, and health checks have no public route. The router
also validates methods, queries, and POST content type and rejects Authorization
or Proxy-Authorization headers. Probes do not forward client headers, cookies,
credentials, or repository request bodies, use no environment proxy, validate
TLS, and never follow upstream redirects. Use a forge's direct URL for private
repositories or authenticated operations. Readiness checks verify the router
itself, independently of backend outages, so a healthy replica can still serve
503 when all mirrors are unavailable.

The pod runs as UID/GID 65532 with a read-only root filesystem, dropped
capabilities, no privilege escalation, and no service-account token. It stores
no repository data and logs no request URLs or headers. The HTTPRoute attaches
to the configured HTTPS Gateway listener and carries `wan-mode: 'public'` for
public ExternalDNS and `lan-mode: 'private'` for site-local DNS. Local preference
means the site whose Gateway receives the request; external clients follow the
existing DNS/Gateway site selection. The router does not change that selection.

## Verification and recovery

Run the focused tests and render with each target's ApplicationSet-injected
Helm and Kustomize layers before publishing:

```sh
python3 -m unittest discover -s Development/tests -v
helm lint Development --strict -f /tmp/site-development-values.yaml
helm template core-home1-talos-prod-development Development --namespace core-prod \
  --api-versions gateway.networking.k8s.io/v1/HTTPRoute \
  -f /tmp/site-development-values.yaml
```

`/tmp/site-development-values.yaml` must contain the actual rendered
`LOVELY_HELM_MERGE` values; the filename is illustrative. Helm output must also
pass through the injected Lovely Kustomize patches. Resolve the existing
pinned dependencies locally, as described in the stack overview.

Publish through the [Git and Argo CD procedure](../docs/OPERATIONS.md#agent-git-and-argo-cd-procedure).
Sync only the owning ApplicationSet in the Apps parent, then the five router
resources in the two affected Development Applications at the reviewed commit.
These resources have no sync hooks or dependencies on Development's migration
hooks. Selective sync skips unrelated hooks; inspect current operations before
requesting a sync.

Verify two ready replicas, Service endpoints, the PDB selector, HTTPRoute
`Accepted`/`ResolvedRefs`, ServiceMonitor target discovery, `/metrics` output,
JSON stdout events, TLS, and DNS. Check redirects through each site's
Gateway and compare the `Location` with the expected local Forgejo, then run
`git ls-remote` and clone/fetch using the shared URL. Confirm push discovery and
unlisted paths return no redirect. Tests cover peer/GitHub fallback and all
backends failing without disrupting a running Forgejo.

Rollback by publishing a corrective/revert commit and reconciling the same
owners. Removing a repository removes its route matches and cached backend
configuration after rollout; it does not delete repositories or Forgejo mirror
jobs. Disabling Git HTTP removes its rendered resources, but prune-disabled
syncs leave existing resources until an explicit scoped prune is reviewed.
Router removal has no database, identity, or repository-storage deletion effect.
