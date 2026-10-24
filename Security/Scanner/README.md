# CoRE-Backplane Security/Scanner Stack

This stack installs secureCodeBox and its scanner charts in the
`securecodebox-system` namespace. The operator and Trivy database cache are
enabled for the YVR security-scanner Application. It is owned by the
[Security Scanner ApplicationSet](../../Apps/Security/Scanner.yaml).

## Dependencies and rendering

The pinned secureCodeBox 5.8.0 operator and scanner charts are pulled from the
[secureCodeBox Helm OCI repository](https://github.com/secureCodeBox/secureCodeBox/tree/main/deploy/helm),
with operator documentation in the [secureCodeBox documentation](https://www.securecodebox.io/docs/).
The operator dependency uses the same OCI source as the scanner dependencies
so rendering does not depend on the unavailable legacy chart repository.

The ApplicationSet injects the site-local S3 endpoint through Lovely. Keep the
S3 credential Secret reference in `values.yaml`; do not place credentials in
this stack or its rendered output.

## Verification

Resolve dependencies and render locally with:

```sh
helm dependency update Security/Scanner
helm lint Security/Scanner
helm template security-scanner Security/Scanner --namespace securecodebox-system
```

Validate the operator and scanner CRDs and controller conditions after the
owning Argo CD application is reconciled.
