{{/*
cometchat.app — generic Deployment + Service for a STANDARD single-container
licensed service (the NestJS/Node services that take all config from an envFrom
secret). Special services (sidecars, init containers, two containers, exotic
commands) keep their own explicit template files instead of using this.

Call it from the loop in standard-apps.yaml:
  {{ include "cometchat.app" (dict "root" $ "name" $name "svc" $svc) }}

Per-service values it understands (all optional unless noted):
  digest / tag              licensed image ref (one of the two)
  replicas                  default 1
  command                   container command (list)
  env                       inline env (list of {name,value})
  envFromSecret             name of a Secret to envFrom
  port                      containerPort (default 3000); Service maps 80 -> port
  portName                  container port name (default http)
  servicePort               Service port (default 80)
  probe                     { type: http|tcp, path, port, startupFailureThreshold }
  strategy                  Deployment strategy (passthrough)
  podSecurityContext        pod-level securityContext (passthrough)
  containerSecurityContext  container securityContext (passthrough; hardened default)
  extraVolumes / extraVolumeMounts   passthrough lists (e.g. a config secret/configmap)
  resources                 required
*/}}
{{- define "cometchat.app" -}}
{{- $root := .root -}}
{{- $name := .name -}}
{{- $svc := .svc -}}
{{- $port := $svc.port | default 3000 -}}
{{- $probe := $svc.probe | default dict -}}
{{- $ptype := $probe.type | default "tcp" -}}
{{- $pport := $probe.port | default $port -}}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ $name }}
  namespace: {{ include "cometchat.namespace" $root }}
  labels:
    app.kubernetes.io/name: {{ $name }}
    {{- include "cometchat.labels" $root | nindent 4 }}
spec:
  replicas: {{ $svc.replicas | default 1 }}
  {{- with $svc.strategy }}
  strategy:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  selector:
    matchLabels:
      app.kubernetes.io/name: {{ $name }}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: {{ $name }}
        {{- include "cometchat.labels" $root | nindent 8 }}
    spec:
      imagePullSecrets:
        - name: {{ $root.Values.image.pullSecret }}
      {{- with $svc.podSecurityContext }}
      securityContext:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      containers:
        - name: {{ $name }}
          image: {{ include "cometchat.image" (dict "root" $root "digest" $svc.digest "tag" $svc.tag) }}
          imagePullPolicy: {{ $root.Values.image.pullPolicy }}
          {{- with $svc.command }}
          command:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with $svc.env }}
          env:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with $svc.envFromSecret }}
          envFrom:
            - secretRef: { name: {{ . }} }
          {{- end }}
          ports:
            - { containerPort: {{ $port }}, name: {{ $svc.portName | default "http" }} }
          {{- with $svc.extraVolumeMounts }}
          volumeMounts:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          startupProbe:
            {{- if eq $ptype "http" }}
            httpGet: { path: {{ $probe.path }}, port: {{ $pport }} }
            {{- else }}
            tcpSocket: { port: {{ $pport }} }
            {{- end }}
            periodSeconds: 10
            failureThreshold: {{ $probe.startupFailureThreshold | default 30 }}
          readinessProbe:
            {{- if eq $ptype "http" }}
            httpGet: { path: {{ $probe.path }}, port: {{ $pport }} }
            {{- else }}
            tcpSocket: { port: {{ $pport }} }
            {{- end }}
            periodSeconds: 10
          resources:
            {{- toYaml $svc.resources | nindent 12 }}
          {{- with $svc.containerSecurityContext }}
          securityContext:
            {{- toYaml . | nindent 12 }}
          {{- else }}
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
          {{- end }}
      {{- with $svc.extraVolumes }}
      volumes:
        {{- toYaml . | nindent 8 }}
      {{- end }}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ $name }}
  namespace: {{ include "cometchat.namespace" $root }}
  labels:
    app.kubernetes.io/name: {{ $name }}
    {{- include "cometchat.labels" $root | nindent 4 }}
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: {{ $name }}
  ports:
    - { name: {{ $svc.portName | default "http" }}, port: {{ $svc.servicePort | default 80 }}, targetPort: {{ $port }} }
{{- end -}}
