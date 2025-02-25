# K-FOSS/CoRE-Backplane Network Ingress Stack

This stack mainly deploys and configures Envoy using the Envoy Gateway project


| Label                      | Type                                  |      Options                         | Options |
|--------------------------- | --------------------------------------| ------------------------------------ | ------- |
| resolvemy.host/gw          | Gateway Reference Name                | The name of the gateway resources    |
| resolvemy.host/gw-ns       | The namespace of the relevant gateway |
| resolvemy.host/security    | SecurityMode                          | public, private                    |