# CORE-Backplane KeyDB/Redis

[KeyDB]() is a [Redis]() and memcached compatible FOSS service that is much easier to cluster, and much more thorugh controls around multi tenancy.

We currently manually "use" 3 "databases" and these are due to the applications they are used being critical to the deployment and maintence of the KeyDB system and everything else

| Database | Application         | Purpose                           |
|    0     | Core DNS & Harbor   | Distributed DNS Cache             |
|    1     | Authentik Cache     | Authentik                         |
|    2     | Authentik Queue     | TODO                              |
|    3     | Authentik websocket | TODO                              |
|    4     | Authentik Outpost   | TODO                              |
| 5        | Pomerium            | SSO Audited Proxy/Gatekeeper      |
| 6        | AWX/Ansible         | Ansible Tower, Automation         |
| 7        | Harbor              | Container Images, Charts, etc     |
| 8        | Harbor              | Container Images, Charts, etc     |
| 9        | Harbor              | Container Images, Charts, etc     |
| 10       | ArgoCD              | The deployerer                    |
| 11       | Cortex              | Metrics S3                        |
| 12       | Loki                | Logs S3                           |
| 13       | Tempo               | Traces Store                      |
| 14       | Harbor               | Traces Store                      |
| 15       | CoTURN    



| 40 | Grafana | Yay!

| 50 | NextCloud | Yay!

| 70 | RSSHub | Yay!

| 80 | Netbox | Yay!
| 81 | Netbox | Yay!
| 82 | Netbox | Yay!
| 83 | Netbox | Yay!
| 84 | Netbox | Yay!
| 85 | Netbox | Yay!

| 95 | Blink | Link Sharing | |
| 100 | Outline | Docs |
| 120 | eJabberD | MQTT, SIP, and XMPP broker |

Further usage relies upon ArgoCD, Database Operator, KeyDB, TwemProxy, OAM/KubeVela, and Crossplane ****TODO: Make that stuff****
