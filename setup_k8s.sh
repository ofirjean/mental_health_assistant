#!/usr/bin/env bash
set -euo pipefail

# Make sure we're in the repo root BEFORE running this script.
echo "PWD: $(pwd)"

# 1) Ensure folder and write manifests (overwrite to keep things consistent)
mkdir -p app/k8s

cat > app/k8s/namespace.yaml <<'YAML'
apiVersion: v1
kind: Namespace
metadata:
  name: mental-health
  labels:
    app.kubernetes.io/name: mental-health
YAML

cat > app/k8s/secret-app.yaml <<'YAML'
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
  namespace: mental-health
type: Opaque
stringData:
  SECRET_KEY: "dev-secret-change-me"
  MONGO_URI: "mongodb://mongo:27017/mental_health_db"
  GEMINI_API_KEY: ""
  GOOGLE_API_KEY: ""
  WTF_CSRF_SECRET_KEY: ""
  PORT: "5000"
  FLASK_DEBUG: "0"
YAML

cat > app/k8s/configmap.yaml <<'YAML'
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: mental-health
  labels:
    app.kubernetes.io/name: mental-health
data:
  GEMINI_MODEL: "gemini-1.5-flash"
YAML

cat > app/k8s/mongo-service.yaml <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: mongo
  namespace: mental-health
  labels:
    app.kubernetes.io/name: mongo
spec:
  ports:
    - name: mongo
      port: 27017
      targetPort: 27017
  selector:
    app.kubernetes.io/name: mongo
YAML

cat > app/k8s/mongo-statefulset.yaml <<'YAML'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mongo
  namespace: mental-health
  labels:
    app.kubernetes.io/name: mongo
spec:
  serviceName: mongo
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: mongo
  template:
    metadata:
      labels:
        app.kubernetes.io/name: mongo
    spec:
      containers:
        - name: mongo
          image: mongo:8.0
          imagePullPolicy: IfNotPresent
          args: ["--bind_ip_all"]
          ports:
            - name: mongo
              containerPort: 27017
          volumeMounts:
            - name: mongo-data
              mountPath: /data/db
          readinessProbe:
            tcpSocket: { port: 27017 }
            initialDelaySeconds: 10
            periodSeconds: 10
          livenessProbe:
            tcpSocket: { port: 27017 }
            initialDelaySeconds: 20
            periodSeconds: 10
  volumeClaimTemplates:
    - metadata:
        name: mongo-data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 2Gi
YAML

cat > app/k8s/app-deployment.yaml <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: flask-app
  namespace: mental-health
  labels:
    app.kubernetes.io/name: flask-app
    app.kubernetes.io/part-of: mental-health
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: flask-app
  template:
    metadata:
      labels:
        app.kubernetes.io/name: flask-app
    spec:
      containers:
        - name: flask-app
          image: ofirjean/mental-health-assistant:latest  # change tag if you have one
          imagePullPolicy: IfNotPresent
          envFrom:
            - secretRef:
                name: app-secrets
            - configMapRef:
                name: app-config
          ports:
            - name: http
              containerPort: 5000
          readinessProbe:
            httpGet: { path: /healthz, port: http }
            initialDelaySeconds: 8
            periodSeconds: 10
          livenessProbe:
            httpGet: { path: /healthz, port: http }
            initialDelaySeconds: 15
            periodSeconds: 10
YAML

cat > app/k8s/app-service.yaml <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: flask-app
  namespace: mental-health
  labels:
    app.kubernetes.io/name: flask-app
spec:
  type: NodePort
  selector:
    app.kubernetes.io/name: flask-app
  ports:
    - name: http
      port: 80
      targetPort: 5000
      nodePort: 30080
YAML

# 2) Namespace (create if missing)
kubectl get ns mental-health >/dev/null 2>&1 || kubectl create ns mental-health

# 3) Secret from your env file if present, else use YAML we wrote
if [ -f ".env" ]; then
  kubectl -n mental-health delete secret app-secrets >/dev/null 2>&1 || true
  kubectl -n mental-health create secret generic app-secrets --from-env-file=.env
elif [ -f "app/.env" ]; then
  kubectl -n mental-health delete secret app-secrets >/dev/null 2>&1 || true
  kubectl -n mental-health create secret generic app-secrets --from-env-file=app/.env
else
  kubectl apply -f app/k8s/secret-app.yaml
fi

# 4) Apply the rest (no unsupported flags)
kubectl apply -f app/k8s/namespace.yaml
kubectl apply -f app/k8s/configmap.yaml
kubectl apply -f app/k8s/mongo-service.yaml
kubectl apply -f app/k8s/mongo-statefulset.yaml
kubectl apply -f app/k8s/app-deployment.yaml
kubectl apply -f app/k8s/app-service.yaml

# 5) Wait for rollouts
kubectl -n mental-health rollout status statefulset/mongo
kubectl -n mental-health rollout status deploy/flask-app

# 6) Quick checks
kubectl -n mental-health get pods,svc
echo "Health:" && curl -sS -i http://localhost:30080/healthz || true
echo "Open: http://localhost:30080"
