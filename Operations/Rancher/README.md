# Rancher deployment

This chart packages Rancher and a Gateway route. No direct ApplicationSet owner
was found.

Before enabling it, define the authoritative management role relative to Argo
CD, Cluster API and OCM; avoid multiple controllers competing for cluster
lifecycle. Review hostname/TLS, bootstrap credentials, audit-log hostPath,
storage, backup/restore and downstream cluster-agent access.

Rancher is a high-privilege control plane. Restrict administrative access and
test loss/recovery without affecting GitOps ownership.
