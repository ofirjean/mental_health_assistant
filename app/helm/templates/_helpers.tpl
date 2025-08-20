{{- define "mha.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "mha.fullname" -}}
{{ include "mha.name" . }}
{{- end }}
