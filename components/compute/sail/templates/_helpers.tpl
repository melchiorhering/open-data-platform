{{/* sail-chart/templates/_helpers.tpl */}}
{{/*
Generate the worker pod template as a dictionary.
This is based on the 'SAIL_KUBERNETES__WORKER_POD_TEMPLATE' env var
in test-volume-patch.yaml.
*/}}
{{- define "sail.workerPodTemplateDict" -}}
{{- $spec := dict "containers" (list (dict "name" "worker")) -}}
{{- if and .Values.hostPaths.enabled .Values.hostPaths.paths -}}
  {{- $volumes := list -}}
  {{- $volumeMounts := list -}}
  {{- range .Values.hostPaths.paths -}}
    {{- $volumes = append $volumes (dict "name" .name "hostPath" (dict "path" .hostPath "type" "DirectoryOrCreate")) -}}
    {{- $volumeMounts = append $volumeMounts (dict "name" .name "mountPath" .mountPath) -}}
  {{- end -}}
  {{- $_ := set $spec "volumes" $volumes -}}
  {{- $_ := set (first $spec.containers) "volumeMounts" $volumeMounts -}}
{{- end -}}
{{- (dict "spec" $spec) | toJson -}}
{{- end -}}