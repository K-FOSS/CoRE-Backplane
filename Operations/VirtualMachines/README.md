# CoRE-Backplane Operations/VirtualMachines Stack

This Lovely deployment installs KubeVirt, CDI and KubeVirt Manager using
remote Kustomize resources, then creates the KubeVirt/CDI custom resources and
management route/policy. It is owned by [Apps/Infra/KubeVirt.yaml](../../Apps/Infra/KubeVirt.yaml)
and is listed in the [Operations overview](../README.md).

KubeVirt and CDI URLs are versioned. CDI is pinned to [v1.66.1](https://github.com/kubevirt/containerized-data-importer/releases/tag/v1.66.1);
the operator installs the CDI CRDs and controllers before the CDI custom
resource in this stack. KubeVirt Manager currently tracks a mutable upstream
`main` manifest. Inspect and preferably pin the fetched manager resources for
reproducibility. See the [CDI upstream repository](https://github.com/kubevirt/containerized-data-importer)
for operator documentation and release notes.

Virtualization requires hardware virtualization, device access, storage
classes and network attachments. Validate operator/CRD compatibility, live
migration prerequisites, CDI imports, VM console access, disruption behavior
and backups before upgrades.
