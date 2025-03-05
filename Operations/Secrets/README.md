# K-FOSS/CoRE-Backplane Secret Operations

This chart installs the [External Secrets Operator](https://external-secrets.io/main/) 


We have a few main secret stores, we use our two internal Hashicorp Vaults, CoreVault and Vault, CoreVault unlocks Vault. So secrets which are part of the initial phase of rolling out CoRE go into CoreVault while most application and end user services go under Vault

# Bootstrapping

In the event of recreating the system from scratch you will need to manually add the CoreVault Token

```
kubectl create secret generic central-corevault-token --from-literal=token=hvs.TOKEN_HERE -n core-prod
```