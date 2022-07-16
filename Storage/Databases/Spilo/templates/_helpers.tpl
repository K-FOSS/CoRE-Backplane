{{/* vim: set filetype=gohtmltmpl: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "spilo.name" -}}
{{- default "spilo" .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "spilo.clusterName" -}}
{{- default "spilo-cluster0" .Values.clusterName -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "spilo.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default "spilo" .Values.nameOverride -}}
{{- if or (eq $name .Release.Name) (eq (.Release.Name | upper) "RELEASE-NAME") -}}
{{- $name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}