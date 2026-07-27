# SSO User platform APIs

This chart installs Crossplane APIs that turn a namespaced identity claim into
an Authentik account and, optionally, PostgreSQL and MinIO/S3 resources. It is
the account-provisioning layer used by platform services; it does not deploy
Authentik, PostgreSQL, MinIO, Crossplane, or their providers.

The fleet entry point is
[`Apps/Infra/Crossplane/User.yaml`](../../../Apps/Infra/Crossplane/User.yaml).
It deploys this chart to selected infrastructure clusters in the
`crossplane-system-prod` namespace. The XRDs and Compositions are
cluster-scoped, while `User` and `BucketCredential` claims and their connection
Secrets are namespaced.

## What is active

| API | Implementation | Current state |
| --- | --- | --- |
| `User.mylogin.space/v1alpha1` | `sso-user` pipeline Composition | Active. Creates an Authentik identity and can add PostgreSQL and S3 resources. |
| `BucketCredential.mylogin.space/v1alpha1` | `sso-s3-credentials` resource-mode Composition | Present, but appears incomplete/legacy. Do not use for new consumers without testing it. |
| `Group.mylogin.space/v1alpha1` | Commented templates | Not installed. |
| `Tenant.mylogin.space/v1alpha1` | Commented XRD | Not installed. |

The `User` API is the supported entry point in this directory. The rest of
this document focuses on its observed template behavior.

## Reconciliation flow

```text
User claim
  -> XUser composite
  -> function-go-templating
  -> Terraform Workspace using ProviderConfig/authentik
  -> Authentik user + generated username/password
  -> claim connection Secret
       |
       +-> optional PostgreSQL Role, Database, and grants
       |
       +-> optional MinIO buckets, policy, LDAP attachment,
           and temporary S3 credentials
```

The base Terraform Workspace generates a random username when `spec.username`
is absent, generates a password, resolves the Authentik `LDAPService` group,
and creates the Authentik user. Later resources wait for that Workspace's
connection details.

All reconciliation is declarative, but it crosses several controllers:
Crossplane, the Go-templating function, provider-terraform, the Authentik
Terraform provider, provider-sql, and the MinIO provider. An Argo CD
application being `Synced` only proves that the API definitions were applied;
it does not prove a `User` claim completed.

## Prerequisites

- Crossplane with composition pipeline support.
- `function-go-templating`, named `function-go-templating` by default.
- provider-terraform and an Authentik-capable Terraform
  `ProviderConfig` named `authentik`.
- An Authentik group named `LDAPService`.
- For `spec.psql.enabled`: provider-sql PostgreSQL CRDs plus the Terraform and
  Crossplane ProviderConfigs selected by the claim.
- For `spec.s3.enabled`: the MinIO `Bucket` CRD plus the Terraform and
  Crossplane ProviderConfigs selected by the claim.
- Network and credentials allowing those providers to reach Authentik,
  PostgreSQL, and MinIO.

Defaults are defined in [`values.yaml`](values.yaml). In particular, the
default provider names are environment-specific and must exist on every
cluster where claims reconcile.

## User claim

Minimal service identity:

```yaml
apiVersion: mylogin.space/v1alpha1
kind: User
metadata:
  name: example-service
  namespace: core-prod
spec:
  name: Example Service
  username: example-service
  writeConnectionSecretToRef:
    name: example-service
```

`spec.name` is the only field required by the XRD. Omitting `spec.username`
causes the composition to generate a ten-letter lowercase username. The
generated password is 16 characters.

### Implemented fields

