# Consul upgrade work

- [ ] Confirm the Consul, Consul-K8s, Helm chart, and Kubernetes versions
  currently running in each production cluster.
- [ ] Verify and store an off-cluster Consul snapshot.
- [x] Confirm continuous Consul backups are replicating to Cloudflare R2. See
  the [Backups documentation](../../../Backups/README.md#consul-backups).
- [ ] Test snapshot restoration and manual Raft recovery outside production.
- [ ] Confirm three failure domains and sufficient persistent-storage capacity.
- [ ] Scale the production datacenter from one voter to three by following
  [RUNBOOK.md](RUNBOOK.md).
- [ ] Record peak `consul.runtime.alloc_bytes` and container working-set memory.
- [ ] Select and validate lower memory requests and limits from observed usage.
- [ ] Choose a stable target chart supported by the Kubernetes version.
- [ ] Review all intervening Consul release notes and compatibility guidance.
- [ ] Render and review the complete Argo CD diff before each production sync.
- [ ] Upgrade one server at a time with `updatePartition`.
- [ ] Remove the release-candidate chart dependency after the stable upgrade.
