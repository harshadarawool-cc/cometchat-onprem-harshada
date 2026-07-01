{{/*
_helpers.tpl — reusable template snippets.

Files starting with "_" render NO Kubernetes objects themselves; they only
DEFINE named templates that other files pull in with `include`. Think of these
as functions you call from the real templates.
*/}}

{{/*
The namespace every object lands in. Centralised so we change it in one place.
Usage:  namespace: {{ include "cometchat.namespace" . }}
*/}}
{{- define "cometchat.namespace" -}}
{{- .Values.namespace | default "cometchat" -}}
{{- end -}}

{{/*
Common labels stamped on every object. Helm best-practice labels make `helm
list`, selectors, and `kubectl get -l` behave well.
Usage:
  labels:
    {{- include "cometchat.labels" . | nindent 4 }}
*/}}
{{- define "cometchat.labels" -}}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: cometchat
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{/*
Build a full image reference for a LICENSED image from the central registry.
Pass a dict with the digest (preferred) or tag:
  {{ include "cometchat.image" (dict "root" . "digest" "sha256:abc...") }}
  {{ include "cometchat.image" (dict "root" . "tag" "chat-api") }}
Resolves to: {registry}/{repository}@{digest}  or  {registry}/{repository}:{tag}
*/}}
{{- define "cometchat.image" -}}
{{- $img := .root.Values.image -}}
{{- if .digest -}}
{{ $img.registry }}/{{ $img.repository }}@{{ .digest }}
{{- else -}}
{{ $img.registry }}/{{ $img.repository }}:{{ .tag }}
{{- end -}}
{{- end -}}
