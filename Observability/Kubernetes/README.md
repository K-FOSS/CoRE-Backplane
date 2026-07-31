# Kubernetes resource metrics

This chart deploys the official
[Kubernetes Metrics Server](https://github.com/kubernetes-sigs/metrics-server)
using chart version `3.13.1`. The
[`core-observability-k8s` ApplicationSet](../../Apps/Observability/Kubernetes.yaml)
targets both infrastructure clusters at 15-second resolution and
`dc1-k3s-node1` at 60-second resolution, deploying into `kube-system`.

Metrics Server serves the aggregated `metrics.k8s.io` API used by autoscaling
and `kubectl top`. It watches node/pod metadata and polls each kubelet's resource
metrics endpoint. It does not remote-write samples to Mimir and is distinct
from the Alloy/Prometheus monitoring pipeline. Its traffic scales with node
count and the configured metric resolution, but repository inspection shows
the repeated cluster-wide Alloy DaemonSet watches are the larger structural API
traffic multiplier.

The deployment uses one replica, cert-manager-issued serving TLS, and
`--kubelet-insecure-tls=true` for kubelet scraping. The latter weakens kubelet
server authentication and should be revisited when trusted kubelet serving
certificates are available.

Verify the APIService `Available` condition, Metrics Server readiness, kubelet
scrape errors, and `kubectl top nodes/pods`. A healthy pod alone does not prove
the aggregated API works. Render and lint with the cluster domain and
ApplicationSet resolution override. Roll back through Git/Argo CD; removal can
break HPA/VPA and operational tooling that depends on `metrics.k8s.io`.
