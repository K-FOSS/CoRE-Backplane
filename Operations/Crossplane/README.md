# K-FOSS/CoRE-Backplane Crossplane Deployment

This is a helm chart that is deployed by [ArgoCD](../../ArgoCD/) that includes deployment of [Crossplane](https://www.crossplane.io/) and a bunch of the providers I have found really useful and helpful for my operations here at CoRE.

# Providers

## Minio Provider


## Database Provider

For auto configuring databases, database roles, and the like so that the LDAP Auth to PSQL and soon to be other databases can just magically work seamlessly for users and services accounts deployed by [SSO User](../SSO/User/) I use [provider-sql](https://marketplace.upbound.io/providers/crossplane-contrib/provider-sql/v0.11.0)

## Vault Provider

I use the [provider-vault](https://marketplace.upbound.io/providers/upbound/provider-vault/v2.1.0) Provider to auto configure Kubernetes service account auth, OAuth SSO and the like for [CoreVault](../../Hashicorp/CoreVault/) and [Vault](../../Hashicorp/Vault/)

## Terraform Provider

I have been using Terraform in my personal infrastructure since 2019 or awhile before, it's been really useful, although I stopped after moving to ArgoCD, although eventually I ran the Flux Subsystem for ArgoCD with the Flux Terraform Controller, although now I am able to rely entirely upon ArgoCD stock using Crossplane and the [Terraform provider](https://github.com/upbound/provider-terraform), you will see many uses of this to autoconfigure a large part of my systems and allow full Infrastructure as code.