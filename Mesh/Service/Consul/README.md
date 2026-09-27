# Consul

This Helm wrapper deploys HashiCorp Consul through the upstream `consul` chart.
It contains only the values that differ from the upstream defaults.

Deployment-specific values, including server replica count, bootstrap
expectation, and rolling-update partition, are supplied by the Consul
ApplicationSet in `Apps/Hashicorp/Consul.yaml`. They are intentionally not
duplicated in this chart.

## Documentation

- [Production scaling and upgrade runbook](RUNBOOK.md)
- [Upgrade work](TODO.md)
- [Cluster and Consul backups](../../../Backups/README.md)

## Validation

Render and inspect the chart before merging a change:

```bash
helm dependency build
helm lint .
helm template consul .
```

Production changes must also be reviewed in Argo CD before syncing.
