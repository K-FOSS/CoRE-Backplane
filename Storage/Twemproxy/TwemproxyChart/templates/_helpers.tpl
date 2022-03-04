{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "twemproxy.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "twemproxy.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "twemproxy.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "twemproxy.labels" -}}
helm.sh/chart: {{ .Chart.Name }}
{{ include "twemproxy.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Selector labels
*/}}
{{- define "twemproxy.selectorLabels" -}}
app.kubernetes.io/name: {{ include "twemproxy.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Selector labels twemproxy
*/}}
{{- define "twemproxy.twemproxySelectorLabels" -}}
app.kubernetes.io/name: {{ include "twemproxy.name" . }}-twemproxy
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Create the name of the service account to use
*/}}
{{- define "twemproxy.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
    {{ default (include "twemproxy.fullname" .) .Values.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{/*
  Create redis connections list with weight 1, based in the number of stateful sets and the specified name.
*/}}
{{- define "twemproxy.connectionsList" -}}
{{- $redisName := include "twemproxy.fullname" . -}}
{{- $redisPort := (.Values.redisPort | int) -}}
{{- range $i, $e := until (.Values.replicaCount|int) -}}
- {{ printf "%s-%d.%s-backend:%d:1\n" $redisName $i $redisName $redisPort }}
{{- end -}}
{{- end -}}


{{/*
  Generate nutcracker config
*/}}
{{- define "twemproxy.nutcrackerConfig" -}}
redis:
  listen: 0.0.0.0:{{ .Values.redisPort }}
  redis: true
{{- with .Values.twemproxy.config }}
{{ toYaml . | indent 2 }}
{{- end }}
  servers:
{{ include "twemproxy.connectionsList" . | indent 2 }}
{{- end -}}