| Field | Behavior |
| --- | --- |
| `spec.name` | Friendly name assigned to the Authentik user. Required. |
| `spec.username` | Optional fixed username; generated when omitted. |
| `spec.ldaps.uri` | URI prefix used in the emitted `ldapsURI`; defaults to `ldaps://`. |
| `spec.psql.enabled` | Enables PostgreSQL role/grant reconciliation. |
| `spec.psql.createUserDatabase` | Creates a database named after the username unless set to `false`; schema default is `true`. |
| `spec.psql.databases[]` | Existing databases on which grants are applied. |
| `spec.psql.crossplane.*Provider` | Overrides PostgreSQL provider configuration names. |
| `spec.s3.enabled` | Enables bucket, policy, and LDAP-policy reconciliation. |
| `spec.s3.region` | Region used for created buckets; defaults to `us-east-1`. |
| `spec.s3.createUserBucket` | Creates a username-named bucket unless explicitly `false`. |
| `spec.s3.createBuckets` | Creates entries in `s3.buckets` unless explicitly `false`. |
| `spec.s3.buckets[]` | Buckets included in the user's MinIO policy. |
| `spec.s3.createCredentials` | Requests temporary LDAP-derived S3 credentials; defaults to `false`. |
| `spec.s3.writeCredentialsSecretRef` | Destination for the optional S3 credential Secret. |
| `spec.s3.crossplane.*Provider` | Overrides MinIO/S3 provider configuration names. |
| `spec.writeConnectionSecretToRef.name` | Claim connection Secret written in the claim namespace. |

### Schema fields that are not implemented

The XRD currently exposes more intent than the Composition consumes:

- `email` is ignored.
- `serviceAccount` is ignored; the Terraform input is hardcoded to `true`, so
  Authentik creates a service account.
- `groups` is ignored; every user is placed only in `LDAPService`.
- `mysql` and `mongodb` have schemas but create no resources or connection
  details.
- `AVoIP` is not consumed.
- `psql.uri` is not used by the PostgreSQL managed resources.

Do not rely on these fields until both the composition and this document are
updated. Schema acceptance is not evidence that a feature is implemented.

## PostgreSQL provisioning

Example:

```yaml
apiVersion: mylogin.space/v1alpha1
kind: User
metadata:
  name: gitlab-database
  namespace: core-prod
spec:
  name: GitLab
  username: gl-core
  psql:
    enabled: true
    createUserDatabase: true
    databases:
      - gitlab_shared
  writeConnectionSecretToRef:
    name: gitlab-database
```

When enabled, the composition:

1. Creates a provider-sql `Role` with login privileges and the generated
   Authentik password.
2. By default creates a database named after the lowercase username, owned by
   that role.
3. Uses a Terraform Workspace to grant `CREATE`, `CONNECT`, and `TEMPORARY` on
   listed databases, plus broad privileges on their public schema, tables,
   and sequences.

The generated database uses `deletionPolicy: Orphan` and management policies
that exclude deletion. Removing the claim therefore does not imply that its
database is removed. Review the Role, grants, and external database separately
during deprovisioning.

## MinIO/S3 provisioning

Example:

```yaml
apiVersion: mylogin.space/v1alpha1
kind: User
metadata:
  name: gitlab-object-storage
  namespace: core-prod
spec:
  name: GitLab
  username: gl-core
  s3:
    enabled: true
    region: us-east-1
    createUserBucket: false
    buckets:
      - gitlab-uploads
      - gitlab-packages
    createCredentials: true
    writeCredentialsSecretRef:
      name: gitlab-s3
      namespace: core-prod
  writeConnectionSecretToRef:
    name: gitlab-object-storage
```

When enabled, the composition:

1. Builds the authorized bucket set from the username bucket and
   `spec.s3.buckets`.
2. Optionally creates those buckets as MinIO managed resources.
3. Creates a username-named MinIO policy granting `s3:*` on the selected
   buckets and their objects.
4. Attaches that policy to the Authentik user's LDAP distinguished name.
5. Optionally exchanges the LDAP username/password for temporary S3
   credentials and copies them to `writeCredentialsSecretRef`.

Created bucket resources use `deletionPolicy: Orphan`. Setting
`createUserBucket` or `createBuckets` to `false` excludes creation, not policy
access: named buckets can still be included in the policy.

Temporary credentials are requested for seven days and the template attempts
to reuse or refresh them. This path handles passwords and access keys inside
Terraform Workspace connection Secrets. Treat all intermediate and copied
Secrets as sensitive, and test rotation before depending on it in production.

## Connection details and Secrets

The claim's `writeConnectionSecretToRef` receives only the connection details
published by the final `CompositeConnectionDetails` object:

