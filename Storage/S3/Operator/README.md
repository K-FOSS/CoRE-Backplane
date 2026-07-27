# S3 Operator chart

This chart installs the MinIO Operator when `operator.enabled` is true. It is
owned by `Apps/Storage/S3/Operator.yaml`, which injects cluster domain,
namespace and operator settings.

The operator manages MinIO Tenant resources; tenant data is not stored in the
operator itself. Install CRDs/controller before tenant charts and preserve CRD
ownership during upgrades.

Validate operator health, watched namespaces, STS settings, CRD compatibility
and tenant reconciliation. Removing the operator does not safely delete or
migrate tenant data, while deleting tenant resources may have destructive
effects depending on PVC retention.
