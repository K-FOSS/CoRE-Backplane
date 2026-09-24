# Business workloads

The ApplicationSets in this directory are the fleet owners for production
business workloads rendered from the
[CoRE-Business repository](https://github.com/K-FOSS/CoRE-Business). They
select registered Argo CD clusters, inject the site-specific values required by
each chart, and reconcile into the target cluster's `core-prod` namespace.

## Mail

[Mail.yaml](Mail.yaml) owns the production
[CoRE Mail chart](https://github.com/K-FOSS/CoRE-Business/tree/main/Mail). Mail
is an active production service and is no longer classified as a wholly legacy
stack. The `dc1-k3s-node1` deployment remains as a compatibility target while
the DC1 and Home Talos deployments are production targets; its presence does
not make the Talos deployments non-production.

The merge generator limits Mail to these explicitly approved production
clusters and requires exactly one entry to be marked as the credential hub:

| Argo CD cluster | Role | Site | LDAP | PostgreSQL and S3 providers | Dragonfly credentials |
| --- | --- | --- | --- | --- | --- |
| `dc1-k3s-node1` | Credential hub | `dc1/yxl` | `ldap-dc1.mylogin.space` | `psql-dc1-yxl`, `s3-yxl-dc1-core` | Legacy compatibility alias |
| `core-dc1-talos-prod` | Spoke | `dc1/yxl` | `ldap-dc1-talos.mylogin.space` | `psql-dc1-yxl`, `s3-yxl-dc1-core` | Site-local path |
| `core-home1-talos-prod` | Spoke | `home1/yvr` | `ldap-home1.mylogin.space` | `psql-home1-yvr`, `s3-yvr-home1-core` | Site-local path |

For each target, the ApplicationSet derives the destination API server,
environment, cluster DNS domain, region, and datacentre from the registered
Argo CD cluster Secret. Lovely overrides the chart's legacy K3s defaults with
the selected cluster identity, automatically derived credential hub, target's
LDAP endpoint, site-local PostgreSQL and Dragonfly endpoints, and PostgreSQL/S3
provider names. Credential synchronization is enabled for every target: only
the selected hub manages the Mail `User` claims and pushes their generated
credentials, while each spoke pulls those credentials into its local workload
Secrets. Talos targets use their site-specific Dragonfly credential paths. K3s
retains `Storage/DragonFly/CoRE/Creds` until that compatibility deployment is
removed because it does not publish a current site-specific credential path.
The chart continues to reserve Dragonfly logical database `25` for Rspamd at
each site.

Component ownership, mail flow, prerequisites, and user-facing checks are
documented in the
[Mail operations README](https://github.com/K-FOSS/CoRE-Business/blob/main/Mail/README.md).
This document and `Mail.yaml` are authoritative for current fleet ownership and
target selection. The chart still follows mutable `HEAD`, preserves generated
resources when a target is removed, and contains shared public mail-address and
egress settings.
Treat target removal, public IP, PureLB, Cilium egress, DNS/MX, PTR/rDNS, SPF,
DKIM, DMARC, TLS, identity, database, object-storage, and Dragonfly changes as
one coordinated production change.

Before sync, render the Mail chart once per target with the corresponding
`LOVELY_HELM_MERGE` values and inspect the `User`, ExternalSecret, Service,
DKIM, DNS, and Cilium resources. Verify the provider objects and stable
connection Secrets without printing their values. After reconciliation,
validate Argo CD plus downstream controller conditions, SMTP/STARTTLS,
authenticated submission, IMAP login, inbound and outbound delivery, spam
filtering, queue health, mail authentication results, and representative data
restore. Roll back through Git; removing a generator entry does not delete the
preserved resources or prove that external identities, databases, buckets, or
Dragonfly data were removed.

Other manifests under `Legacy/` remain legacy fleet owners until they are
individually migrated and documented.

## AVoIP

[Legacy/AVoIP.yaml](Legacy/AVoIP.yaml) is the migration owner for the
[CoRE-Business AVoIP chart](https://github.com/K-FOSS/CoRE-Business/tree/main/AVoIP).
It is prepared for the YVR `core-home1-talos-prod` and DC1
`core-dc1-talos-prod` clusters, plus the legacy `dc1-k3s-node1` cluster, and
renders into each cluster's `core-prod` namespace. Its matrix models
`core-dc1-talos-prod` as the tenant hub and both YVR and legacy K3s as spokes.
The K3s render deliberately retains the existing
`dc1-k3s-node1-business-avoip` Application name. The ApplicationSet derives
each target's cluster name, Kubernetes DNS domain, datacentre, region, and
environment from the registered Argo CD cluster labels; spoke renders also
receive the hub cluster name, datacentre, and region. The chart is given
`meet.mylogin.space`, the shared `core-prod/main-gw` HTTPS listener, and the
cluster-local `myloginspace-default-certificates` Secret.

The AVoIP chart schema is not yet present in the checked-out CoRE-Business
source, so the values merge follows the modernized application convention and
is intentionally pending a chart-schema validation. Before enabling sync,
render the upstream `AVoIP` path for both targets and confirm that its Jitsi
route consumes `gateway`, `jitsi.domain`, and `jitsi.tls.secretName`. Verify
the generated HTTPRoute, certificate reference, Jitsi web health, and media
connectivity from an external client. Resource preservation remains enabled;
removing a target does not delete retained application state or prove that
external DNS, certificates, and any persisted AVoIP data were cleaned up.

## Projects

[Projects.yaml](Projects.yaml) owns the production YVR deployment of the
[CoRE Projects chart](https://github.com/K-FOSS/CoRE-Business/tree/main/Projects).
Its matrix selects `core-home1-talos-prod` as the main hub and renders the
application in `core-prod` with the `projects.mylogin.space` hostname. The
OpenProject PostgreSQL and S3 Secret references are derived from the selected
cluster and production environment; no credential values are stored here.

The upstream [Projects README](https://github.com/K-FOSS/CoRE-Business/blob/main/Projects/README.md)
documents chart prerequisites and user-facing verification. Before sync,
render the chart with the registered Home1 cluster values and inspect the
Secret references, PostgreSQL, object-storage, Deployment, Service, and
HTTPRoute resources. Removing the matrix entry preserves generated resources,
so decommissioning requires an explicit database, bucket, and retained-data
cleanup decision.

## Personal/Fitness

[Personal/Fitness.yaml](Personal/Fitness.yaml) owns the YVR deployment of the
[CoRE openGym chart](https://github.com/K-FOSS/CoRE-Business/tree/main/Personal/Fitness)
in the dedicated `core-fitness-prod` namespace. It targets
`core-home1-talos-prod`, injects the registered cluster name, datacentre, and
region into the Lovely renderer, and attaches the `gym.mylogin.space` route to
the shared `core-prod/main-gw` HTTPS listener. The chart uses its own passkey
identity and does not consume PostgreSQL, External Secrets, or the Backplane
`User` resource.

The upstream [openGym README](https://github.com/K-FOSS/CoRE-Business/blob/main/Personal/Fitness/README.md)
documents prerequisites, the retained data and media PVCs, and operational
verification. Before sync, render the chart with the Home1 values and inspect
the two PVCs, Deployments, Services, and HTTPRoute. After reconciliation,
verify the route, `/api/health`, profile creation, passkey sign-in, media
loading, and restore of both PVCs. The chart currently follows mutable `HEAD`
and preserves both PVCs on removal; decommissioning therefore requires an
explicit backup and data cleanup decision.

## Personal/Finances

[Personal/Finances.yaml](Personal/Finances.yaml) owns the YVR deployment of
the upstream [CoRE Finances chart](https://github.com/K-FOSS/CoRE-Business/tree/main/Personal/Finances)
for `core-home1-talos-prod` in the standard `core-prod` namespace. The chart
is rendered through the Lovely plugin with the selected cluster identity and
Home1 PostgreSQL provider injected. The source is pinned to the upstream
revision that contains this chart.

The chart deploys Firefly III with a retained 10Gi Longhorn upload PVC, a
PostgreSQL `User` claim, an Authentik forward-auth policy, and a scheduler
CronJob. The externally managed `firefly-app-key` Secret must exist in
`core-prod` with an `APP_KEY` entry before synchronization; no credential value
is stored here. Before sync, resolve the chart dependency and inspect the
rendered User, Workspace, SecurityPolicy, Deployment, CronJob, Service,
HTTPRoute, and PVC. After reconciliation, verify PostgreSQL and Authentik
conditions, the application endpoint, authentication, transaction creation,
scheduler completion, and backup/restore behavior. The ApplicationSet
preserves generated resources on removal; decommissioning must therefore
include an explicit data-retention and cleanup decision.

## Personal/History

[Personal/History.yaml](Personal/History.yaml) owns the YVR deployment of the
upstream [CoRE Personal History chart](https://github.com/K-FOSS/CoRE-Business/tree/main/Personal/History),
which packages [Dawarich](https://dawarich.app/) in the `core-history-prod`
namespace. The ApplicationSet targets `core-home1-talos-prod`, pins the source
to the chart revision that introduced the stack, injects the site-local
PostgreSQL providers, and attaches `dawarich.mylogin.space` to the shared
`core-prod/main-gw` HTTPS listener.

The chart creates the PostgreSQL `User` claim, Authentik OIDC Workspace,
Dragonfly ExternalSecret, and three retained Longhorn PVCs for public data,
watched imports, and application storage. Dawarich uses Dragonfly logical
database `153`, registered in the [Dragonfly allocation registry](https://github.com/K-FOSS/CoRE-Backplane/blob/main/Storage/Dragonfly/CoRE/README.md);
database `152` remains reserved for SnapOtter. The Dragonfly password is read
from the chart's derived site-local Vault path, and no credential value is
stored here.

The upstream [Personal History README](https://github.com/K-FOSS/CoRE-Business/blob/main/Personal/History/README.md)
documents chart prerequisites and user-facing checks. Before sync, render the
pinned chart with the Home1 values and inspect the User, Workspace,
ExternalSecret, Deployments, Services, HTTPRoute, and PVCs. After
reconciliation, verify PostgreSQL migrations, Dragonfly TLS connectivity,
Authentik callback/login, location import, background processing, and restore
of all three PVCs. Removal preserves generated resources, runtime credentials,
database connection material, and PVCs; decommissioning therefore requires an
explicit data-retention and cleanup decision.

## Personal/Tasks

[Personal/Tasks.yaml](Personal/Tasks.yaml) owns the production YVR deployment of
the [CoRE Personal Tasks chart](https://github.com/K-FOSS/CoRE-Business/tree/main/Personal/Tasks)
in the standard `core-prod` namespace. It targets
`core-home1-talos-prod`, injects the registered cluster name, datacentre, and
region into the Lovely renderer, and attaches the chart's route to the shared
`core-prod/main-gw` HTTPS listener.

The upstream [Personal Tasks README](https://github.com/K-FOSS/CoRE-Business/blob/main/Personal/Tasks/README.md)
is authoritative for chart prerequisites and user-facing verification. The
ApplicationSet preserves generated resources on removal; decommissioning must
therefore include an explicit data-retention and cleanup decision.

## Landing

[Landing.yaml](Landing.yaml) owns the production YVR deployment rendered from
the [CoRE-Business Landing component](https://github.com/K-FOSS/CoRE-Business/tree/main/Landing).
It selects YVR bare-metal infrastructure clusters and reconciles the component
from that repository through the Lovely renderer into `core-prod`. The
ApplicationSet injects the selected environment, region, datacentre, and
cluster name/domain from the registered Argo CD cluster into the chart.
The upstream [Landing README](https://github.com/K-FOSS/CoRE-Business/blob/main/Landing/README.md)
is authoritative for its prerequisites and user-facing verification.

## Tools/IT-Tools

[Tools/IT-Tools.yaml](Tools/IT-Tools.yaml) owns the production YVR deployment
rendered from the [CoRE-Business IT-Tools component](https://github.com/K-FOSS/CoRE-Business/tree/main/Tools/IT-Tools).
It selects YVR bare-metal infrastructure clusters and reconciles the component
from that repository into `core-prod` without ApplicationSet value overrides.
The upstream [IT-Tools README](https://github.com/K-FOSS/CoRE-Business/blob/main/Tools/IT-Tools/README.md)
is authoritative for prerequisites and user-facing verification.

## Social/Fediverse

[Social/Fediverse.yaml](Social/Fediverse.yaml) owns the production YVR
deployment rendered from the [CoRE Fediverse chart](https://github.com/K-FOSS/CoRE-Business/tree/main/Social/Fediverse).
It is restricted to `core-home1-talos-prod` and reconciles into `core-prod`
through the Lovely renderer. The ApplicationSet patches the selected
environment, region, datacentre, and cluster name/domain into the chart values.
It also configures the public `mastodon.mylogin.space` hostname, the
site-local PostgreSQL and S3 providers, and the `main-gw` HTTPS listener. The
`social-fediverse-mastodon` Secret must already exist in `core-prod` with the
Mastodon runtime keys; this ApplicationSet references the Secret but does not
create or store its values. The chart's current values and prerequisites are
authoritative in its upstream component directory; federation uses the
[ActivityPub standard](https://www.w3.org/TR/activitypub/).

## Social/Matrix

[Social/Matrix.yaml](Social/Matrix.yaml) owns the production YVR deployment
rendered from the [CoRE Matrix component](https://github.com/K-FOSS/CoRE-Business/tree/main/Social/Matrix).
It targets `core-home1-talos-prod`, follows the upstream `HEAD` revision, and
reconciles into `core-prod` through the Lovely renderer. The ApplicationSet
injects the selected environment, site, cluster identity, and shared HTTPS
gateway values; Matrix-specific defaults and prerequisites remain owned by the
upstream component.

## Conversions

[Tools/Conversions.yaml](Tools/Conversions.yaml) owns the production
[CoRE Conversions chart](https://github.com/K-FOSS/CoRE-Business/tree/main/Tools/Conversions)
for the single YVR target `core-home1-talos-prod`. The chart runs
[SnapOtter 2.2.0](https://github.com/snapotter-hq/SnapOtter/releases/tag/v2.2.0)
at `https://conotter.mylogin.space`; its upstream deployment and recovery
requirements are documented in the
[Conversions README](https://github.com/K-FOSS/CoRE-Business/blob/main/Tools/Conversions/README.md).

The ApplicationSet injects the selected cluster name, datacentre, and region
into the Lovely Helm merge. This is intentionally a single persistent
deployment: independent instances would conflict on the public hostname and
would split files, sessions, and database state. The chart creates the
PostgreSQL/User and Authentik automation resources, while the namespace-local
`snapotter-runtime` Secret and Redis service remain separately provisioned;
their credential values are never stored here.

Before sync, render the chart with the representative Home1 identity and
inspect the User, PostgreSQL, Workspace, Secret references, PVC, and HTTPRoute.
After reconciliation, verify those downstream conditions, the PVC and
application health, HTTPS, local recovery login, Authentik group access,
conversion and download workflows, and persistence after a pod restart. The
chart retains its PVC and User resources on removal, so decommissioning must
be explicit and coordinated with data backup, identity, and database cleanup.

## Passwords

[Tools/VaultWarden.yaml](Tools/VaultWarden.yaml) owns the production
[CoRE Vaultwarden chart](https://github.com/K-FOSS/CoRE-Business/tree/main/Passwords/VaultWarden)
on three explicitly selected clusters. `dc1-k3s-node1` is the credential hub;
`core-dc1-talos-prod` and `core-home1-talos-prod` are spokes. All three serve
the production `passwords.mylogin.space` endpoint and connect to the PGPool
endpoint local to their site.

| Argo CD cluster | Role | PostgreSQL endpoint | Provider |
| --- | --- | --- | --- |
| `dc1-k3s-node1` | Hub | `psql.dc1-k3s-node1.dc1.yxl.mylogin.space` | `psql-dc1-yxl` |
| `core-dc1-talos-prod` | Spoke | `psql.core-dc1-talos-prod.dc1.yxl.mylogin.space` | `psql-dc1-yxl` |
| `core-home1-talos-prod` | Spoke | `psql.core-home1-talos-prod.home1.yvr.mylogin.space` | `psql-home1-yvr` |

Only the K3s render enables the `User.mylogin.space/v1alpha1` claim. That claim
owns the stable `vaultwarden-prod` PostgreSQL identity and `bitwarden` database
grant, then a PushSecret publishes its username, password, and database fields
to the chart's configured Vault record. Each Talos spoke omits the claim and
uses an ExternalSecret to reproduce the same stable connection Secret before
Vaultwarden starts. No credential values are stored in this repository.

The [Vaultwarden operations README](https://github.com/K-FOSS/CoRE-Business/blob/main/Passwords/VaultWarden/README.md)
documents component behavior, prerequisites, credential flow, and validation.
This document and `Tools/VaultWarden.yaml` are authoritative for the current
hub and target selection. Removing the hub, changing `hubCluster`, or rotating
the shared database identity requires a coordinated change across all three
sites. The PushSecret does not delete its remote record, spoke ExternalSecrets
retain orphaned local Secrets, and the PostgreSQL resources use orphaning
behavior; removal from Git is therefore not proof of credential revocation or
database deletion.

Before sync, render all three targets and confirm that only K3s produces one
User and one PushSecret, each Talos target produces one ExternalSecret, and all
three Deployments use their site-local PGPool hostname and the same stable
connection Secret name. After reconciliation, verify the claim and composite,
PostgreSQL Role/Database and Terraform Workspace, PushSecret/ExternalSecret
conditions, application readiness, login, vault read/write, invitations, and
SMTP delivery. Vaultwarden's local `/data` remains ephemeral, so recovery must
also account for local RSA keys, attachments, sends, and icon-cache data rather
than treating PostgreSQL readiness alone as complete recovery.
