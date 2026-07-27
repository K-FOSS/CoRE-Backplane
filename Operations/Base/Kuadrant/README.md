# Kuadrant base deployment

This deployment contains Kuadrant subscription/source resources and a local
Kuadrant template. Its Kustomization currently has no resources. No direct
ApplicationSet owner was found.

The subscription requires OLM, a compatible catalog/source and Gateway API
integration. Confirm channel/version, CRDs, namespace, installed CSV and
interaction with existing Envoy Gateway security/rate-limit policy before use.
