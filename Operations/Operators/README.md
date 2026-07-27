# Operator Lifecycle Manager deployment

This deployment installs Operator Lifecycle Manager (OLM) and is owned by
`Apps/Infra/Operators.yaml`.

OLM manages catalogs, subscriptions, install plans, CSVs, CRDs and operator
RBAC. A catalog or channel change can upgrade controllers and CRDs without a
change to the consuming application's chart.

Before upgrades, inventory subscriptions and installed CSVs, review manual
versus automatic approval, CRD conversion/storage versions and operator
compatibility. Validate package-server/catalog health and every affected
operator after reconciliation. Do not delete OLM CRDs or namespaces while
operators remain managed by it.
