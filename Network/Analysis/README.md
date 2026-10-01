# CoRE-Backplane Network/Analysis Stack

This stack starts the internal network-analysis platform with [IVRE](https://github.com/ivre/ivre): a self-hosted web interface for Nmap and other active-recon results plus passive and flow intelligence. It is owned by [`Apps/Network/Analysis.yaml`](../../Apps/Network/Analysis.yaml) and follows the [Network stack overview](../README.md).

## Ownership, target, and rendering

The ApplicationSet currently selects `core-home1-talos-prod`, because the
shared MongoDB service is currently hosted there. The Lovely Helm merge supplies
the cluster-specific hostname and the MongoDB connection Secret name. The chart
renders the IVRE `web`, `web-uwsgi`, `web-doku`, and MCP components, internal
backend Services using the names expected by IVRE's [upstream Nginx
configuration](https://github.com/ivre/ivre/blob/master/docker/web/nginx-default-site),
an optional CLI container, a retained DokuWiki PVC, an internal HTTPRoute, and
the `User` claim for the IVRE service identity. Workloads use the [BJW-S common
library chart](https://github.com/bjw-s-labs/helm-charts/tree/common-5.0.1/charts/library/common).

The `User` claim declares the intended MongoDB database allocation as `ivre`.
The current [User Composition](../../Operations/SSO/User/README.md) schema
accepts MongoDB fields, but its implemented provisioning path is not yet
validated for MongoDB. Activation therefore requires verifying that the
connection Secret named by the ApplicationSet contains a usable `mongoURI`;
the chart intentionally fails rendering when that reference is absent.

## Data flow and initial scope

IVRE stores its recon data in MongoDB. The [IVRE Docker image
documentation](https://doc.ivre.rocks/en/latest/install/docker.html) defines
the component roles and the `3031`, `8000`, and `9100` backend ports. The web
image serves the static UI and
reverse proxies to uWSGI and DokuWiki; uWSGI reads the database URL from the
User connection Secret. DokuWiki notes use the retained PVC. The client image
is available for controlled `ivre` CLI operations but is disabled by default.

This first slice does not create host-network packet sensors, capture devices,
or an unattended scanner. IVRE can ingest Nmap, Masscan, Zeek, Argus, Nfdump,
and related tool output; adding those sensors requires an explicit placement,
capture-interface policy, scan authorization, and result-retention design.
The [IVRE active-recon documentation](https://doc.ivre.rocks/en/latest/usage/active-recon.html), [passive-recon documentation](https://doc.ivre.rocks/en/latest/usage/passive-recon.html), and [Docker component documentation](https://doc.ivre.rocks/en/latest/install/docker.html) describe the supported input and image model.

## Operations and verification

Before enabling the ApplicationSet, verify the MongoDB User claim, its
connection Secret, the `mongoURI` key, and the target database grants without
printing Secret values. Render the complete ApplicationSet-injected chart and
confirm that the HTTPRoute is private, the Gateway reference is valid, and the
PVC uses an available storage class.

After reconciliation, verify the User composite and downstream MongoDB
identity, pod readiness, HTTPRoute `Accepted`/`Programmed` conditions, and the
IVRE help page. Import a small approved Nmap result with the client before
considering the data path healthy. Do not enable broad internal scans until
source networks, rate limits, schedules, and an owner-approved target list are
recorded.

## Recovery and removal

The DokuWiki PVC is retained so notes are not removed by an Argo application
deletion. Removing the User claim does not prove that the MongoDB role,
database, grants, or stored IVRE data were deleted; inspect the User composite,
MongoDB state, and retention policy explicitly. Back up the shared MongoDB
service through its owning stack before any destructive cleanup.
