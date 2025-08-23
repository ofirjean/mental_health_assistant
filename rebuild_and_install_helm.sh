#!/usr/bin/env bash
set -euo pipefail

NS="mental-health"
RELEASE="app"
CHART_DIR="app/helm"
IMAGE_REPO="${IMAGE_REPO:-ofirjean/mental-health-assistant}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

echo "==> Rebuilding chart at $CHART_DIR (clean labels, no 'mha')..."
rm -rf "$CHART_DIR"
mkdir -p "$CHART_DIR/templates"

# Chart.yaml
cat > "$CHART_DIR/Chart.yaml" <<'YAML'
apiVersion: v2
name: mental-health-app
description: Flask + Mongo app for local K8s via Helm
type: application
version: 0.1.0
appVersion: "0.1.0"
YAML

# values.yaml
cat > "$CHART_DIR/values.yaml" <<EOF
image:
  repository: ${IMAGE_REPO}
  tag: ${IMAGE_TAG}
  pullPolicy: IfNotPresent

service:
  type: NodePort
  port: 80
  targetPort: 5000
  nodePort: 30080

env:
  GEMINI_MODEL: "gemini-1.5-flash"

secret:
  SECRET_KEY: "dev-secret-change-me"
  MONGO_URI: "mongodb://mongo:27017/mental_health_db"
  GEMINI_API_KEY: ""
  GOOGLE_API_KEY: ""
  WTF_CSRF_SECRET_KEY: ""
  PORT: "5000"
  FLASK_DEBUG: "0"

mongo:
  image: "mongo:8.0"
  servicePort: 27017
  storage: "2Gi"

sanityTest:
  enabled: true
  image: curlimages/curl:8.10.0
EOF

# _helpers.tpl (only common labels; no name/instance here)
cat > "$CHART_DIR/templates/_helpers.tpl" <<'TPL'
{{- define "app.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" -}}
{{- end -}}

{{- define "app.commonLabels" -}}
helm.sh/chart: {{ include "app.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Chart.AppVersion }}
app.kubernetes.io/version: {{ . | quote }}
{{- end }}
{{- end -}}
TPL

# Secret
cat > "$CHART_DIR/templates/secret.yaml" <<'YAML'
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
  namespace: {{ .Release.Namespace }}
type: Opaque
stringData:
  SECRET_KEY: {{ .Values.secret.SECRET_KEY | quote }}
  MONGO_URI: {{ .Values.secret.MONGO_URI | quote }}
  GEMINI_API_KEY: {{ .Values.secret.GEMINI_API_KEY | quote }}
  GOOGLE_API_KEY: {{ .Values.secret.GOOGLE_API_KEY | quote }}
  WTF_CSRF_SECRET_KEY: {{ .Values.secret.WTF_CSRF_SECRET_KEY | quote }}
  PORT: {{ .Values.secret.PORT | quote }}
  FLASK_DEBUG: {{ .Values.secret.FLASK_DEBUG | quote }}
YAML

# ConfigMap
cat > "$CHART_DIR/templates/configmap.yaml" <<'YAML'
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "app.commonLabels" . | nindent 4 }}
data:
  GEMINI_MODEL: {{ .Values.env.GEMINI_MODEL | quote }}
YAML

# Flask Deployment
cat > "$CHART_DIR/templates/deployment.yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: flask-app
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "app.commonLabels" . | nindent 4 }}
    app.kubernetes.io/name: flask-app
    app.kubernetes.io/instance: {{ .Release.Name }}
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: flask-app
      app.kubernetes.io/instance: {{ .Release.Name }}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: flask-app
        app.kubernetes.io/instance: {{ .Release.Name }}
        {{- include "app.commonLabels" . | nindent 8 }}
    spec:
      containers:
        - name: flask-app
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          envFrom:
            - secretRef: { name: app-secrets }
            - configMapRef: { name: app-config }
          ports:
            - name: http
              containerPort: {{ .Values.service.targetPort }}
          readinessProbe:
            httpGet: { path: /healthz, port: http }
            initialDelaySeconds: 8
            periodSeconds: 10
          livenessProbe:
            httpGet: { path: /healthz, port: http }
            initialDelaySeconds: 15
            periodSeconds: 10
YAML

# Flask Service
cat > "$CHART_DIR/templates/service.yaml" <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: flask-app
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "app.commonLabels" . | nindent 4 }}
    app.kubernetes.io/name: flask-app
    app.kubernetes.io/instance: {{ .Release.Name }}
