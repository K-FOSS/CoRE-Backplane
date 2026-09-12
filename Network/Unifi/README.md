# UniFi chart

This chart deploys the UniFi Network Application and integrates it with CoRE
database, secrets, ingress, DNS and storage. It is owned by
`Apps/Network/Unifi.yaml`, currently targeting the selected Home1 production
cluster.

It includes the controller workload, device/client service ports, Gateway
route, persistent data/certificates, MongoDB user integration, ExternalSecret
and PushSecret resources.

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
ApplicationSet.

Before upgrades or moves, back up application state and test restoration.
Verify database health, web login, certificates, device inform/adoption and
every required TCP/UDP port. Avoid changing controller address, DNS,
certificates and database location simultaneously.
