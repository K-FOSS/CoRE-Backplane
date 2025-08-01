{{- define "s3-env" -}}
- name: MINIO_DOMAIN
  value: 's3.{{ .Values.cluster.name }}.{{ .Values.datacenter }}.{{ .Values.region }}.{{ .Values.domain }},{{ .Release.Namespace }}.svc.cluster.local,{{ .Release.Namespace }}.svc.{{ .Values.cluster.domain }}'

- name: MINIO_BROWSER
  value: {{ if .Values.admin.dashboard.enabled }}on{{ else }}off{{ end }}

- name: MINIO_BROWSER_REDIRECT_URL
  value: https://{{ .Values.admin.dashboard.domainKey }}.{{ .Values.cluster.name }}.{{ .Values.datacenter }}.{{ .Values.region }}.{{ .Values.domain }}

- name: MINIO_SERVER_URL
  value: https://s3.{{ .Values.cluster.name }}.{{ .Values.datacenter }}.{{ .Values.region }}.{{ .Values.domain }}

#
# High Avail
#
- name: MINIO_STORAGE_CLASS_STANDARD
  value: 'EC:0'

#
# OIDC
#
- name: MINIO_IDENTITY_OPENID_REDIRECT_URI
  value: https://{{ .Values.admin.dashboard.domainKey }}.{{ .Values.cluster.name }}.{{ .Values.datacenter }}.{{ .Values.region }}.{{ .Values.domain }}/oauth_callback

#
# LDAP
#
- name: MINIO_IDENTITY_LDAP_LOOKUP_BIND_DN
  valueFrom:
    secretKeyRef:
      name: {{ .Release.Name }}-sso-user
      key: ldapsBIND

- name: MINIO_IDENTITY_LDAP_LOOKUP_BIND_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Release.Name }}-sso-user
      key: password

- name: MINIO_IDENTITY_LDAP_SERVER_ADDR
  valueFrom:
    secretKeyRef:
      name: {{ .Release.Name }}-sso-user
      key: ldapsURI

#
# Credentials
#
- name: MINIO_ROOT_USER
  valueFrom:
    secretKeyRef:
      name: {{ .Release.Name }}-sso-user
      key: username

- name: MINIO_ROOT_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Release.Name }}-sso-user
      key: password


- name: MINIO_IDENTITY_OPENID_CONFIG_URL
  valueFrom:
    secretKeyRef:
      name: {{ .Release.Name }}-aaa
      key: MINIO_IDENTITY_OPENID_CONFIG_URL

- name: MINIO_IDENTITY_LDAP_USER_DN_SEARCH_BASE_DN
  value: 'ou=users,{{ .Values.ldap.base }}'

- name: MINIO_IDENTITY_LDAP_USER_DN_SEARCH_FILTER
  value: '(&(objectclass=user)(cn=%s))'

- name: MINIO_IDENTITY_LDAP_GROUP_SEARCH_FILTER
  value: '(&(objectclass=group)(member=%s))'

- name: MINIO_IDENTITY_LDAP_GROUP_SEARCH_BASE_DN
  value: 'ou=groups,{{ .Values.ldap.base }}'

- name: MINIO_IDENTITY_LDAP_USER_DN_ATTRIBUTES
  value: 'cn,uid,mail,lastname,name'

- name: MINIO_IDENTITY_OPENID_CLIENT_ID
  valueFrom:
    secretKeyRef:
      name: {{ .Release.Name }}-aaa
      key: OIDC_CLIENT_ID

- name: MINIO_IDENTITY_OPENID_SCOPES
  valueFrom:
    secretKeyRef:
      name: {{ .Release.Name }}-aaa
      key: OIDC_SCOPES

- name: MINIO_IDENTITY_OPENID_CLIENT_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ .Release.Name }}-aaa
      key: OIDC_CLIENT_SECRET
{{- end }}