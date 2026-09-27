# YVR Home1 running workload usage vs requests

- Captured: `2026-09-27T02:49:40Z` (Metrics API window `19.324s`).
- Cluster context: `logged-user` (YVR Home1). Scope: all namespaces, all regular containers in Pods whose phase was `Running` and container state was `Running` at capture time.
- Requests are the admitted Pod-spec CPU and memory requests. Usage is the current Metrics API sample. Per-row usage is the mean and maximum across matching running container instances for that controller/container. Ratios compare mean usage with the uniform request only when every instance in the group has one.
- CPU is normalized to millicores (`m`); memory to mebibytes (`Mi`). `—` means no requests are set; `(N unset)` marks instances missing that request; multiple values are listed when requests vary. `partial` means only some grouped instances have a request, so no single ratio is shown.
- This is a point-in-time comparison, not a historical average, utilization target, or recommendation. Deployment/ReplicaSet and Job/CronJob ownership is folded up to the top owner when available; custom-controller-owned Pods retain their immediate owner.

Running regular container instances: **547**. Instances with a matching Metrics API sample: **547**. Workload/container groups: **310**.

| Namespace | Workload owner | Container | Running pods | CPU request | CPU usage avg / max | Avg CPU / request | Memory request | Memory usage avg / max | Avg memory / request | Metrics absent |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `argocd` | `Deployment/argocd-applicationset-controller` | `applicationset-controller` | 1 | 16m | 2.4m / 2.4m | 15% | 64.0Mi | 56.8Mi / 56.8Mi | 89% | — |
| `argocd` | `Deployment/argocd-notifications-controller` | `notifications-controller` | 1 | 32m | 0.5m / 0.5m | 2% | 64.0Mi | 59.3Mi / 59.3Mi | 93% | — |
| `argocd` | `Deployment/argocd-repo-server` | `lovely-plugin` | 2 | 2000m | 3997.3m / 7994.6m | 200% | 256.0Mi | 1872.2Mi / 3468.2Mi | 731% | — |
| `argocd` | `Deployment/argocd-repo-server` | `repo-server` | 2 | 250m | 12.7m / 14.3m | 5% | 128.0Mi | 114.7Mi / 128.7Mi | 90% | — |
| `argocd` | `Deployment/argocd-server` | `server` | 2 | 100m | 25.0m / 47.5m | 25% | 256.0Mi | 125.2Mi / 128.1Mi | 49% | — |
| `argocd` | `Deployment/capi2argo-operator` | `capi2argo-cluster-operator` | 1 | 10m | 0.5m / 0.5m | 5% | 50.0Mi | 46.1Mi / 46.1Mi | 92% | — |
| `argocd` | `StatefulSet/argocd-application-controller` | `application-controller` | 2 | 64m | 142.4m / 176.0m | 222% | 64.0Mi | 1691.6Mi / 2181.4Mi | 2643% | — |
| `cdi` | `CDI/cdi` | `cdi-apiserver` | 1 | 100m | 1.3m / 1.3m | 1% | 150.0Mi | 74.1Mi / 74.1Mi | 49% | — |
| `cdi` | `CDI/cdi` | `cdi-deployment` | 1 | 100m | 14.5m / 14.5m | 14% | 150.0Mi | 190.8Mi / 190.8Mi | 127% | — |
| `cdi` | `CDI/cdi` | `cdi-uploadproxy` | 1 | 100m | 0.7m / 0.7m | <1% | 150.0Mi | 11.9Mi / 11.9Mi | 8% | — |
| `cdi` | `Deployment/cdi-operator` | `cdi-operator` | 1 | 100m | 1.1m / 1.1m | 1% | 150.0Mi | 236.6Mi / 236.6Mi | 158% | — |
| `cert-manager` | `Deployment/cert-manager` | `cert-manager-controller` | 1 | — (1 unset) | 1.5m / 1.5m | partial | — (1 unset) | 54.2Mi / 54.2Mi | partial | — |
| `cert-manager` | `Deployment/cert-manager-cainjector` | `cert-manager-cainjector` | 1 | — (1 unset) | 0.7m / 0.7m | partial | — (1 unset) | 157.0Mi / 157.0Mi | partial | — |
| `cert-manager` | `Deployment/cert-manager-webhook` | `cert-manager-webhook` | 1 | — (1 unset) | 0.3m / 0.3m | partial | — (1 unset) | 22.9Mi / 22.9Mi | partial | — |
| `cert-manager` | `Deployment/trust-manager` | `trust-manager` | 1 | — (1 unset) | 2.4m / 2.4m | partial | — (1 unset) | 30.9Mi / 30.9Mi | partial | — |
| `core-ai-prod` | `Deployment/core-home1-talos-prod-business-ai-prod-openwebui` | `openwebui` | 1 | — (1 unset) | 9.6m / 9.6m | partial | — (1 unset) | 907.8Mi / 907.8Mi | partial | — |
| `core-ai-prod` | `Deployment/core-home1-talos-prod-business-ai-prod-wyoming` | `wyoming` | 1 | — (1 unset) | 0.0m / 0.0m | partial | — (1 unset) | 41.2Mi / 41.2Mi | partial | — |
| `core-ai-prod` | `StatefulSet/core-home1-talos-prod-business-ai-prod-gpustack` | `gpustack` | 1 | — (1 unset) | 62.0m / 62.0m | partial | — (1 unset) | 3499.1Mi / 3499.1Mi | partial | — |
| `core-ai-prod` | `StatefulSet/core-home1-talos-prod-business-ai-prod-speeches` | `speeches` | 1 | 8000m | 3.7m / 3.7m | <1% | 4096.0Mi | 625.8Mi / 625.8Mi | 15% | — |
| `core-ai-prod` | `StatefulSet/core-home1-talos-prod-business-ai-prod-speeches-cpu` | `speeches-cpu` | 2 | 4000m | 4.6m / 5.2m | <1% | — (2 unset) | 231.2Mi / 316.4Mi | partial | — |
| `core-ai-prod` | `StatefulSet/core-home1-talos-prod-business-ai-prod-speeches-cuda` | `speeches-cuda` | 1 | — (1 unset) | 2.0m / 2.0m | partial | — (1 unset) | 924.5Mi / 924.5Mi | partial | — |
| `core-development-prod` | `Deployment/forgejo-runner-core-home1-talos-prod` | `dind` | 1 | 200m | 2.3m / 2.3m | 1% | 512.0Mi | 33.0Mi / 33.0Mi | 6% | — |
| `core-development-prod` | `Deployment/forgejo-runner-core-home1-talos-prod` | `runner` | 1 | 100m | 0.5m / 0.5m | <1% | 128.0Mi | 11.2Mi / 11.2Mi | 9% | — |
| `core-fitness-prod` | `Deployment/fitness-api` | `api` | 1 | 25m | 0.2m / 0.2m | <1% | 64.0Mi | 41.4Mi / 41.4Mi | 65% | — |
| `core-fitness-prod` | `Deployment/fitness-web` | `web` | 1 | 25m | 0.1m / 0.1m | <1% | 64.0Mi | 7.9Mi / 7.9Mi | 12% | — |
| `core-media` | `Deployment/core-home1-talos-prod-media-nzb-prod-sabnzbd` | `sabnzbd` | 1 | — (1 unset) | 0.7m / 0.7m | partial | — (1 unset) | 73.6Mi / 73.6Mi | partial | — |
| `core-media` | `Deployment/core-home1-talos-prod-media-streaming-augy-prod-stash` | `stash` | 1 | — (1 unset) | 1.2m / 1.2m | partial | — (1 unset) | 63.0Mi / 63.0Mi | partial | — |
| `core-media` | `Deployment/core-media-scraparr` | `scraparr` | 1 | — (1 unset) | 0.8m / 0.8m | partial | — (1 unset) | 30.6Mi / 30.6Mi | partial | — |
| `core-media` | `Deployment/photos-machine-learning` | `main` | 1 | — (1 unset) | 1.2m / 1.2m | partial | — (1 unset) | 147.6Mi / 147.6Mi | partial | — |
| `core-media` | `Deployment/photos-machine-learning` | `redis-proxy` | 1 | — (1 unset) | 3.6m / 3.6m | partial | — (1 unset) | 78.4Mi / 78.4Mi | partial | — |
| `core-media` | `Deployment/photos-server` | `main` | 1 | — (1 unset) | 1.8m / 1.8m | partial | — (1 unset) | 3167.8Mi / 3167.8Mi | partial | — |
| `core-media` | `Deployment/photos-server` | `redis-proxy` | 1 | — (1 unset) | 6.8m / 6.8m | partial | — (1 unset) | 96.1Mi / 96.1Mi | partial | — |
| `core-net-prod` | `Deployment/core-home1-talos-prod-network-filter-prod-filter-gw` | `frr` | 1 | — (1 unset) | 0.8m / 0.8m | partial | — (1 unset) | 29.1Mi / 29.1Mi | partial | — |
| `core-net-prod` | `Deployment/core-home1-talos-prod-network-insight-prod-flow` | `asn-lookup` | 1 | 10m | 0.0m / 0.0m | <1% | 32.0Mi | 23.3Mi / 23.3Mi | 73% | — |
| `core-net-prod` | `Deployment/core-home1-talos-prod-network-insight-prod-flow` | `ipfix` | 1 | 100m | 0.0m / 0.0m | <1% | 256.0Mi | 35.1Mi / 35.1Mi | 14% | — |
| `core-net-prod` | `Deployment/core-home1-talos-prod-network-insight-prod-flow` | `netflow` | 1 | 100m | 0.8m / 0.8m | <1% | 256.0Mi | 43.2Mi / 43.2Mi | 17% | — |
| `core-net-prod` | `Deployment/core-home1-talos-prod-network-insight-prod-flow` | `sflow` | 1 | 100m | 0.0m / 0.0m | <1% | 256.0Mi | 35.6Mi / 35.6Mi | 14% | — |
| `core-net-prod` | `Deployment/core-home1-talos-prod-network-insight-prod-flow` | `sql-exporter` | 1 | 10m | 0.0m / 0.0m | <1% | 32.0Mi | 36.6Mi / 36.6Mi | 114% | — |
| `core-net-prod` | `Deployment/core-home1-talos-prod-network-insight-prod-minion` | `minion` | 1 | 2000m | 14.0m / 14.0m | <1% | 9216.0Mi | 2250.5Mi / 2250.5Mi | 24% | — |
| `core-net-prod` | `Deployment/core-home1-talos-prod-network-routeserver-prod-rs0` | `frr` | 1 | — (1 unset) | 1.4m / 1.4m | partial | — (1 unset) | 38.5Mi / 38.5Mi | partial | — |
| `core-net-prod` | `Deployment/core-home1-talos-prod-network-routeserver-prod-rs0` | `netshoot` | 1 | — (1 unset) | 0.0m / 0.0m | partial | — (1 unset) | 0.3Mi / 0.3Mi | partial | — |
| `core-net-prod` | `StatefulSet/core-home1-talos-prod-network-insight-prod` | `opennms` | 1 | 1000m | 11.0m / 11.0m | 1% | 2048.0Mi | 1884.9Mi / 1884.9Mi | 92% | — |
| `core-net-tunneler-prod` | `Deployment/core-home1-talos-prod-tunneler-prod-yvr-tunneler1` | `frr` | 1 | — (1 unset) | 1.1m / 1.1m | partial | — (1 unset) | 21.8Mi / 21.8Mi | partial | — |
| `core-net-tunneler-prod` | `Deployment/core-home1-talos-prod-tunneler-prod-yvr-tunneler1` | `wireguard` | 1 | — (1 unset) | 0.0m / 0.0m | partial | — (1 unset) | 3.1Mi / 3.1Mi | partial | — |
| `core-net-tunneler-prod` | `Deployment/core-home1-talos-prod-tunneler-prod-yvr-tunneler2` | `frr` | 1 | — (1 unset) | 0.7m / 0.7m | partial | — (1 unset) | 21.9Mi / 21.9Mi | partial | — |
| `core-net-tunneler-prod` | `Deployment/core-home1-talos-prod-tunneler-prod-yvr-tunneler2` | `wireguard` | 1 | — (1 unset) | 0.0m / 0.0m | partial | — (1 unset) | 3.3Mi / 3.3Mi | partial | — |
| `core-prod` | `ClusterServiceVersion/percona-server-mongodb-operator.v1.23.0` | `percona-server-mongodb-operator` | 1 | — (1 unset) | 24.0m / 24.0m | partial | — (1 unset) | 109.8Mi / 109.8Mi | partial | — |
| `core-prod` | `DaemonSet/core-home1-talos-prod-collectors-alloy-logs` | `alloy` | 4 | — (4 unset) | 2.4m / 5.1m | partial | — (4 unset) | 49.2Mi / 58.1Mi | partial | — |
| `core-prod` | `DaemonSet/core-home1-talos-prod-collectors-alloy-logs` | `config-reloader` | 4 | 10m | 0.0m / 0.0m | <1% | 50.0Mi | 8.4Mi / 10.7Mi | 17% | — |
| `core-prod` | `DaemonSet/core-home1-talos-prod-collectors-alloy-metrics` | `alloy` | 4 | — (4 unset) | 3.2m / 5.1m | partial | — (4 unset) | 100.5Mi / 137.5Mi | partial | — |
| `core-prod` | `DaemonSet/core-home1-talos-prod-collectors-alloy-metrics` | `config-reloader` | 4 | 10m | 0.0m / 0.1m | <1% | 50.0Mi | 8.0Mi / 8.9Mi | 16% | — |
| `core-prod` | `DaemonSet/core-home1-talos-prod-collectors-alloy-otlp` | `alloy` | 4 | — (4 unset) | 3.4m / 5.8m | partial | — (4 unset) | 80.1Mi / 170.8Mi | partial | — |
| `core-prod` | `DaemonSet/core-home1-talos-prod-collectors-alloy-otlp` | `config-reloader` | 4 | 10m | 0.1m / 0.2m | <1% | 50.0Mi | 12.0Mi / 20.4Mi | 24% | — |
| `core-prod` | `Deployment/adventurelog-backend` | `backend` | 1 | 100m | 1.9m / 1.9m | 2% | 512.0Mi | 293.1Mi / 293.1Mi | 57% | — |
| `core-prod` | `Deployment/adventurelog-frontend` | `frontend` | 1 | 100m | 0.5m / 0.5m | <1% | 256.0Mi | 43.8Mi / 43.8Mi | 17% | — |
| `core-prod` | `Deployment/ak-outpost-ractest` | `rac` | 1 | — (1 unset) | 5.3m / 5.3m | partial | — (1 unset) | 87.0Mi / 87.0Mi | partial | — |
| `core-prod` | `Deployment/cdn-idle` | `idle` | 3 | — (3 unset) | 0.2m / 0.2m | partial | — (3 unset) | 16.9Mi / 19.6Mi | partial | — |
| `core-prod` | `Deployment/core-ambient` | `moodist` | 1 | — (1 unset) | 0.0m / 0.0m | partial | — (1 unset) | 20.1Mi / 20.1Mi | partial | — |
| `core-prod` | `Deployment/core-business-finances-app` | `firefly` | 1 | 50m | 8.5m / 8.5m | 17% | 256.0Mi | 184.9Mi / 184.9Mi | 72% | — |
| `core-prod` | `Deployment/core-business-finances-httpbin` | `httpbin` | 1 | 10m | 0.1m / 0.1m | 1% | 32.0Mi | 3.7Mi / 3.7Mi | 12% | — |
| `core-prod` | `Deployment/core-home1-talos-prod-aaa-prod-authentik-server` | `server` | 2 | — (2 unset) | 309.0m / 558.6m | partial | — (2 unset) | 861.1Mi / 969.9Mi | partial | — |
| `core-prod` | `Deployment/core-home1-talos-prod-business-avoip-prod-avoip-kamailio` | `kamailio` | 1 | — (1 unset) | 7.4m / 7.4m | partial | — (1 unset) | 14.5Mi / 14.5Mi | partial | — |
| `core-prod` | `Deployment/core-home1-talos-prod-business-avoip-prod-avoip-kamailio` | `netshoot` | 1 | — (1 unset) | 0.0m / 0.0m | partial | — (1 unset) | 0.3Mi / 0.3Mi | partial | — |
| `core-prod` | `Deployment/core-home1-talos-prod-business-avoip-prod-avoip-rtpengine` | `netshoot` | 1 | — (1 unset) | 0.0m / 0.0m | partial | — (1 unset) | 0.5Mi / 0.5Mi | partial | — |
| `core-prod` | `Deployment/core-home1-talos-prod-business-avoip-prod-avoip-rtpengine` | `rtpengine` | 1 | — (1 unset) | 7.0m / 7.0m | partial | — (1 unset) | 20.2Mi / 20.2Mi | partial | — |
| `core-prod` | `Deployment/core-home1-talos-prod-business-conversions-prod` | `snapotter` | 1 | 500m | 5.6m / 5.6m | 1% | 2048.0Mi | 409.2Mi / 409.2Mi | 20% | — |
| `core-prod` | `Deployment/core-home1-talos-prod-business-cyberchef-prod` | `cyberchef` | 2 | 25m | 0.1m / 0.1m | <1% | 64.0Mi | 22.7Mi / 37.0Mi | 35% | — |
| `core-prod` | `Deployment/core-home1-talos-prod-business-drawio-prod-drawio` | `drawio` | 1 | — (1 unset) | 1.1m / 1.1m | partial | — (1 unset) | 263.1Mi / 263.1Mi | partial | — |
| `core-prod` | `Deployment/core-home1-talos-prod-business-it-tools-prod` | `it-tools` | 2 | 25m | 0.1m / 0.1m | <1% | 64.0Mi | 21.9Mi / 36.2Mi | 34% | — |
| `core-prod` | `Deployment/core-home1-talos-prod-business-landing-prod-core-business-landi` | `discovery` | 2 | — (2 unset) | 0.1m / 0.1m | partial | — (2 unset) | 20.6Mi / 34.1Mi | partial | — |
| `core-prod` | `Deployment/core-home1-talos-prod-business-passwords-vaultwarden` | `vaultwarden` | 1 | 15m | 0.2m / 0.2m | 1% | 100.0Mi | 54.2Mi / 54.2Mi | 54% | — |
| `core-prod` | `Deployment/core-home1-talos-prod-business-social-fediverse-prod-bluesky` | `bluesky` | 1 | 100m | 1.1m / 1.1m | 1% | 256.0Mi | 139.9Mi / 139.9Mi | 55% | — |
| `core-prod` | `Deployment/core-home1-talos-prod-business-social-fediverse-prod-sidekiq` | `sidekiq` | 3 | 500m | 22.8m / 45.4m | 5% | 1024.0Mi | 481.9Mi / 519.8Mi | 47% | — |
| `core-prod` | `Deployment/core-home1-talos-prod-business-social-fediverse-prod-streaming` | `streaming` | 3 | 100m | 3.6m / 4.5m | 4% | 256.0Mi | 94.6Mi / 116.2Mi | 37% | — |
| `core-prod` | `Deployment/core-home1-talos-prod-business-social-fediverse-prod-tranquil` | `dragonfly-tls-proxy` | 2 | — (2 unset) | 0.0m / 0.0m | partial | — (2 unset) | 1.0Mi / 1.1Mi | partial | — |
| `core-prod` | `Deployment/core-home1-talos-prod-business-social-fediverse-prod-tranquil` | `tranquil` | 2 | 100m | 2.1m / 2.6m | 2% | 256.0Mi | 58.2Mi / 59.7Mi | 23% | — |
| `core-prod` | `Deployment/core-home1-talos-prod-business-social-fediverse-prod-web` | `web` | 3 | 500m | 7.0m / 14.1m | 1% | 1024.0Mi | 783.3Mi / 809.1Mi | 76% | — |
| `core-prod` | `Deployment/core-home1-talos-prod-business-social-matrix-prod-element` | `element` | 2 | 100m | 0.1m / 0.1m | <1% | 128.0Mi | 35.6Mi / 36.3Mi | 28% | — |
| `core-prod` | `Deployment/core-home1-talos-prod-business-social-matrix-prod-mas` | `mas` | 1 | — (1 unset) | 1.5m / 1.5m | partial | — (1 unset) | 81.2Mi / 81.2Mi | partial | — |
| `core-prod` | `Deployment/core-home1-talos-prod-business-social-matrix-prod-synapse` | `synapse` | 1 | 500m | 4.2m / 4.2m | <1% | 1024.0Mi | 117.9Mi / 117.9Mi | 12% | — |
| `core-prod` | `Deployment/core-home1-talos-prod-core-unseal-corevault-vault-autounseal` | `main` | 3 | — (3 unset) | 0.2m / 0.4m | partial | — (3 unset) | 9.8Mi / 15.7Mi | partial | — |
| `core-prod` | `Deployment/core-home1-talos-prod-db-operator-postgres-operator` | `postgres-operator` | 1 | 100m | 0.9m / 0.9m | <1% | 250.0Mi | 57.9Mi / 57.9Mi | 23% | — |
| `core-prod` | `Deployment/core-home1-talos-prod-db-operator-pxc-operator` | `percona-xtradb-cluster-operator` | 1 | 100m | 3.4m / 3.4m | 3% | 20.0Mi | 36.3Mi / 36.3Mi | 181% | — |
| `core-prod` | `Deployment/core-home1-talos-prod-db-psql-pgadmin4` | `pgadmin4` | 1 | — (1 unset) | 0.3m / 0.3m | partial | — (1 unset) | 254.2Mi / 254.2Mi | partial | — |
| `core-prod` | `Deployment/core-home1-talos-prod-development-forgejo` | `forgejo` | 1 | — (1 unset) | 57.7m / 57.7m | partial | — (1 unset) | 153.9Mi / 153.9Mi | partial | — |
| `core-prod` | `Deployment/core-home1-talos-prod-development-harbor-helm-core` | `core` | 1 | — (1 unset) | 0.8m / 0.8m | partial | — (1 unset) | 48.9Mi / 48.9Mi | partial | — |
| `core-prod` | `Deployment/core-home1-talos-prod-development-harbor-helm-jobservice` | `jobservice` | 1 | — (1 unset) | 3.5m / 3.5m | partial | — (1 unset) | 35.1Mi / 35.1Mi | partial | — |
| `core-prod` | `Deployment/core-home1-talos-prod-development-harbor-helm-nginx` | `nginx` | 2 | — (2 unset) | 1.0m / 1.2m | partial | — (2 unset) | 80.2Mi / 80.3Mi | partial | — |
| `core-prod` | `Deployment/core-home1-talos-prod-development-harbor-helm-portal` | `portal` | 1 | — (1 unset) | 0.3m / 0.3m | partial | — (1 unset) | 7.5Mi / 7.5Mi | partial | — |
| `core-prod` | `Deployment/core-home1-talos-prod-development-harbor-helm-registry` | `registry` | 1 | — (1 unset) | 0.3m / 0.3m | partial | — (1 unset) | 18.9Mi / 18.9Mi | partial | — |
| `core-prod` | `Deployment/core-home1-talos-prod-development-harbor-helm-registry` | `registryctl` | 1 | — (1 unset) | 0.2m / 0.2m | partial | — (1 unset) | 21.4Mi / 21.4Mi | partial | — |
| `core-prod` | `Deployment/core-home1-talos-prod-expo-operator` | `kube-prometheus-stack` | 1 | — (1 unset) | 2.3m / 2.3m | partial | — (1 unset) | 34.0Mi / 34.0Mi | partial | — |
| `core-prod` | `Deployment/core-home1-talos-prod-exporters-kube-state-metrics` | `kube-state-metrics` | 1 | — (1 unset) | 12.3m / 12.3m | partial | — (1 unset) | 47.9Mi / 47.9Mi | partial | — |
| `core-prod` | `Deployment/core-home1-talos-prod-exporters-prometheus-ipmi-exporter` | `ipmi-exporter` | 1 | 100m | 0.0m / 0.0m | <1% | 128.0Mi | 12.0Mi / 12.0Mi | 9% | — |
| `core-prod` | `Deployment/core-home1-talos-prod-externalsecrets-prod` | `external-secrets` | 1 | — (1 unset) | 1.2m / 1.2m | partial | — (1 unset) | 131.8Mi / 131.8Mi | partial | — |
| `core-prod` | `Deployment/core-home1-talos-prod-externalsecrets-prod-cert-controller` | `cert-controller` | 1 | — (1 unset) | 1.3m / 1.3m | partial | — (1 unset) | 62.1Mi / 62.1Mi | partial | — |
| `core-prod` | `Deployment/core-home1-talos-prod-externalsecrets-prod-webhook` | `webhook` | 1 | — (1 unset) | 0.4m / 0.4m | partial | — (1 unset) | 30.4Mi / 30.4Mi | partial | — |
| `core-prod` | `Deployment/core-home1-talos-prod-management-k8s-headlamp` | `headlamp` | 3 | — (3 unset) | 0.3m / 0.3m | partial | — (3 unset) | 28.3Mi / 46.1Mi | partial | — |
| `core-prod` | `Deployment/core-home1-talos-prod-net-testing-prod-iperf3` | `main` | 1 | — (1 unset) | 0.0m / 0.0m | partial | — (1 unset) | 1.1Mi / 1.1Mi | partial | — |
| `core-prod` | `Deployment/core-home1-talos-prod-net-testing-prod-librespeed` | `librespeed` | 1 | — (1 unset) | 0.0m / 0.0m | partial | — (1 unset) | 20.9Mi / 20.9Mi | partial | — |
| `core-prod` | `Deployment/core-home1-talos-prod-network-ipam-prod-kea` | `dhcp` | 3 | — (3 unset) | 11.5m / 14.2m | partial | — (3 unset) | 17.1Mi / 34.6Mi | partial | — |
| `core-prod` | `Deployment/core-home1-talos-prod-network-ipam-prod-kea` | `ns` | 3 | — (3 unset) | 0.2m / 0.2m | partial | — (3 unset) | 66.1Mi / 86.5Mi | partial | — |
| `core-prod` | `Deployment/core-home1-talos-prod-ops-configuration-prod-reloader` | `core-home1-talos-prod-ops-configuration-prod-reloader` | 1 | — (1 unset) | 1.6m / 1.6m | partial | — (1 unset) | 35.7Mi / 35.7Mi | partial | — |
| `core-prod` | `Deployment/core-home1-talos-prod-unifi-prod` | `unifi` | 1 | — (1 unset) | 6.2m / 6.2m | partial | — (1 unset) | 1083.8Mi / 1083.8Mi | partial | — |
| `core-prod` | `Deployment/core-kafka-ui` | `kafka-ui` | 1 | 100m | 6.9m / 6.9m | 7% | 512.0Mi | 363.8Mi / 363.8Mi | 71% | — |
| `core-prod` | `Deployment/core-mimir-proxy` | `cluster-query-filter` | 2 | 10m | 0.1m / 0.1m | <1% | 16.0Mi | 10.8Mi / 12.8Mi | 67% | — |
| `core-prod` | `Deployment/core-mimir-proxy` | `proxy` | 2 | 10m | 0.0m / 0.1m | <1% | 16.0Mi | 21.5Mi / 35.0Mi | 135% | — |
| `core-prod` | `Deployment/core-personal-travel-airtrail` | `airtrail` | 1 | 100m | 0.4m / 0.4m | <1% | 256.0Mi | 58.3Mi / 58.3Mi | 23% | — |
| `core-prod` | `Deployment/core-personal-travel-trek` | `trek` | 1 | 100m | 0.4m / 0.4m | <1% | 256.0Mi | 262.5Mi / 262.5Mi | 103% | — |
| `core-prod` | `Deployment/dc1-k3s-node1-baremetal-core` | `s3tftpd` | 1 | — (1 unset) | 0.0m / 0.0m | partial | — (1 unset) | 3.2Mi / 3.2Mi | partial | — |
| `core-prod` | `Deployment/donetick-app` | `donetick` | 1 | 25m | 0.0m / 0.0m | <1% | 128.0Mi | 24.4Mi / 24.4Mi | 19% | — |
| `core-prod` | `Deployment/donetick-habitsync` | `habitsync` | 1 | 100m | 1.6m / 1.6m | 2% | 512.0Mi | 370.8Mi / 370.8Mi | 72% | — |
| `core-prod` | `Deployment/grafana-core` | `grafana` | 2 | — (2 unset) | 32.6m / 33.9m | partial | — (2 unset) | 345.5Mi / 430.6Mi | partial | — |
| `core-prod` | `Deployment/grafana-core` | `grafana-sc-dashboard` | 2 | — (2 unset) | 0.3m / 0.4m | partial | — (2 unset) | 80.0Mi / 81.1Mi | partial | — |
| `core-prod` | `Deployment/history-app` | `dawarich` | 1 | 100m | 0.8m / 0.8m | <1% | 512.0Mi | 517.8Mi / 517.8Mi | 101% | — |
| `core-prod` | `Deployment/landing` | `landing` | 1 | 25m | 18.3m / 18.3m | 73% | 64.0Mi | 36.4Mi / 36.4Mi | 57% | — |
| `core-prod` | `Deployment/myloginspace-ldap` | `ldap` | 2 | 15m | 8.0m / 11.3m | 53% | 100.1Mi | 60.7Mi / 74.7Mi | 61% | — |
| `core-prod` | `Deployment/myloginspace-proxy` | `authentik-proxy` | 1 | 15m | 0.9m / 0.9m | 6% | 100.1Mi | 37.7Mi / 37.7Mi | 38% | — |
| `core-prod` | `Deployment/myloginspace-radius` | `radius` | 2 | 50m | 6.7m / 8.5m | 13% | 32.0Mi | 29.1Mi / 37.3Mi | 91% | — |
| `core-prod` | `Deployment/netbox` | `netbox` | 1 | 500m | 1.1m / 1.1m | <1% | 1024.0Mi | 1177.4Mi / 1177.4Mi | 115% | — |
| `core-prod` | `Deployment/ns-core-main` | `main` | 1 | 100m | 0.2m / 0.2m | <1% | 128.0Mi | 55.9Mi / 55.9Mi | 44% | — |
| `core-prod` | `Deployment/pgpool` | `pgpool` | 3 | 128m | 39.3m / 69.9m | 31% | 256.0Mi | 269.7Mi / 303.3Mi | 105% | — |
| `core-prod` | `Deployment/pgpool` | `recovery` | 3 | 10m | 0.8m / 0.9m | 8% | 32.0Mi | 0.7Mi / 0.8Mi | 2% | — |
| `core-prod` | `Deployment/sharing-kutt` | `app` | 1 | 50m | 1.0m / 1.0m | 2% | 128.0Mi | 67.0Mi / 67.0Mi | 52% | — |
| `core-prod` | `Deployment/sharing-kutt` | `redis-tls-proxy` | 1 | — (1 unset) | 0.1m / 0.1m | partial | — (1 unset) | 8.4Mi / 8.4Mi | partial | — |
| `core-prod` | `Deployment/strimzi-cluster-operator` | `strimzi-cluster-operator` | 1 | 200m | 4.1m / 4.1m | 2% | 384.0Mi | 295.5Mi / 295.5Mi | 77% | — |
| `core-prod` | `Deployment/traefik-core-s3-proxy` | `s3-proxy` | 3 | — (3 unset) | 0.1m / 0.2m | partial | — (3 unset) | 19.1Mi / 30.1Mi | partial | — |
| `core-prod` | `Dragonfly/dragonfly-core` | `dragonfly` | 2 | 500m | 30.1m / 46.4m | 6% | 500.0Mi | 222.1Mi / 295.4Mi | 44% | — |
| `core-prod` | `Dragonfly/dragonfly-pgpool` | `dragonfly` | 3 | 100m | 27.2m / 43.1m | 27% | 256.0Mi | 36.7Mi / 51.6Mi | 14% | — |
| `core-prod` | `Dragonfly/sharing-dragonfly` | `dragonfly` | 2 | — (2 unset) | 31.7m / 41.0m | partial | — (2 unset) | 16.9Mi / 17.7Mi | partial | — |
| `core-prod` | `Kafka/core-kafka` | `topic-operator` | 1 | — (1 unset) | 2.9m / 2.9m | partial | — (1 unset) | 257.7Mi / 257.7Mi | partial | — |
| `core-prod` | `Kafka/core-kafka` | `user-operator` | 1 | — (1 unset) | 2.1m / 2.1m | partial | — (1 unset) | 260.9Mi / 260.9Mi | partial | — |
| `core-prod` | `PerconaServerMongoDB/core-home1-talos-prod` | `backup-agent` | 3 | — (3 unset) | 1.8m / 2.4m | partial | — (3 unset) | 37.6Mi / 69.6Mi | partial | — |
| `core-prod` | `PerconaServerMongoDB/core-home1-talos-prod` | `mongod` | 3 | — (3 unset) | 83.5m / 129.0m | partial | — (3 unset) | 461.9Mi / 567.8Mi | partial | — |
| `core-prod` | `StatefulSet/core-corevault-prod` | `vault` | 1 | — (1 unset) | 123.6m / 123.6m | partial | — (1 unset) | 94.8Mi / 94.8Mi | partial | — |
| `core-prod` | `StatefulSet/core-home1-talos-prod-collectors-alloy` | `alloy` | 3 | — (3 unset) | 84.0m / 133.3m | partial | — (3 unset) | 1577.7Mi / 1725.7Mi | partial | — |
| `core-prod` | `StatefulSet/core-home1-talos-prod-collectors-alloy` | `config-reloader` | 3 | 1m | 0.0m / 0.0m | <1% | 5.0Mi | 9.0Mi / 11.2Mi | 180% | — |
| `core-prod` | `StatefulSet/core-home1-talos-prod-core-vault-prod` | `vault` | 1 | — (1 unset) | 134.0m / 134.0m | partial | — (1 unset) | 49.7Mi / 49.7Mi | partial | — |
| `core-prod` | `StatefulSet/core-home1-talos-prod-server` | `consul` | 1 | 1000m | 33.5m / 33.5m | 3% | 22888.2Mi | 32.0Mi / 32.0Mi | <1% | — |
| `core-prod` | `StatefulSet/keydb-core` | `keydb` | 1 | — (1 unset) | 36.4m / 36.4m | partial | — (1 unset) | 9.2Mi / 9.2Mi | partial | — |
| `core-prod` | `StatefulSet/keydb-core` | `redis-exporter` | 1 | — (1 unset) | 7.6m / 7.6m | partial | — (1 unset) | 9.6Mi / 9.6Mi | partial | — |
| `core-prod` | `StatefulSet/keydb-core` | `scripts` | 1 | — (1 unset) | 0.0m / 0.0m | partial | — (1 unset) | 1.4Mi / 1.4Mi | partial | — |
| `core-prod` | `StrimziPodSet/core-kafka-kafka` | `kafka` | 2 | 250m | 35.1m / 42.3m | 14% | 1024.0Mi | 915.6Mi / 1309.5Mi | 89% | — |
| `core-prod` | `StrimziPodSet/core-kafka-zookeeper` | `zookeeper` | 1 | 100m | 9.5m / 9.5m | 10% | 512.0Mi | 593.7Mi / 593.7Mi | 116% | — |
| `core-prod` | `TempoMonolithic/core-tempo` | `jaeger-query` | 1 | 15m | 0.1m / 0.1m | <1% | 2048.0Mi | 7.6Mi / 7.6Mi | <1% | — |
| `core-prod` | `TempoMonolithic/core-tempo` | `tempo` | 1 | 15m | 8.5m / 8.5m | 57% | — (1 unset) | 917.6Mi / 917.6Mi | partial | — |
| `core-prod` | `TempoMonolithic/core-tempo` | `tempo-query` | 1 | — (1 unset) | 0.0m / 0.0m | partial | — (1 unset) | 3.4Mi / 3.4Mi | partial | — |
| `core-prod` | `postgresql/psql-home1-yvr` | `connection-pooler` | 2 | 500m | 0.1m / 0.1m | <1% | 100.0Mi | 3.1Mi / 3.4Mi | 3% | — |
| `core-prod` | `postgresql/psql-home1-yvr` | `postgres` | 3 | 100m | 16.9m / 34.3m | 17% | 1907.3Mi | 807.5Mi / 1072.5Mi | 42% | — |
| `core-prod` | `postgresql/psql-home1-yvr` | `postgres-exporter` | 3 | 10m | 0.6m / 1.8m | 6% | 32.0Mi | 10.8Mi / 12.7Mi | 34% | — |
| `core-prod` | `postgresql/psql-main` | `postgres` | 3 | 100m | 162.2m / 234.0m | 162% | 1024.0Mi | 1434.4Mi / 2664.5Mi | 140% | — |
| `core-prod` | `postgresql/psql-main` | `postgres-exporter` | 3 | 10m | 0.0m / 0.0m | <1% | 32.0Mi | 15.4Mi / 18.4Mi | 48% | — |
| `core-testing` | `Deployment/core-home1-talos-prod-lab-storage-file-browser` | `file-browser` | 3 | — (3 unset) | 0.0m / 0.0m | partial | — (3 unset) | 4.4Mi / 4.8Mi | partial | — |
| `core-testing` | `Deployment/core-home1-talos-prod-lab-storage-request-writer` | `request-writer` | 1 | — (1 unset) | 0.0m / 0.0m | partial | — (1 unset) | 4.6Mi / 4.6Mi | partial | — |
| `core-testing` | `VirtualMachineInstance/debian-lab1` | `compute` | 1 | 32m | 16.5m / 16.5m | 52% | 901.0Mi | 392.2Mi / 392.2Mi | 44% | — |
| `core-testing` | `VirtualMachineInstance/testvm` | `compute` | 1 | 400m | 55.5m / 55.5m | 14% | 5420.0Mi | 4198.9Mi / 4198.9Mi | 77% | — |
| `core-testing` | `VirtualMachineInstance/wan-rt2` | `compute` | 1 | 4000m | 1623.3m / 1623.3m | 41% | 5520.0Mi | 4219.2Mi / 4219.2Mi | 76% | — |
| `crossplane-system-prod` | `Deployment/core-home1-talos-prod-ops-crossplane-ess-plugin-vault` | `ess-plugin-vault` | 1 | — (1 unset) | 0.0m / 0.0m | partial | — (1 unset) | 14.4Mi / 14.4Mi | partial | — |
| `crossplane-system-prod` | `Deployment/crossplane` | `crossplane` | 1 | 1m | 32.3m / 32.3m | 3229% | 256.0Mi | 728.1Mi / 728.1Mi | 284% | — |
| `crossplane-system-prod` | `Deployment/crossplane-rbac-manager` | `crossplane` | 1 | 1m | 0.8m / 0.8m | 80% | 256.0Mi | 38.5Mi / 38.5Mi | 15% | — |
| `crossplane-system-prod` | `FunctionRevision/function-auto-ready-d5bb310c3bb7` | `package-runtime` | 1 | — (1 unset) | 0.0m / 0.0m | partial | — (1 unset) | 7.7Mi / 7.7Mi | partial | — |
| `crossplane-system-prod` | `FunctionRevision/function-cel-filter-e27bffada1b4` | `package-runtime` | 1 | — (1 unset) | 0.0m / 0.0m | partial | — (1 unset) | 9.6Mi / 9.6Mi | partial | — |
| `crossplane-system-prod` | `FunctionRevision/function-go-templating-91d48cd1542b` | `package-runtime` | 1 | — (1 unset) | 30.0m / 30.0m | partial | — (1 unset) | 22.5Mi / 22.5Mi | partial | — |
| `crossplane-system-prod` | `FunctionRevision/function-patch-and-transform-201f894df2f6` | `package-runtime` | 1 | — (1 unset) | 0.0m / 0.0m | partial | — (1 unset) | 8.4Mi / 8.4Mi | partial | — |
| `crossplane-system-prod` | `FunctionRevision/function-sequencer-ea44063cdb58` | `package-runtime` | 1 | — (1 unset) | 0.0m / 0.0m | partial | — (1 unset) | 8.3Mi / 8.3Mi | partial | — |
| `crossplane-system-prod` | `FunctionRevision/function-shell-5708fb77860a` | `package-runtime` | 1 | — (1 unset) | 0.0m / 0.0m | partial | — (1 unset) | 6.8Mi / 6.8Mi | partial | — |
| `crossplane-system-prod` | `ProviderRevision/local-k8s-71953a1e5c15` | `package-runtime` | 1 | — (1 unset) | 0.6m / 0.6m | partial | — (1 unset) | 46.1Mi / 46.1Mi | partial | — |
| `crossplane-system-prod` | `ProviderRevision/provider-authentik-8aee71e41a4f` | `package-runtime` | 1 | — (1 unset) | 8.2m / 8.2m | partial | — (1 unset) | 37.4Mi / 37.4Mi | partial | — |
| `crossplane-system-prod` | `ProviderRevision/provider-minio-7af4d9157ece` | `package-runtime` | 1 | — (1 unset) | 2.9m / 2.9m | partial | — (1 unset) | 41.0Mi / 41.0Mi | partial | — |
| `crossplane-system-prod` | `ProviderRevision/provider-sql-a2c547580f15` | `package-runtime` | 1 | — (1 unset) | 4.5m / 4.5m | partial | — (1 unset) | 54.9Mi / 54.9Mi | partial | — |
| `crossplane-system-prod` | `ProviderRevision/provider-terraform-6fe8d52ff0a1` | `package-runtime` | 1 | — (1 unset) | 1.6m / 1.6m | partial | — (1 unset) | 146.7Mi / 146.7Mi | partial | — |
| `crossplane-system-prod` | `ProviderRevision/provider-vault-938c4dcacab6` | `package-runtime` | 1 | — (1 unset) | 8.0m / 8.0m | partial | — (1 unset) | 66.9Mi / 66.9Mi | partial | — |
| `dragonfly-operator-system` | `Deployment/dragonfly-operator-controller-manager` | `kube-rbac-proxy` | 1 | 5m | 0.0m / 0.0m | <1% | 64.0Mi | 18.1Mi / 18.1Mi | 28% | — |
| `dragonfly-operator-system` | `Deployment/dragonfly-operator-controller-manager` | `manager` | 1 | 10m | 1.8m / 1.8m | 18% | 64.0Mi | 56.8Mi / 56.8Mi | 89% | — |
| `eclipse-che` | `CheCluster/devspaces` | `che` | 2 | 256m | 5.4m / 6.1m | 2% | 512.0Mi | 680.3Mi / 758.5Mi | 133% | — |
| `eclipse-che` | `CheCluster/devspaces` | `che-dashboard` | 2 | 16m | 0.3m / 0.4m | 2% | 32.0Mi | 65.5Mi / 67.2Mi | 205% | — |
| `eclipse-che` | `CheCluster/devspaces` | `configbump` | 2 | 50m | 34.3m / 51.8m | 69% | 64.0Mi | 14.7Mi / 15.4Mi | 23% | — |
| `eclipse-che` | `CheCluster/devspaces` | `gateway` | 2 | 20m | 10.2m / 15.0m | 51% | 128.0Mi | 26.0Mi / 26.3Mi | 20% | — |
| `eclipse-che` | `CheCluster/devspaces` | `kube-rbac-proxy` | 2 | 100m | 4.2m / 5.4m | 4% | 64.0Mi | 19.0Mi / 23.1Mi | 30% | — |
| `eclipse-che` | `CheCluster/devspaces` | `oauth-proxy` | 2 | 100m | 13.6m / 18.2m | 14% | 64.0Mi | 14.4Mi / 18.2Mi | 22% | — |
| `eclipse-che` | `Deployment/che-operator` | `che-operator` | 2 | 16m | 1.0m / 1.7m | 6% | 128.0Mi | 24.6Mi / 33.0Mi | 19% | — |
| `gadget` | `DaemonSet/gadget` | `gadget` | 5 | — (5 unset) | 104.5m / 223.4m | partial | — (5 unset) | 80.3Mi / 135.2Mi | partial | — |
| `gpustack-system` | `DaemonSet/csi-nfs-node` | `liveness-probe` | 5 | 10m | 0.2m / 0.6m | 2% | 20.0Mi | 15.1Mi / 28.0Mi | 75% | — |
| `gpustack-system` | `DaemonSet/csi-nfs-node` | `nfs` | 5 | 10m | 0.0m / 0.1m | <1% | 20.0Mi | 19.8Mi / 47.8Mi | 99% | — |
| `gpustack-system` | `DaemonSet/csi-nfs-node` | `node-driver-registrar` | 5 | 10m | 0.1m / 0.4m | 1% | 20.0Mi | 7.2Mi / 15.0Mi | 36% | — |
| `gpustack-system` | `DaemonSet/csi-s3-node` | `liveness-probe` | 5 | 10m | 0.2m / 0.4m | 2% | 20.0Mi | 9.5Mi / 12.8Mi | 47% | — |
| `gpustack-system` | `DaemonSet/csi-s3-node` | `node-driver-registrar` | 5 | 10m | 0.0m / 0.1m | <1% | 20.0Mi | 9.8Mi / 25.5Mi | 49% | — |
| `gpustack-system` | `DaemonSet/csi-s3-node` | `s3` | 5 | 10m | 0.1m / 0.2m | <1% | 20.0Mi | 12.9Mi / 22.8Mi | 64% | — |
| `gpustack-system` | `DaemonSet/gpustack-operator-device-manager-amd` | `main` | 1 | 100m | 6.6m / 6.6m | 7% | 128.0Mi | 51.0Mi / 51.0Mi | 40% | — |
| `gpustack-system` | `DaemonSet/gpustack-operator-device-manager-nvidia` | `main` | 1 | 100m | 3.7m / 3.7m | 4% | 128.0Mi | 71.8Mi / 71.8Mi | 56% | — |
| `gpustack-system` | `DaemonSet/gpustack-worker` | `gpustack-worker` | 3 | — (3 unset) | 11.8m / 22.0m | partial | — (3 unset) | 805.0Mi / 853.1Mi | partial | — |
| `gpustack-system` | `DaemonSet/gpustack-worker-nvidia` | `gpustack-worker` | 1 | — (1 unset) | 21.0m / 21.0m | partial | — (1 unset) | 798.0Mi / 798.0Mi | partial | — |
| `gpustack-system` | `DaemonSet/node-feature-discovery-worker` | `worker` | 5 | 5m | 4.7m / 13.4m | 95% | 64.0Mi | 19.1Mi / 43.9Mi | 30% | — |
| `gpustack-system` | `Deployment/csi-nfs-controller` | `csi-provisioner` | 1 | 10m | 2.4m / 2.4m | 24% | 20.0Mi | 16.4Mi / 16.4Mi | 82% | — |
| `gpustack-system` | `Deployment/csi-nfs-controller` | `csi-resizer` | 1 | 10m | 3.2m / 3.2m | 32% | 20.0Mi | 32.8Mi / 32.8Mi | 164% | — |
| `gpustack-system` | `Deployment/csi-nfs-controller` | `csi-snapshotter` | 1 | 10m | 4.0m / 4.0m | 40% | 20.0Mi | 33.3Mi / 33.3Mi | 167% | — |
| `gpustack-system` | `Deployment/csi-nfs-controller` | `liveness-probe` | 1 | 10m | 0.2m / 0.2m | 2% | 20.0Mi | 13.5Mi / 13.5Mi | 68% | — |
| `gpustack-system` | `Deployment/csi-nfs-controller` | `nfs` | 1 | 10m | 0.0m / 0.0m | <1% | 20.0Mi | 24.2Mi / 24.2Mi | 121% | — |
| `gpustack-system` | `Deployment/csi-s3-controller` | `csi-provisioner` | 1 | 10m | 2.5m / 2.5m | 25% | 20.0Mi | 36.8Mi / 36.8Mi | 184% | — |
| `gpustack-system` | `Deployment/csi-s3-controller` | `s3` | 1 | 10m | 0.0m / 0.0m | <1% | 20.0Mi | 11.7Mi / 11.7Mi | 58% | — |
| `gpustack-system` | `Deployment/gpustack-operator-worker` | `main` | 1 | 500m | 10.2m / 10.2m | 2% | 512.0Mi | 76.8Mi / 76.8Mi | 15% | — |
| `gpustack-system` | `Deployment/kueue-controller-manager` | `manager` | 1 | 100m | 4.1m / 4.1m | 4% | 128.0Mi | 83.2Mi / 83.2Mi | 65% | — |
| `gpustack-system` | `Deployment/node-feature-discovery-gc` | `gc` | 1 | 10m | 0.1m / 0.1m | 1% | 128.0Mi | 20.6Mi / 20.6Mi | 16% | — |
| `gpustack-system` | `Deployment/node-feature-discovery-master` | `master` | 1 | 100m | 0.3m / 0.3m | <1% | 128.0Mi | 18.7Mi / 18.7Mi | 15% | — |
| `gpustack-system` | `Pod/gpustack-42c81a7038998465` | `default` | 1 | — (1 unset) | 0.3m / 0.3m | partial | — (1 unset) | 3436.2Mi / 3436.2Mi | partial | — |
| `gpustack-system` | `Pod/tts-1-0n3eh` | `default` | 1 | — (1 unset) | 1.9m / 1.9m | partial | — (1 unset) | 1375.1Mi / 1375.1Mi | partial | — |
| `gpustack-system` | `Pod/tts-1-hd-wg3c4` | `default` | 1 | — (1 unset) | 0.9m / 0.9m | partial | — (1 unset) | 1286.5Mi / 1286.5Mi | partial | — |
| `k8gb` | `Deployment/core-home1-talos-prod-network-global-prod-coredns` | `coredns` | 1 | 100m | 0.9m / 0.9m | <1% | 128.0Mi | 11.8Mi / 11.8Mi | 9% | — |
| `k8gb` | `Deployment/k8gb` | `k8gb` | 1 | 100m | 0.5m / 0.5m | <1% | 64.0Mi | 19.4Mi / 19.4Mi | 30% | — |
| `kepler-operator` | `Deployment/kepler-operator-controller` | `manager` | 1 | 10m | 1.9m / 1.9m | 19% | 64.0Mi | 20.5Mi / 20.5Mi | 32% | — |
| `kjones-che` | `DevWorkspace/core-backplane-prod-9mvq` | `che-gateway` | 1 | 50m | 11.0m / 11.0m | 22% | 64.0Mi | 20.6Mi / 20.6Mi | 32% | — |
| `kjones-che` | `DevWorkspace/core-backplane-prod-9mvq` | `devtools` | 1 | 2030m | 261.2m / 261.2m | 13% | 2163.3Mi | 2257.9Mi / 2257.9Mi | 104% | — |
| `kjones-che` | `DevWorkspace/core-business-lvdw` | `che-gateway` | 1 | 50m | 26.4m / 26.4m | 53% | 64.0Mi | 28.2Mi / 28.2Mi | 44% | — |
| `kjones-che` | `DevWorkspace/core-business-lvdw` | `devtools` | 1 | 4500m | 450.2m / 450.2m | 10% | 2163.3Mi | 1946.1Mi / 1946.1Mi | 90% | — |
| `kube-system` | `DaemonSet/bridge-vlan-permit-hpc2` | `bridge-vlan-permit` | 1 | — (1 unset) | 0.3m / 0.3m | partial | — (1 unset) | 1.8Mi / 1.8Mi | partial | — |
| `kube-system` | `DaemonSet/bridge-vlan-permit-hpc3` | `bridge-vlan-permit` | 1 | — (1 unset) | 0.0m / 0.0m | partial | — (1 unset) | 1.7Mi / 1.7Mi | partial | — |
| `kube-system` | `DaemonSet/bridge-vlan-permit-laptop2` | `bridge-vlan-permit` | 1 | — (1 unset) | 0.0m / 0.0m | partial | — (1 unset) | 0.9Mi / 0.9Mi | partial | — |
| `kube-system` | `DaemonSet/bridge-vlan-permit-srv2` | `bridge-vlan-permit` | 1 | — (1 unset) | 2.0m / 2.0m | partial | — (1 unset) | 3.1Mi / 3.1Mi | partial | — |
| `kube-system` | `DaemonSet/bridge-vlan-permit-srv3` | `bridge-vlan-permit` | 1 | — (1 unset) | 1.7m / 1.7m | partial | — (1 unset) | 3.2Mi / 3.2Mi | partial | — |
| `kube-system` | `DaemonSet/cilium` | `cilium-agent` | 5 | — (5 unset) | 88.9m / 184.7m | partial | — (5 unset) | 417.0Mi / 566.3Mi | partial | — |
| `kube-system` | `DaemonSet/core-home1-talos-prod-exporters-dcgm-exporter` | `exporter` | 1 | 100m | 3.3m / 3.3m | 3% | 128.0Mi | 403.2Mi / 403.2Mi | 315% | — |
| `kube-system` | `DaemonSet/core-home1-talos-prod-exporters-prometheus-node-exporter` | `node-exporter` | 5 | — (5 unset) | 5.0m / 16.1m | partial | — (5 unset) | 15.7Mi / 28.1Mi | partial | — |
| `kube-system` | `DaemonSet/core-home1-talos-prod-exporters-prometheus-smartctl-exporter-0` | `main` | 5 | — (5 unset) | 0.0m / 0.0m | partial | — (5 unset) | 14.8Mi / 23.6Mi | partial | — |
| `kube-system` | `DaemonSet/core-home1-talos-prod-net-base-frr-k8s` | `controller` | 5 | — (5 unset) | 1.1m / 3.1m | partial | — (5 unset) | 33.6Mi / 54.0Mi | partial | — |
| `kube-system` | `DaemonSet/core-home1-talos-prod-net-base-frr-k8s` | `frr` | 5 | — (5 unset) | 1.5m / 2.3m | partial | — (5 unset) | 46.4Mi / 52.8Mi | partial | — |
| `kube-system` | `DaemonSet/core-home1-talos-prod-net-base-frr-k8s` | `frr-metrics` | 5 | — (5 unset) | 1.9m / 5.5m | partial | — (5 unset) | 23.8Mi / 31.1Mi | partial | — |
| `kube-system` | `DaemonSet/core-home1-talos-prod-net-base-frr-k8s` | `frr-status` | 5 | — (5 unset) | 0.5m / 0.7m | partial | — (5 unset) | 27.0Mi / 48.4Mi | partial | — |
| `kube-system` | `DaemonSet/core-home1-talos-prod-net-base-frr-k8s` | `reloader` | 5 | — (5 unset) | 0.0m / 0.0m | partial | — (5 unset) | 4.9Mi / 7.7Mi | partial | — |
| `kube-system` | `DaemonSet/dynamic-networks-controller-ds` | `dynamic-networks-controller` | 5 | 100m | 10.3m / 23.5m | 10% | 50.0Mi | 22.4Mi / 41.0Mi | 45% | — |
| `kube-system` | `DaemonSet/kube-multus-ds` | `kube-multus` | 5 | 100m | 0.6m / 0.8m | <1% | 256.0Mi | 61.2Mi / 98.3Mi | 24% | — |
| `kube-system` | `DaemonSet/kube-sriov-cni-ds` | `kube-sriov-cni` | 4 | 100m | 0.0m / 0.0m | <1% | 50.0Mi | 1.1Mi / 1.9Mi | 2% | — |
| `kube-system` | `DaemonSet/kube-sriov-device-plugin` | `kube-sriovdp` | 4 | 250m | 0.0m / 0.0m | <1% | 40.0Mi | 22.0Mi / 48.4Mi | 55% | — |
| `kube-system` | `DaemonSet/lbnodeagent` | `lbnodeagent` | 4 | 8m | 3.1m / 4.3m | 39% | 64.0Mi | 25.6Mi / 36.2Mi | 40% | — |
| `kube-system` | `Deployment/allocator` | `allocator` | 1 | 100m | 0.1m / 0.1m | <1% | 64.0Mi | 13.4Mi / 13.4Mi | 21% | — |
| `kube-system` | `Deployment/cilium-operator` | `cilium-operator` | 2 | — (2 unset) | 5.3m / 9.4m | partial | — (2 unset) | 76.7Mi / 80.1Mi | partial | — |
| `kube-system` | `Deployment/clustermesh-apiserver` | `apiserver` | 1 | — (1 unset) | 3.1m / 3.1m | partial | — (1 unset) | 47.2Mi / 47.2Mi | partial | — |
| `kube-system` | `Deployment/clustermesh-apiserver` | `etcd` | 1 | — (1 unset) | 5.7m / 5.7m | partial | — (1 unset) | 52.4Mi / 52.4Mi | partial | — |
| `kube-system` | `Deployment/clustermesh-apiserver` | `kvstoremesh` | 1 | — (1 unset) | 1.0m / 1.0m | partial | — (1 unset) | 28.7Mi / 28.7Mi | partial | — |
| `kube-system` | `Deployment/core-home1-talos-prod-k8s-metrics-prod-metrics-server` | `metrics-server` | 2 | 100m | 9.1m / 10.0m | 9% | 200.0Mi | 63.4Mi / 73.2Mi | 32% | — |
| `kube-system` | `Deployment/core-home1-talos-prod-net-base-cf-dns` | `external-dns` | 1 | — (1 unset) | 2.3m / 2.3m | partial | — (1 unset) | 69.7Mi / 69.7Mi | partial | — |
| `kube-system` | `Deployment/core-home1-talos-prod-net-base-frr-k8s-statuscleaner` | `frr-k8s-statuscleaner` | 1 | — (1 unset) | 1.9m / 1.9m | partial | — (1 unset) | 50.0Mi / 50.0Mi | partial | — |
| `kube-system` | `Deployment/core-home1-talos-prod-ops-resources-descheduler` | `descheduler` | 1 | 32m | 1.2m / 1.2m | 4% | 64.0Mi | 57.1Mi / 57.1Mi | 89% | — |
| `kube-system` | `Deployment/core-home1-talos-prod-ops-resources-goldilocks-controller` | `goldilocks` | 1 | 25m | 1.2m / 1.2m | 5% | 256.0Mi | 53.1Mi / 53.1Mi | 21% | — |
| `kube-system` | `Deployment/core-home1-talos-prod-ops-resources-goldilocks-dashboard` | `goldilocks` | 2 | 25m | 0.4m / 0.6m | 2% | 256.0Mi | 13.2Mi / 16.6Mi | 5% | — |
| `kube-system` | `Deployment/core-home1-talos-prod-ops-resources-vpa-admission-controller` | `vpa` | 1 | 50m | 0.5m / 0.5m | 1% | 200.0Mi | 75.6Mi / 75.6Mi | 38% | — |
| `kube-system` | `Deployment/core-home1-talos-prod-ops-resources-vpa-recommender` | `vpa` | 1 | 50m | 2.8m / 2.8m | 6% | 500.0Mi | 96.2Mi / 96.2Mi | 19% | — |
| `kube-system` | `Deployment/core-nfd-gc` | `gc` | 1 | 10m | 0.5m / 0.5m | 5% | 128.0Mi | 14.9Mi / 14.9Mi | 12% | — |
| `kube-system` | `Deployment/core-nfd-master` | `master` | 1 | 100m | 1.0m / 1.0m | <1% | 128.0Mi | 19.1Mi / 19.1Mi | 15% | — |
| `kube-system` | `Deployment/coredns` | `coredns` | 4 | 100m | 16.1m / 22.9m | 16% | 70.0Mi | 39.6Mi / 68.8Mi | 57% | — |
| `kube-system` | `Deployment/envoy-gateway` | `envoy-gateway` | 2 | 100m | 3.8m / 6.4m | 4% | 256.0Mi | 139.7Mi / 182.4Mi | 55% | — |
| `kube-system` | `Deployment/hami-core-scheduler` | `kube-scheduler` | 1 | — (1 unset) | 8.6m / 8.6m | partial | — (1 unset) | 81.1Mi / 81.1Mi | partial | — |
| `kube-system` | `Deployment/hami-core-scheduler` | `vgpu-scheduler-extender` | 1 | — (1 unset) | 5.4m / 5.4m | partial | — (1 unset) | 76.6Mi / 76.6Mi | partial | — |
| `kube-system` | `Deployment/inteldeviceplugins-controller-manager` | `manager` | 1 | 100m | 13.8m / 13.8m | 14% | 100.0Mi | 84.0Mi / 84.0Mi | 84% | — |
| `kube-system` | `Deployment/nvidia-dra-driver-gpu-controller` | `compute-domain` | 1 | — (1 unset) | 0.0m / 0.0m | partial | — (1 unset) | 18.0Mi / 18.0Mi | partial | — |
| `kube-system` | `GatewayClass/eg-core.mylogin.space` | `envoy` | 4 | 500m | 11.8m / 24.5m | 2% | 256.0Mi | 73.1Mi / 122.9Mi | 29% | — |
| `kube-system` | `GatewayClass/eg-core.mylogin.space` | `shutdown-manager` | 4 | 10m | 0.1m / 0.2m | <1% | 32.0Mi | 21.3Mi / 24.7Mi | 66% | — |
| `kube-system` | `GpuDevicePlugin/gpudeviceplugin-sample` | `intel-gpu-plugin` | 2 | 40m | 0.4m / 0.5m | <1% | 45.0Mi | 10.6Mi / 12.4Mi | 24% | — |
| `kube-system` | `Node/hpc2` | `kube-apiserver` | 1 | 200m | 176.3m / 176.3m | 88% | 512.0Mi | 6545.2Mi / 6545.2Mi | 1278% | — |
| `kube-system` | `Node/hpc2` | `kube-controller-manager` | 1 | 50m | 20.0m / 20.0m | 40% | 256.0Mi | 307.8Mi / 307.8Mi | 120% | — |
| `kube-system` | `Node/hpc2` | `kube-scheduler` | 1 | 10m | 1.6m / 1.6m | 16% | 64.0Mi | 75.4Mi / 75.4Mi | 118% | — |
| `kubevirt` | `DaemonSet/virt-handler` | `virt-handler` | 4 | 10m | 1.8m / 2.3m | 18% | 325.0Mi | 190.9Mi / 295.1Mi | 59% | — |
| `kubevirt` | `Deployment/virt-api` | `virt-api` | 2 | 5m | 1.5m / 2.5m | 30% | 500.0Mi | 232.4Mi / 235.6Mi | 46% | — |
| `kubevirt` | `Deployment/virt-controller` | `virt-controller` | 2 | 10m | 3.0m / 5.4m | 30% | 275.0Mi | 176.2Mi / 200.1Mi | 64% | — |
| `kubevirt` | `Deployment/virt-operator` | `virt-operator` | 1 | 10m | 8.8m / 8.8m | 88% | 450.0Mi | 390.4Mi / 390.4Mi | 87% | — |
| `kubevirt-manager` | `Deployment/kubevirt-manager` | `kubevirtmgr` | 1 | — (1 unset) | 0.0m / 0.0m | partial | — (1 unset) | 58.3Mi / 58.3Mi | partial | — |
| `longhorn-system` | `DaemonSet/longhorn-csi-plugin` | `longhorn-csi-plugin` | 5 | — (5 unset) | 0.7m / 1.7m | partial | — (5 unset) | 19.2Mi / 34.6Mi | partial | — |
| `longhorn-system` | `DaemonSet/longhorn-csi-plugin` | `longhorn-liveness-probe` | 5 | — (5 unset) | 0.5m / 0.7m | partial | — (5 unset) | 14.7Mi / 27.6Mi | partial | — |
| `longhorn-system` | `DaemonSet/longhorn-csi-plugin` | `node-driver-registrar` | 5 | — (5 unset) | 0.1m / 0.2m | partial | — (5 unset) | 8.5Mi / 19.1Mi | partial | — |
| `longhorn-system` | `DaemonSet/longhorn-manager` | `longhorn-manager` | 5 | — (5 unset) | 58.6m / 86.3m | partial | — (5 unset) | 378.6Mi / 479.3Mi | partial | — |
| `longhorn-system` | `DaemonSet/longhorn-manager` | `pre-pull-share-manager-image` | 5 | — (5 unset) | 0.0m / 0.0m | partial | — (5 unset) | 0.4Mi / 0.5Mi | partial | — |
| `longhorn-system` | `Deployment/csi-attacher` | `csi-attacher` | 3 | — (3 unset) | 0.4m / 0.7m | partial | — (3 unset) | 12.6Mi / 16.1Mi | partial | — |
| `longhorn-system` | `Deployment/csi-provisioner` | `csi-provisioner` | 3 | — (3 unset) | 0.8m / 1.4m | partial | — (3 unset) | 13.8Mi / 21.2Mi | partial | — |
| `longhorn-system` | `Deployment/csi-resizer` | `csi-resizer` | 3 | — (3 unset) | 0.7m / 1.4m | partial | — (3 unset) | 12.5Mi / 13.9Mi | partial | — |
| `longhorn-system` | `Deployment/csi-snapshotter` | `csi-snapshotter` | 3 | — (3 unset) | 0.9m / 2.2m | partial | — (3 unset) | 12.1Mi / 14.9Mi | partial | — |
| `longhorn-system` | `Deployment/longhorn-driver-deployer` | `longhorn-driver-deployer` | 1 | — (1 unset) | 0.0m / 0.0m | partial | — (1 unset) | 10.4Mi / 10.4Mi | partial | — |
| `longhorn-system` | `Deployment/longhorn-ui` | `longhorn-ui` | 2 | — (2 unset) | 0.0m / 0.0m | partial | — (2 unset) | 3.0Mi / 3.0Mi | partial | — |
| `longhorn-system` | `EngineImage/ei-493e04e7` | `engine-image-ei-493e04e7` | 5 | — (5 unset) | 13.3m / 26.2m | partial | — (5 unset) | 1.7Mi / 2.5Mi | partial | — |
| `longhorn-system` | `EngineImage/ei-5ee94262` | `engine-image-ei-5ee94262` | 5 | — (5 unset) | 13.6m / 28.9m | partial | — (5 unset) | 4.3Mi / 8.3Mi | partial | — |
| `longhorn-system` | `InstanceManager/instance-manager-12201edc928b8070a2ea79b772a8e048` | `instance-manager` | 1 | 1918m | 169.0m / 169.0m | 9% | — (1 unset) | 1639.2Mi / 1639.2Mi | partial | — |
| `longhorn-system` | `InstanceManager/instance-manager-33ed82b33c6cbc892823aed17f68ed98` | `instance-manager` | 1 | 1918m | 134.6m / 134.6m | 7% | — (1 unset) | 441.2Mi / 441.2Mi | partial | — |
| `longhorn-system` | `InstanceManager/instance-manager-406a137c07bbc862586888973935100a` | `instance-manager` | 1 | 1918m | 47.3m / 47.3m | 2% | — (1 unset) | 116.3Mi / 116.3Mi | partial | — |
| `longhorn-system` | `InstanceManager/instance-manager-5e967de87c22c2f7a6458003b19134c7` | `instance-manager` | 1 | 318m | 3.5m / 3.5m | 1% | — (1 unset) | 16.2Mi / 16.2Mi | partial | — |
| `longhorn-system` | `InstanceManager/instance-manager-6f7a0ae0845d35ba1a46ab44b26d8ca1` | `instance-manager` | 1 | 318m | 34.8m / 34.8m | 11% | — (1 unset) | 146.1Mi / 146.1Mi | partial | — |
| `longhorn-system` | `InstanceManager/instance-manager-71740d0185bf368f4894a5839afe0dd0` | `instance-manager` | 1 | 478m | 3.7m / 3.7m | <1% | — (1 unset) | 55.7Mi / 55.7Mi | partial | — |
| `longhorn-system` | `InstanceManager/instance-manager-87c58b803ed8dc23a0c826e7f42bd75b` | `instance-manager` | 1 | 318m | 188.6m / 188.6m | 59% | — (1 unset) | 1288.4Mi / 1288.4Mi | partial | — |
| `longhorn-system` | `InstanceManager/instance-manager-a8c622a383125909b4dd92d29b95bff1` | `instance-manager` | 1 | 1918m | 116.1m / 116.1m | 6% | — (1 unset) | 588.9Mi / 588.9Mi | partial | — |
| `longhorn-system` | `InstanceManager/instance-manager-bc8d2330b8b70a7078138bba0e8c0269` | `instance-manager` | 1 | 318m | 68.5m / 68.5m | 22% | — (1 unset) | 421.1Mi / 421.1Mi | partial | — |
| `longhorn-system` | `InstanceManager/instance-manager-edf97639218aa935971ca2ba1792c307` | `instance-manager` | 1 | 478m | 24.2m / 24.2m | 5% | — (1 unset) | 501.3Mi / 501.3Mi | partial | — |
| `longhorn-system` | `ShareManager/pvc-0391a981-74a4-4af7-a28e-ef8bb337b251` | `share-manager` | 1 | — (1 unset) | 1.4m / 1.4m | partial | — (1 unset) | 50.6Mi / 50.6Mi | partial | — |
| `longhorn-system` | `ShareManager/pvc-2b563205-b12b-41ce-bf49-b57344563291` | `share-manager` | 1 | — (1 unset) | 1.2m / 1.2m | partial | — (1 unset) | 38.8Mi / 38.8Mi | partial | — |
| `longhorn-system` | `ShareManager/pvc-3641e248-9540-436b-a9cf-61beda911c17` | `share-manager` | 1 | — (1 unset) | 1.5m / 1.5m | partial | — (1 unset) | 39.3Mi / 39.3Mi | partial | — |
| `longhorn-system` | `ShareManager/pvc-4a9b1e18-2b5f-4ed1-86c2-be2f0ebf3a47` | `share-manager` | 1 | — (1 unset) | 1.4m / 1.4m | partial | — (1 unset) | 55.1Mi / 55.1Mi | partial | — |
| `longhorn-system` | `ShareManager/pvc-65a87e2d-ddcb-4854-9020-89e735fd1141` | `share-manager` | 1 | — (1 unset) | 1.1m / 1.1m | partial | — (1 unset) | 39.1Mi / 39.1Mi | partial | — |
| `longhorn-system` | `ShareManager/pvc-b299c40a-65b0-4b4f-850a-a320e913dfb8` | `share-manager` | 1 | — (1 unset) | 1.5m / 1.5m | partial | — (1 unset) | 38.6Mi / 38.6Mi | partial | — |
| `longhorn-system` | `ShareManager/pvc-c200909f-38d0-4ff0-9f06-e4ba2c8cfed7` | `share-manager` | 1 | — (1 unset) | 1.3m / 1.3m | partial | — (1 unset) | 59.9Mi / 59.9Mi | partial | — |
| `operator-lifecycle-manager` | `CatalogSource/devworkspace-operator-catalog` | `registry-server` | 1 | 10m | 17.4m / 17.4m | 174% | 50.0Mi | 18.8Mi / 18.8Mi | 38% | — |
| `operator-lifecycle-manager` | `CatalogSource/operatorhubio-catalog` | `registry-server` | 1 | 10m | 10.2m / 10.2m | 102% | 50.0Mi | 45.1Mi / 45.1Mi | 90% | — |
| `operator-lifecycle-manager` | `ClusterServiceVersion/packageserver` | `packageserver` | 1 | 10m | 3.3m / 3.3m | 33% | 50.0Mi | 80.2Mi / 80.2Mi | 160% | — |
| `operator-lifecycle-manager` | `Deployment/catalog-operator` | `catalog-operator` | 1 | 10m | 0.4m / 0.4m | 4% | 80.0Mi | 164.1Mi / 164.1Mi | 205% | — |
| `operator-lifecycle-manager` | `Deployment/olm-operator` | `olm-operator` | 1 | 10m | 2.6m / 2.6m | 26% | 160.0Mi | 104.5Mi / 104.5Mi | 65% | — |
| `operators` | `CDI/cdi` | `cdi-deployment` | 1 | 100m | 11.6m / 11.6m | 12% | 150.0Mi | 59.6Mi / 59.6Mi | 40% | — |
| `operators` | `ClusterServiceVersion/cloudnative-pg.v1.29.1` | `manager` | 1 | — (1 unset) | 3.0m / 3.0m | partial | — (1 unset) | 91.8Mi / 91.8Mi | partial | — |
| `operators` | `ClusterServiceVersion/devworkspace-operator.v0.42.0` | `devworkspace-controller` | 1 | 250m | 1.8m / 1.8m | <1% | 100.0Mi | 60.3Mi / 60.3Mi | 60% | — |
| `operators` | `ClusterServiceVersion/tempo-operator.v0.19.0` | `manager` | 1 | 100m | 2.5m / 2.5m | 3% | 64.0Mi | 81.9Mi / 81.9Mi | 128% | — |
| `operators` | `Deployment/devworkspace-webhook-server` | `webhook-server` | 2 | 100m | 0.2m / 0.2m | <1% | 20.0Mi | 14.9Mi / 15.4Mi | 75% | — |
| `power-monitor` | `PowerMonitorInternal/power-monitor` | `power-monitor` | 5 | — (5 unset) | 23.3m / 45.2m | partial | — (5 unset) | 57.1Mi / 96.4Mi | partial | — |
| `valkey-operator-system` | `Deployment/valkey-operator-controller-manager` | `manager` | 1 | 10m | 1.0m / 1.0m | 10% | 64.0Mi | 17.8Mi / 17.8Mi | 28% | — |
| `velero-system` | `DaemonSet/node-agent` | `node-agent` | 4 | 500m | 2.2m / 6.7m | <1% | 512.0Mi | 71.7Mi / 120.1Mi | 14% | — |
| `velero-system` | `Deployment/consul-backup` | `consul-backup` | 1 | 32m | 0.0m / 0.0m | <1% | 15.3Mi | 8.1Mi / 8.1Mi | 53% | — |
| `velero-system` | `Deployment/velero-core` | `velero` | 1 | 22m | 3.0m / 3.0m | 14% | 100.1Mi | 146.5Mi / 146.5Mi | 146% | — |
