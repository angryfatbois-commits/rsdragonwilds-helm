{{- define "rsdw.name" -}}
{{- printf "%s-rsdragonwilds" .Release.Name | trunc 54 | trimSuffix "-" -}}
{{- end -}}
{{- define "rsdw.labels" -}}
app.kubernetes.io/name: rsdragonwilds
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
{{- define "rsdw.image" -}}
{{- if .Values.image.digest -}}
{{ .Values.image.repository }}@{{ .Values.image.digest }}
{{- else -}}
{{ .Values.image.repository }}:{{ default .Chart.AppVersion .Values.image.tag }}
{{- end -}}
{{- end -}}
{{- define "rsdw.claim" -}}
{{ default (include "rsdw.name" .) .Values.persistence.existingClaim }}
{{- end -}}
{{- define "rsdw.validate" -}}
{{- $extra := dict -}}
{{- range .Values.server.extraEnv -}}
  {{- if hasKey $extra .name -}}{{ fail (printf "duplicate extraEnv name: %s" .name) }}{{- end -}}
  {{- $_ := set $extra .name . -}}
  {{- if eq (hasKey . "value") (hasKey . "valueFrom") -}}{{ fail "each extraEnv entry requires exactly one of value or valueFrom" }}{{- end -}}
{{- end -}}
{{- $env := mergeOverwrite (deepCopy .Values.server.env) $extra -}}
{{- range $name, $value := $env -}}
  {{- if or (has $name (list "RSDW_PORT" "LD_PRELOAD" "STEAMAPPDIR" "GAMELIFT")) (hasPrefix "RSDWAPI_" $name) -}}
    {{- fail (printf "%s is chart-owned" $name) -}}
  {{- end -}}
{{- end -}}
{{- $owner := get $env "RSDW_OWNER_ID" -}}
{{- if not $owner -}}{{ fail "server.env.RSDW_OWNER_ID or its extraEnv override is required" }}{{- end -}}
{{- if and (kindIs "map" $owner) (hasKey $owner "value") (empty $owner.value) -}}{{ fail "RSDW_OWNER_ID cannot be empty" }}{{- end -}}
{{- if and .Values.api.enabled (empty .Values.api.bearerTokenSecret.name) -}}{{ fail "api.bearerTokenSecret.name is required when API is enabled" }}{{- end -}}
{{- if and .Values.metrics.enabled (not .Values.api.enabled) -}}{{ fail "metrics.enabled requires api.enabled" }}{{- end -}}
{{- if and (not .Values.metrics.enabled) (or .Values.metrics.serviceMonitor.enabled .Values.metrics.networkPolicy.enabled) -}}{{ fail "ServiceMonitor and metrics NetworkPolicy require metrics.enabled" }}{{- end -}}
{{- if and .Values.metrics.enabled (eq (int .Values.api.port) 7979) -}}{{ fail "API port conflicts with exporter port 7979" }}{{- end -}}
{{- if ne (empty .Values.saveSeed.existingClaim) (empty .Values.saveSeed.path) -}}{{ fail "saveSeed requires both existingClaim and path" }}{{- end -}}
{{- if regexMatch "(^|/)\\.\\.(/|$)" .Values.saveSeed.path -}}{{ fail "saveSeed.path cannot contain traversal" }}{{- end -}}
{{- if and .Values.saveSeed.existingClaim (eq .Values.saveSeed.existingClaim (include "rsdw.claim" .)) -}}{{ fail "saveSeed must use a different PVC from the server" }}{{- end -}}
{{- if and .Values.service.nodePort (eq .Values.service.type "ClusterIP") -}}{{ fail "nodePort requires NodePort or LoadBalancer service" }}{{- end -}}
{{- range $key := list "app.kubernetes.io/name" "app.kubernetes.io/instance" -}}
  {{- if hasKey $.Values.podLabels $key -}}{{ fail "podLabels cannot replace selector labels" }}{{- end -}}
{{- end -}}
{{- end -}}
