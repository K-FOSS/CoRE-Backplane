# Talos Image Factory

This stack deploys the [Sidero Labs Talos Image Factory](https://github.com/siderolabs/image-factory) to the YXL infrastructure cluster `core-dc1-talos-prod` in the `core-prod` namespace. The stack is owned by [`Apps/Operations/TalosImageFactory.yaml`](../../Apps/Operations/TalosImageFactory.yaml).

The `User.mylogin.space/v1alpha1` claim provisions the site-local MinIO bucket, temporary S3 credentials, and a long-lived service-account Secret consumed by the Image Factory. Temporary credentials are enabled as a compatibility workaround until the current User Composition bug affecting role and user creation without `createCredentials` is fixed. Bucket and credential resources are managed by the existing [SSO User Composition](../SSO/User/README.md); this chart does not contain credentials.

The factory is published at `https://tfactory.<cluster>.<datacenter>.<region>.writemy.codes`. Its S3 cache endpoint is site-local, while its Talos core, schematic, and generated-installer OCI repositories use the `kjones/actions-lab` packages on the YXL Forgejo registry.

Before reconciliation, create `talos-image-factory-cache-signing-key` in the destination namespace with the `cache-signing.key` data key containing an ECDSA P-256 private key. Keep that Secret across rollback or deletion: changing it makes previously cached artifacts unverifiable. The Image Factory also requires the Forgejo packages to be reachable and readable by the pod; package authentication is not configured by this stack.

Operational verification should follow the User claim, generated bucket and service-account Secret, Image Factory Deployment, S3 cache writes, Forgejo OCI pulls, and HTTPRoute status. An Argo CD `Synced` status alone does not prove those downstream paths are healthy.

Upstream references: [Image Factory Helm chart](https://github.com/siderolabs/image-factory/tree/main/deploy/helm/image-factory), [Image Factory configuration](https://github.com/siderolabs/image-factory/blob/main/docs/configuration.md), [custom registry deployment](https://github.com/siderolabs/image-factory/blob/main/docs/air-gapped.md), and [Talos Image Factory API/OCI usage](https://github.com/siderolabs/image-factory/blob/main/internal/frontend/http/templates/llms.txt).
