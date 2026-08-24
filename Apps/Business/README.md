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
clusters:

| Argo CD cluster | Site | LDAP | PostgreSQL and S3 providers | Dragonfly credentials |
| --- | --- | --- | --- | --- |
| `dc1-k3s-node1` | `dc1/yxl` | `ldap-dc1.mylogin.space` | `psql-dc1-yxl`, `s3-yxl-dc1-core` | Legacy compatibility alias |
| `core-dc1-talos-prod` | `dc1/yxl` | `ldap-dc1-talos.mylogin.space` | `psql-dc1-yxl`, `s3-yxl-dc1-core` | Site-local path |
| `core-home1-talos-prod` | `home1/yvr` | `ldap-home1.mylogin.space` | `psql-home1-yvr`, `s3-yvr-home1-core` | Site-local path |

For each target, the ApplicationSet derives the destination API server,
environment, cluster DNS domain, region, and datacentre from the registered
Argo CD cluster Secret. Lovely overrides the chart's legacy K3s defaults with
the target's LDAP endpoint, site-local PostgreSQL and Dragonfly endpoints, and
PostgreSQL/S3 provider names. Talos targets use their site-specific Dragonfly
credential paths. K3s retains `Storage/DragonFly/CoRE/Creds` until that
compatibility deployment is removed because it does not publish a current
site-specific credential path. The chart continues to reserve Dragonfly
logical database `25` for Rspamd at each site.

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
