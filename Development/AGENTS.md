# Development chart local guidance

## Forgejo Actions timeout contract

The Forgejo Actions timeout is a coordinated server-and-runner setting. Keep
all three limits at `12h` when changing this behavior:

- `forgejo.gitea.config.actions.ENDLESS_TASK_TIMEOUT` is the Forgejo server
  limit for continuously updating Actions jobs.
- `runner.timeout` is the Forgejo Runner maximum job duration.
- `runner.shutdown_timeout` is the runner shutdown grace period.

The runner Deployment's `terminationGracePeriodSeconds` must be at least the
runner shutdown timeout plus 30 seconds (`43230` for `12h`) so Kubernetes does
not terminate the runner before it can finish shutting down. The server-side
Actions setting is rendered by the upstream Forgejo chart into `app.ini`; the
runner settings are rendered into each generated runner Secret's
`config.yaml`.

Keep the values synchronized across `values.yaml`, ApplicationSet-injected
values, and any deployment-specific overrides. Verify both rendered
configurations after changes. Refer to Forgejo's [configuration cheat
sheet](https://forgejo.org/docs/latest/admin/config-cheat-sheet/) for
`ENDLESS_TASK_TIMEOUT` and the [Forgejo Runner configuration
reference](https://forgejo.org/docs/latest/admin/actions/configuration/) for
the runner timeout fields.

## Forgejo rollout strategy

Forgejo is intentionally configured with a `RollingUpdate` strategy using
`maxSurge: '100%'` and `maxUnavailable: '0'` for a smooth replacement. The
upstream chart warns that RollingUpdate can cause issues because Forgejo is not
HA-ready and the deployment remains single-replica. Keep the shared persistent
storage available to the temporary overlap and verify database connectivity,
readiness, login, repository access, and Actions after reconciliation. Do not
increase the replica count as part of this change.
