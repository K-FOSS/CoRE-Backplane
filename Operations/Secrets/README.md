# Secret operations deployment

This Lovely deployment installs External Secrets Operator and defines the
CoreVault/Main Vault secret stores plus bootstrap token synchronization. It is
owned by `Apps/Infra/ExternalSecrets.yaml`.

## Secret tiers

- **CoreVault** holds bootstrap material required before the main platform
  secret chain is available.
- **Vault** holds most application and user/service credentials.
- `ExternalSecret` pulls credentials into Kubernetes.
- `PushSecret` publishes generated credentials back to an authorized store.

## Bootstrap

Rebuilding currently requires introducing a CoreVault token out of band. Do
not paste the real value into Git, shell history, tickets or shared logs.
Create it through a protected input path, verify the ClusterSecretStore, and
rotate/revoke bootstrap credentials when supported.

Example bootstrap Secret using a placeholder token:

```sh
kubectl create secret generic central-corevault-token \
  --namespace core-prod \
  --from-literal=token=hvs.TOKEN_HERE
```

Replace `hvs.TOKEN_HERE` only in a protected operator session. The placeholder
must remain unchanged in committed documentation.

Before controller/store changes, inventory dependent ExternalSecrets, refresh
intervals, deletion/creation policies and target-secret ownership. Validate a
non-critical read and push path, then monitor synchronization errors and
credential rotation. Preserve an emergency credential outside the systems it
must recover.
