# Bootstrapping TLS System

In order to get Cert-Manager working again after a critical system error/when rebuilding the system you must manually create the CloudFlare token, this is the same token/secret used in the Backplane networking/ExternalDNS

```bash
kubectl create secret generic -n cert-manager cf-token --from-li
teral=Token=INSERT_TOKEN_HERE
```