| Key | Availability |
| --- | --- |
| `username` | Always, after the base Workspace reconciles. |
| `password` | Always, after the base Workspace reconciles. |
| `ldapsBIND` | Always; currently uses `cn=<username>,ou=users,dc=ldap,dc=mylogin,dc=space`. |
| `ldapsURI` | Always; contains only the LDAP endpoint, despite being marked sensitive upstream. |
| `S3Hostname` | Only when S3 is enabled and the MinIO attachment Workspace emits it. |

The XRD advertises additional connection keys, but the current pipeline does
not publish most of them to the claim Secret. In particular, do not expect
`psqlURI`, `database`, S3 access keys, ports, or the miscellaneous keys listed
in `connectionSecretKeys` to appear there.

The composition also creates UID-based intermediate Secrets in the claim
namespace, including the Authentik Workspace Secret and feature-specific
Terraform Secrets. Consumers should reference the stable claim Secret or the
explicit S3 credential destination, not these implementation details.

Never print these Secrets in routine diagnostics. Prefer checking key names:

```sh
kubectl -n core-prod get secret example-service \
  -o go-template='{{ range $key, $_ := .data }}{{ printf "%s\n" $key }}{{ end }}'
```

## Fleet rollout and debug claim

`Apps/Infra/Crossplane/User.yaml` currently targets two named infrastructure
clusters. It injects only the `debug` value. When `debug: true`,
`templates/User/Debugging/UserLab.yaml` creates a live test `User` with
PostgreSQL enabled. This is not merely verbose logging: it provisions an
identity and database resources.

Before enabling debug on another cluster, review the rendered test claim and
its external side effects. Disable or remove it with the same care as a normal
user deprovisioning.

## Validation

Render the chart without creating the debug claim:

```sh
helm lint Operations/SSO/User --set debug=false
helm template sso-user Operations/SSO/User \
  --namespace crossplane-system-prod \
  --set debug=false > /tmp/sso-user.yaml
```

Rendering validates the outer Helm templates only. The Composition contains
an inline Go template, which in turn emits Terraform HCL and Kubernetes
resources. Each layer can fail after a successful `helm template`.

After syncing the API definitions, inspect a claim from the outside in:

```sh
kubectl -n core-prod get user
kubectl -n core-prod describe user example-service
kubectl get xuser
kubectl describe xuser
kubectl -n core-prod get workspace
kubectl -n core-prod get secret
```

For an enabled feature, also inspect its downstream resources and provider
events:

```sh
kubectl get roles.postgresql.sql.crossplane.io
kubectl get databases.postgresql.sql.crossplane.io
kubectl get buckets.minio.crossplane.io
kubectl -n core-prod get workspace -o wide
```

Start with claim/composite conditions, then the base Authentik Workspace,
then optional feature resources. A missing downstream resource commonly means
the base Workspace is not Ready or has not exposed connection details.

## Known risks and deprovisioning

- Several composed resources are annotated ready unconditionally. A `Ready`
  composite can therefore overstate downstream health; verify the external
  Authentik, PostgreSQL, and MinIO objects.
- Identity creation, policy changes, database grants, and credential issuance
  are security-sensitive. Review provider access and target namespaces before
  accepting claims from additional tenants.
- Hostnames, ports, the LDAP bind DN suffix, and the `LDAPService` group are
  hardcoded in the composition rather than sourced consistently from values.
- The S3 branch contains complex time-based credential refresh logic and
  assumes intermediate resources and connection keys exist. Exercise it in a
  non-critical namespace before first use or provider upgrades.
- Usernames become external resource names. Changing a username can replace
  identity and authorization state rather than performing a harmless rename.
- Orphaned buckets and databases require an explicit retention or removal
  decision. Deleting the Kubernetes claim is not a complete offboarding
  procedure.

Before deleting a claim, inventory its Authentik user, PostgreSQL role and
grants, databases, MinIO policy and attachment, buckets, temporary
credentials, and consuming workloads. Revoke credentials first, preserve data
that has a retention requirement, and verify external cleanup after
reconciliation.
