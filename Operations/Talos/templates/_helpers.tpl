{{- define "talos-image-factory.name" -}}
{{- default "talos-image-factory" .Values.imageFactory.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "talos-image-factory.labels" -}}
app.kubernetes.io/name: '{{ include "talos-image-factory.name" . }}'
app.kubernetes.io/instance: '{{ .Release.Name }}'
app.kubernetes.io/managed-by: '{{ .Release.Service }}'
app.kubernetes.io/component: 'image-factory'
{{- end -}}
