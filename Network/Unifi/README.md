# UniFi chart

This chart deploys the UniFi Network Application and integrates it with CoRE
database, secrets, ingress, DNS and storage. It is owned by
`Apps/Network/Unifi.yaml`, currently targeting the selected Home1 production
cluster.

It includes the controller workload, device/client service ports, Gateway
route, persistent data/certificates, MongoDB user integration, ExternalSecret
and PushSecret resources.

Before upgrades or moves, back up application state and test restoration.
Verify database health, web login, certificates, device inform/adoption and
every required TCP/UDP port. Avoid changing controller address, DNS,
certificates and database location simultaneously.