spec:
  type: {{ .Values.service.type }}
  selector:
    app.kubernetes.io/name: flask-app
    app.kubernetes.io/instance: {{ .Release.Name }}
  ports:
    - name: http
      port: {{ .Values.service.port }}
      targetPort: {{ .Values.service.targetPort }}
      {{- if eq .Values.service.type "NodePort" }}
      nodePort: {{ .Values.service.nodePort }}
      {{- end }}
YAML

# Mongo Service
cat > "$CHART_DIR/templates/mongo-service.yaml" <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: mongo
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "app.commonLabels" . | nindent 4 }}
    app.kubernetes.io/name: mongo
    app.kubernetes.io/instance: {{ .Release.Name }}
spec:
  ports:
    - name: mongo
      port: {{ .Values.mongo.servicePort }}
      targetPort: {{ .Values.mongo.servicePort }}
  selector:
    app.kubernetes.io/name: mongo
    app.kubernetes.io/instance: {{ .Release.Name }}
YAML

# Mongo StatefulSet
cat > "$CHART_DIR/templates/mongo-statefulset.yaml" <<'YAML'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mongo
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "app.commonLabels" . | nindent 4 }}
    app.kubernetes.io/name: mongo
    app.kubernetes.io/instance: {{ .Release.Name }}
spec:
  serviceName: mongo
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: mongo
      app.kubernetes.io/instance: {{ .Release.Name }}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: mongo
        app.kubernetes.io/instance: {{ .Release.Name }}
        {{- include "app.commonLabels" . | nindent 8 }}
    spec:
      containers:
        - name: mongo
          image: {{ .Values.mongo.image }}
          imagePullPolicy: IfNotPresent
          args: ["--bind_ip_all"]
          ports:
            - name: mongo
              containerPort: {{ .Values.mongo.servicePort }}
          volumeMounts:
            - name: mongo-data
              mountPath: /data/db
          readinessProbe:
            tcpSocket: { port: {{ .Values.mongo.servicePort }} }
            initialDelaySeconds: 10
            periodSeconds: 10
          livenessProbe:
            tcpSocket: { port: {{ .Values.mongo.servicePort }} }
            initialDelaySeconds: 20
            periodSeconds: 10
  volumeClaimTemplates:
    - metadata:
        name: mongo-data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: {{ .Values.mongo.storage }}
YAML

# Helm test (optional)
cat > "$CHART_DIR/templates/test-connection.yaml" <<'YAML'
{{- if .Values.sanityTest.enabled }}
apiVersion: v1
kind: Pod
metadata:
  name: {{ .Release.Name }}-test-connection
  namespace: {{ .Release.Namespace }}
  annotations:
    "helm.sh/hook": test
spec:
  restartPolicy: Never
  containers:
    - name: curl
      image: {{ .Values.sanityTest.image }}
      args: ["-fsS", "http://flask-app/healthz"]
{{- end }}
YAML

echo "==> Linting chart..."
helm lint "$CHART_DIR"

echo "==> Preparing secret overrides from .env (if present)..."
SECRET_ARGS=()
if [ -f ".env" ]; then FILE=".env"; elif [ -f "app/.env" ]; then FILE="app/.env"; else FILE=""; fi
if [ -n "${FILE}" ]; then
  for key in SECRET_KEY MONGO_URI GEMINI_API_KEY GOOGLE_API_KEY WTF_CSRF_SECRET_KEY PORT FLASK_DEBUG; do
    if grep -qE "^${key}=" "$FILE"; then
      val="$(grep -E "^${key}=" "$FILE" | head -n1 | cut -d= -f2-)"
      SECRET_ARGS+=( --set-string "secret.${key}=${val}" )
    fi
  done
fi

echo "==> Removing kubectl-managed copies (PVC/data kept)..."
kubectl -n "$NS" delete deploy/flask-app svc/flask-app statefulset/mongo svc/mongo configmap/app-config secret/app-secrets --ignore-not-found=true

echo "==> helm upgrade --install (release: $RELEASE, ns: $NS)..."
helm upgrade --install "$RELEASE" "$CHART_DIR" -n "$NS" --create-namespace "${SECRET_ARGS[@]}"

echo "==> Waiting for rollout..."
kubectl -n "$NS" rollout status statefulset/mongo
kubectl -n "$NS" rollout status deploy/flask-app

echo "==> Checking service..."
kubectl -n "$NS" get pods,svc
NODEPORT=$(kubectl -n "$NS" get svc flask-app -o jsonpath='{.spec.ports[0].nodePort}')
echo "Open: http://localhost:${NODEPORT}"
curl -i "http://localhost:${NODEPORT}/healthz" || true

echo "==> (Optional) Run Helm test:"
echo "helm test $RELEASE -n $NS"
