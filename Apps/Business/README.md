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
