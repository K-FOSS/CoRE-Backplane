# SSO User

This is a [Crossplane](../../Crossplane/) Custom resource designed to automate the creation of user and service accounts.


This system auto configures [Minio](../../../Storage/S3), [Authentik](../../../AAA/), [PSQL](../../../Databases/PSQL/) 


It first creates a Crossplane Terraform workspace in order to use some templates and logic to create policies, usernames, and figure out some logic regarding the options configured 

# Examples 

```yaml
apiVersion: mylogin.space/v1alpha1
kind: User
metadata:
  name: gitlab-user
  namespace: core-prod

spec:
  name: GitLab

  username: gl-core

  database:
    name: gl-core

  buckets:
    - gitlab-uploads
    - gitlab-packages
    - gitlab-ci-secure-files
    - gitlab-backups

  writeConnectionSecretToRef:
    name: gitlab-user
```

