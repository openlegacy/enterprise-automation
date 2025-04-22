{{/*
Expand the name of the chart.
*/}}
{{- define "hub-enterprise.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "hub-enterprise.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "hub-enterprise.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "hub-enterprise.labels" -}}
helm.sh/chart: {{ include "hub-enterprise.chart" . }}
{{ include "hub-enterprise.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "hub-enterprise.selectorLabels" -}}
app.kubernetes.io/name: {{ include "hub-enterprise.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "hub-enterprise.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "hub-enterprise.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Custom variables
*/}}

{{- define "hub-enterprise.hubIamUrl" -}}
  {{ printf "%s%s%s%s" "https://" (include "hub-enterprise.fullname" .) "-keycloak" "/auth/realms/ol-hub" | b64enc }}
{{- end }}

{{- define "hub-enterprise.backofficeIamUrl" -}}
  {{ printf "%s%s%s%s" "https://" (include "hub-enterprise.fullname" .) "-keycloak" "/auth/realms/ol-hub" | b64enc }}
{{- end }}

{{- define "hub-enterprise.keycloakBaseURL" -}}
  {{ printf "%s%s%s" "https://" (include "hub-enterprise.fullname" .) "-keycloak" | b64enc }}
{{- end }}

{{- define "hub-enterprise.keycloakURL" -}}
  {{ printf "%s%s" "https://" (.Values.keycloak.hostname) | b64enc }}
{{- end }}

{{- define "hub-enterprise.hubURL" -}}
  {{ printf "%s%s" "https://" (.Values.hubEnterprise.hostname) | b64enc }}
{{- end }}
