# CoRE/CoRE-Backplane Vault

From ArgoCD or other web management plane run

```
vault operator init
```

Copy this output to a Bitwarden Secret note under the Secrets Admin Group, synced by LDAP, DO NOT send this to anyone, but ensure all site secret ADMINs print off the Unseal keys and root token securely.

Open up https://corevault.int.mylogin.space and use the Unseal Keys to unseal the vault



Using the Root Token login to the WebUI at https://corevault.int.mylogin.space




From the Web UI create KV `CORE_SECRETS`

And create a `CORE_SECRETS/COREVAULT_KEYS` with the UNSEALKEY-1, UNSEALKEY-2, UNSEALKEY-3, UNSEALKEY-4, UNSEALKEY-5,


Save this

## Creating Vault Transit Seal System

From the web console (ArgoCD) 

```sh
export VAULT_TOKEN=(TOKEN FROM THE OPERATOR INIT)
vault secrets enable transit
vault write -f transit/keys/autounseal
```

From the WebUI Create a policy named `autounseal` with the following config

```hcl
path "transit/encrypt/autounseal" {
   capabilities = [ "update" ]
}

path "transit/decrypt/autounseal" {
   capabilities = [ "update" ]
}
```

This next part the commands need to be run quickly as it expires within 120 seconds, don't be like Entrapta and get distracted and have to create a new sealed token

```
vault token create -orphan -policy="autounseal" -wrap-ttl=120 -period=24h
```

From this copy the field `wrapping_token` and run

```
VAULT_TOKEN=INSERT_WRAPPING_TOKEN_HERE vault unwrap
```


From this copy the enitre output and create a new SecureNote called CoreVault-TransitProcess

Using the token field create a new secret on CoRE-VAULT under `CORE_SECRETS/VAULT_BOOTSTRAP`



