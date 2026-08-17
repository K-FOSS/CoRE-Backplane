# Lab storage request writer

The [Lab storage ApplicationSet](../../Apps/Lab/Storage.yaml) renders this
chart with the Lovely Helm plugin and deploys it to every selected bare-metal
tenant cluster. Its destination namespace is `core-testing` for the current
ApplicationSet values.

## Current behavior

The chart creates an RWX `PersistentVolumeClaim`, a one-replica Deployment,
and an internal ClusterIP Service named `<release>-request-writer`. The pod
mounts the claim at `/data`; each HTTP connection accepted on port 8080 creates
a unique `request-XXXXXX` file containing the HTTP request line and responds
with `201 Created`. TCP health probes deliberately do not issue HTTP requests,
so they do not add files.

The Deployment uses the [Docker Official BusyBox image](https://hub.docker.com/_/busybox)
pinned to a multi-architecture manifest digest. Its small `nc`-based listener
is intentionally a test workload, not an internet-facing or authenticated
application.

## Prerequisites and verification

The target cluster's default StorageClass must provide `ReadWriteMany` storage;
this chart does not select a StorageClass. After Argo CD reconciles, verify the
claim is bound and the Deployment is available, then from the same namespace:

```sh
kubectl -n core-testing run request-writer-check --rm -i --restart=Never \
  --image=docker.io/library/busybox@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0 -- \
  wget -qO- http://<release>-request-writer:8080/
kubectl -n core-testing exec deploy/<release>-request-writer -- ls -1 /data
```

The request command should return a created filename, and the subsequent list
should include that file. Replace `<release>` with the Argo CD application's
Helm release name. The commands use the [Kubernetes Service DNS model](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/).

## Rollback and deletion

Removing the Deployment and Service stops new writes. PVC lifecycle remains
controlled by the ApplicationSet's `preserveResourcesOnDeletion: true` policy;
do not delete the claim unless its retained test data is intentionally no
longer needed.
