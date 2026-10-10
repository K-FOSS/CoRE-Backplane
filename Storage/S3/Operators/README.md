# CoRE-Backplane Storage/S3/Operators

This directory contains operators used by the S3 services and dependent
applications. Each operator has a separate Argo CD ApplicationSet so CRDs and
controllers can be reconciled independently from their workloads.

## Current operators

- [SeaweedFS Operator](SeaweedFS/README.md) manages the CRD used by the
  [YXL SeaweedFS workload](../SeaweedFS/README.md).
- [Garage Operator](Garage/README.md) manages Garage clusters and S3 resources
  for [Observability/Common](../../../Observability/Common/README.md) and
  [Observability/Metrics](../../../Observability/Metrics/README.md).
