# Bootstrapping

In the event of needing to recreate the Vault service without the existing cluster running, you need to manually create the Vault unseal token

Using ArgoCD Open up CoreVault

```
export VAULT_TOKEN=(TOKEN FROM 1PASSWORD)
vault token create -orphan -policy=""autounseal"" -wrap-ttl=120 -period=24h

export VAULT_TOKEN=

vault unwrap

```

Now within the cluster create the token 
```
kubectl create secret generic maincore-vault-token --from-literal=token=TOKEN_HERE -n core-prod
```