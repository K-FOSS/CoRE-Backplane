# UniFi chart

This chart deploys the UniFi Network Application and integrates it with CoRE
database, secrets, ingress, DNS and storage. It is owned by
`Apps/Network/Unifi.yaml`, currently targeting the selected Home1 production
cluster.

It includes the controller workload, device/client service ports, Gateway
route, persistent data/certificates, MongoDB user integration, ExternalSecret
and PushSecret resources.

The chart also runs the [UnPoller Prometheus exporter](https://github.com/unpoller/unpoller)
as a controller sidecar. UnPoller polls the controller through loopback and
serves metrics on the private `unifi-metrics` Service at `/metrics`; the
[Prometheus Operator ServiceMonitor](https://prometheus-operator.dev/docs/api-reference/api/#servicemonitor)
scrapes it every 30 seconds. The exporter image is pinned to the upstream
container digest recorded in `values.yaml`.

Before enabling the exporter, create the read-only UniFi controller account
and store its credentials in CoreVault at `Unifi/Monitoring` with `Username`
and `Password` properties. The chart reads that path through the
[External Secrets Operator](https://external-secrets.io/latest/api/externalsecret/)
and intentionally fails to start the exporter when the required Secret is
absent. The account must have access to every site whose metrics should be
collected. The monitoring Service is private and is not attached to the public
Gateway route.

UnPoller is disabled by default. Set `unpoller.enabled: true` to enable it.
When disabled, the sidecar, metrics Service, ExternalSecret and ServiceMonitor
are omitted from rendered output, and UnPoller credentials are not needed.
Before enabling it, ensure the required CoreVault credentials are present.

The controller uses HTTPS `/status` startup, readiness and liveness probes on
the named `https` container port (8443). The startup probe allows up to 15
minutes for the UniFi application to initialize before the other probes take
effect. The image documents 8443 as the controller GUI/API port in the
[upstream container documentation](https://github.com/goofball222/unifi#readme).

The container starts through a small, idempotent wrapper that patches the
minified `swai.*.js` bundle to suppress the recurring “Upgrade to UniFi OS
Server” modal. This follows the workaround described in the
[upstream issue](https://github.com/goofball222/unifi/issues/187) and the
[related implementation discussion](https://community.ui.com/questions/Cannot-get-rid-of-annoyingUpgrade-to-UniFi-OS-Server-in-unifi-console/f39d36f6-ad39-4d30-9365-785c35c00678).
The patch is best-effort: if the upstream bundle changes, the container logs
the mismatch and starts normally. A new image may therefore require updating
the patch pattern.
The public route hostname is configured by `domain` and supplied by the owning
ApplicationSet. The ExternalDNS hostname is configured independently through
the chart's `hostname` value.

Before upgrades or moves, back up application state and test restoration.
Verify database health, web login, certificates, device inform/adoption and
every required TCP/UDP port. Verify the `unifi-metrics` ServiceMonitor is
discoverable and that `up` remains 1 for the exporter. Avoid changing
controller address, DNS, certificates and database location simultaneously.
