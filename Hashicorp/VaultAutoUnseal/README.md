# CoRE/CoRE-Backplane VaultAutoUnseal


How To recreate CoRE Vault Unsealer after a total system colapse and unable to use ExternalSecrets

Obtain the CoRE Vault Unseal keys from 1Password

And then manually unseal the CoreVault using the pod IP obtained from ArgoCD


Manually create the CoreVault secret

```
kubectl create secret generic -n core-prod central-corevault-token --from-literal=token=OBTAINED_FROM_1PASSWORD
```