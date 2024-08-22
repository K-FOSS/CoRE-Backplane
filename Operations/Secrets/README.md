# Bootstrapping

In the event of recreating the system from scratch you will need to manually add the CoreVault Token

```
kubectl create secret generic central-corevault-token --from-literal=token=hvs.TOKEN_HERE -n core-prod
```