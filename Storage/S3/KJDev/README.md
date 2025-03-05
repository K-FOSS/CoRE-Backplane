# CoRE-Backplane/S3 Stack

This deploys our internal S3 system using the [Minio Operator](../00-Minio.yaml) we do have DNS for buckets configured automatically using [External-DNS](https://github.com/kubernetes-sigs/external-dns)



This also uses the Prometheus operator in order to setup monitoring from our [Dashboards Stack](../../../Observability/Dashboards/), this allows us to monitor the current disk usage, as of current day 2025-02-11 I only have a few hundred gigabytes availabile on the single node cluster I have until I get a few more servers imaged and managed by the Kubernetes Cluster API in the [Cluster Operations Stack](../../../Operations/Clusters/) and deployed in the [Bare Metal Provisoning System Stack](../../../Network/BareMetal/)