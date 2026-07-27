# Network Crossplane APIs

This deployment defines Crossplane XRDs for network `Machine` and `Prefix`
resources. No direct ApplicationSet owner was found.

The local `Chart.yaml` is minimal; the deployment value lies in its raw XRD
templates. Before enabling it, document compositions, claim consumers,
validation, ownership and deletion semantics. Installing an XRD without a
selected Composition exposes an API that may accept claims but cannot realize
them.
