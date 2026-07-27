# Operations S3 deployment

This chart packages the INSEE S3 Operator and synchronizes S3 credentials
through an ExternalSecret. No direct ApplicationSet owner was found.

Confirm whether this operator overlaps with MinIO Operator or Crossplane S3
APIs before deployment. Define watched namespaces, provider credentials,
bucket deletion/reclaim policy and generated-secret ownership.

Test bucket creation, policy, credential rotation and deletion using a
non-production account.
