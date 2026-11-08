{{- define "lab-storage.defaultValues" -}}
env: 'prod'
longhorn:
  provisioner: 'driver.longhorn.io'
testPersistence:
  accessModes: ['ReadWriteMany']
  size: '5Gi'
requestWriter:
  enabled: true
  image: 'docker.io/library/busybox'
  imageDigest: 'sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0'
  mountPath: '/data'
  port: 8080
  replicas: 1
fileBrowser:
  enabled: true
  image: 'docker.io/library/nginx'
  imageDigest: 'sha256:a8b39bd9cf0f83869a2162827a0caf6137ddf759d50a171451b335cecc87d236'
  mountPath: '/usr/share/nginx/html'
  port: 8080
  replicas: 1
garage:
  enabled: false
  hubRegion: 'yvr'
  name: 'lab-garage'
  image: 'dxflrs/garage:v2.4.1@sha256:9c96caa2612d3411acc5b0e6701fb238dbfba33e533a6d7d3d811a4b12d0d020'
  replicationFactor: 3
  storageReplicas: 3
  dataSize: '20Gi'
  metadataSize: '2Gi'
  dataStorageClass: 'garage-lab-yvr-data'
  metadataStorageClass: 'garage-lab-yvr-metadata'
  rpcPublicAddrSubnet: '172.20.56.0/21'
  secretStoreRef:
    kind: 'ClusterSecretStore'
    name: 'mainvault-core'
  remoteKey: 'Garage/LabStorage'
  adminTokenProperty: 'AdminToken'
  rpcSecretProperty: 'RPCSecret'
  tls:
    enabled: true
    serviceName: 'lab-garage-s3'
    gatewayName: 'main-gw'
    gatewayNamespace: 'core-prod'
  bootstrap:
    generatedSecretName: 'lab-garage-bootstrap-generated'
  federation:
    enabled: true
    writerRegion: 'yvr'
    remoteRegion: 'yxl'
    remoteDatacenter: 'dc1'
    adminHostnameSuffix: 'mylogin.space'
    localStorageHostnameTemplate: 'garage-{region}-storage-{ordinal}.cluster.mylogin.space'
    storageRpcEndpointTemplate: ''
    remoteStorageNodes: []
  user:
    enabled: false
    name: 'lab-garage-test'
    displayName: 'Lab Garage test user'
    buckets: []
    credentialsSecretName: 'lab-garage-test-s3-creds'
  storage:
    topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: 'kubernetes.io/hostname'
        whenUnsatisfiable: 'DoNotSchedule'
        labelSelector:
          matchLabels:
            garage.rajsingh.info/cluster: 'lab-garage'
            garage.rajsingh.info/tier: 'storage'
siteLocalGarage:
  enabled: false
  name: 'lab-garage-local'
  image: 'dxflrs/garage:v2.4.1@sha256:9c96caa2612d3411acc5b0e6701fb238dbfba33e533a6d7d3d811a4b12d0d020'
  replicationFactor: 3
  storageReplicas: 3
  dataSize: '20Gi'
  metadataSize: '2Gi'
  dataStorageClass: 'garage-lab-local-yvr-data'
  metadataStorageClass: 'garage-lab-local-yvr-metadata'
  secretStoreRef:
    kind: 'ClusterSecretStore'
    name: 'mainvault-core'
  remoteKey: 'Garage/LabStorageLocal'
  adminTokenProperty: 'AdminToken'
  rpcSecretProperty: 'RPCSecret'
garageUI:
  enabled: false
  hostname: 'lab-garage-ui.mylogin.space'
  accessGroup: 'Server Admins'
  garage:
    serviceName: 'lab-garage'
    s3Port: 3900
    adminPort: 3903
garage-ui-web:
  enabled: false
  nameOverride: 'lab-garage-ui'
  fullnameOverride: 'lab-garage-ui'
  replicaCount: 2
  image:
    repository: 'noooste/garage-ui'
    tag: 'v0.14.0@sha256:e4a33c448304a3f6e60f08d6aa71b2471fd79ac870a5c7e178ea247dea3238b3'
    pullPolicy: 'IfNotPresent'
  config:
    server:
      host: '::'
      port: 8080
      environment: 'production'
      domain: 'lab-garage-ui.mylogin.space'
      protocol: 'https'
      root_url: 'https://lab-garage-ui.mylogin.space'
    garage:
      endpoint: 'http://lab-garage:3900'
      region: 'garage'
      admin_endpoint: 'http://lab-garage:3903'
      admin_token: ''
      existingSecret:
        name: 'lab-garage-bootstrap'
        key: 'admin-token'
    auth:
      metrics_public: true
      admin:
        enabled: false
      oidc:
        enabled: false
  resources:
    requests:
      cpu: '50m'
      memory: '128Mi'
    limits:
      cpu: '500m'
      memory: '512Mi'
  serviceMonitor:
    enabled: true
    interval: '60s'
{{- end }}

{{- define "lab-storage.values.init" -}}
{{- $_ := merge .Values (include "lab-storage.defaultValues" . | fromYaml) -}}
{{- end }}
