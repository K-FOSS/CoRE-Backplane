# K-FOSS/CoRE-Backplane Observability Exporters Stack

This helm chart deployed by [ArgoCD](../../ArgoCD/) deploys the [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)


It is then tracked by [Collectors/Alloy](../Collectors/) and pushed to [Mimir](../Metrics/)