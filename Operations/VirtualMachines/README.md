# Virtual Machine operations

This Lovely deployment installs KubeVirt, CDI and KubeVirt Manager using
remote Kustomize resources, then creates the KubeVirt/CDI custom resources and
management route/policy. It is owned by `Apps/Infra/KubeVirt.yaml`.

KubeVirt and CDI URLs are versioned, while KubeVirt Manager currently tracks a
mutable upstream `main` manifest. Inspect and preferably pin the fetched
manager resources for reproducibility.

Virtualization requires hardware virtualization, device access, storage
classes and network attachments. Validate operator/CRD compatibility, live
migration prerequisites, CDI imports, VM console access, disruption behavior
and backups before upgrades.
