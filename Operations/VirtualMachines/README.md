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

## CDI utility pod resources

The CDI `podResourceRequirements` setting applies to its clone, import and
upload utility pods. This stack requests `100m` CPU and `60M` memory, with
limits of `4` CPU and `600M` memory. CDI uses these values when it creates
utility pods; pods already running keep their existing resources. See the
[CDI configuration reference](https://github.com/kubevirt/containerized-data-importer/blob/v1.66.1/doc/cdi-config.md)
and [CDI quota guidance](https://github.com/kubevirt/containerized-data-importer/blob/v1.66.1/doc/quota.md).

When a clone restarts, compare the `cdi-clone-source` pod's last termination
with the matching upload server's logs. A source pod can complete its stream
and still fail when the upload server cannot write the extracted disk to
`/data`; check the PVC access mode, volume ownership and CSI driver's
`fsGroupPolicy`. The CPU limit does not resolve a destination filesystem
permission failure.
