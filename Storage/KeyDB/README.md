# CORE-Backplane KeyDB/Redis

[KeyDB]() is a [Redis]() and memcached compatible FOSS service that is much easier to cluster, and much more thorugh controls around multi tenancy.

We currently manually "use" 3 "databases" and these are due to the applications they are used being critical to the deployment and maintence of the KeyDB system and everything else

| Database | Application         | Purpose                      |
|    0     | Core DNS            | Distributed DNS Cache        |
|    1     | Authentik Cache     | Authentik        |
|    2     | Authentik Queue     | TODO        |
|    3     | Authentik websocket | TODO        |
|    4     | Authentik Outpost   | TODO        |
| 5        | Pomerium            | SSO Audited Proxy/Gatekeeper |
| 6        | AWX/Ansible         | Ansible Tower, Automation    |
| 10       | ArgoCD              | The deployerer               |



Further usage relies upon ArgoCD, Database Operator, KeyDB, TwemProxy, OAM/KubeVela, and Crossplane ****TODO: Make that stuff****
