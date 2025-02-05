# K-FOSS/CoRE-Backplane Traces Obserability Stack

This helm chart deployed by [ArgoCD](../../ArgoCD/) into CoRE-Prod deploys [Grafana Tempo](https://grafana.com/oss/tempo/)

During deployment using the [User Custom Resources](../../Operations/SSO/User/) at [./templates/TempoUser.yaml](./templates/TempoUser.yaml) the S3 bucket and user credentials are created.



Access to the [HTTPRoute](./templates/HTTPRoute,.yaml) is handled by the [Envoy Security Policy](https://gateway.envoyproxy.io/contributions/design/security-policy/) at [./templates/SecurityPolicy.yaml](./templates/SecurityPolicy.yaml) which checks for Authentik issued JWTs, mainly passed along from Grafana using cookie passthrough.


This allows any user who has the Traces group in their JWT accessing https://traces.mylogin.space to query and push traces


In order to deploy Tempo we are using the [Tempo Operator](https://github.com/grafana/tempo-operator) deployed by the [Subscription](./templates/Operator.yaml)


Currently it is a single node [TempoMonolithic](https://github.com/grafana/tempo-operator/blob/main/docs/tempomonolithic.md) stack although once I get more servers online I will move that to the distributed model