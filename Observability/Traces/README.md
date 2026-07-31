# Tempo traces stack

This chart deploys the
[`TempoMonolithic` custom resource](https://github.com/grafana/tempo-operator/blob/main/docs/tempo/api.md)
and installs the [Grafana Tempo Operator](https://github.com/grafana/tempo-operator)
through an OperatorHub `Subscription`. The
[`core-observability-traces` ApplicationSet](../../Apps/Observability/Traces.yaml)
currently targets only `core-home1-talos-prod`.

Collectors accept OTLP and Jaeger traffic and forward it to Tempo. Tempo stores
traces in S3 using credentials synchronized by `core-tempo-s3`. The platform
`User` resource provisions the bucket identity, while a Terraform Workspace
creates Authentik groups. `traces.mylogin.space` is published through an
HTTPRoute protected by an Envoy Gateway SecurityPolicy requiring the `Traces`
group and forwarding Grafana's `orgID` claim.

The Tempo resource is monolithic and therefore not highly available. The
operator Subscription follows the mutable `alpha` channel rather than an
immutable release; review installed CSV changes and migration notes before
reconciliation. The S3 provider names in `TempoUser.yaml` are currently fixed
to the home1/YVR provider, matching the only selected cluster.

This stack does not create broad Kubernetes discovery. The Tempo Operator adds
normal CR watches, while trace Kubernetes metadata enrichment occurs in Alloy
and contributes to the Collector API traffic.

Verify Subscription/CSV health, `TempoMonolithic` conditions, generated S3
Secret readiness, object writes, collector export errors, route attachment,
JWT authorization, and an end-to-end trace query. Roll back through Git/Argo
CD. Deleting Tempo or its `User` can affect stored traces and credentials, so
review finalizers and deletion policies first.
