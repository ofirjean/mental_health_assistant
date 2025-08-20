#!/usr/bin/env bash
set -euo pipefail

# 0) Go to repo root (adjust if you moved the folder)
cd "/mnt/c/Users/Asus/Documents/SELA/Projectos/mental_health_assistant"

echo "==> Current context:"
kubectl config current-context

echo "==> Ensure namespace exists..."
kubectl get ns mental-health >/dev/null 2>&1 || kubectl create ns mental-health

echo "==> Create/refresh Secret from your .env..."
if [ -f ".env" ]; then
  kubectl -n mental-health delete secret app-secrets >/dev/null 2>&1 || true
  kubectl -n mental-health create secret generic app-secrets --from-env-file=.env
elif [ -f "app/.env" ]; then
  kubectl -n mental-health delete secret app-secrets >/dev/null 2>&1 || true
  kubectl -n mental-health create secret generic app-secrets --from-env-file=app/.env
else
  echo "No .env found. Creating a minimal Secret (edit later if needed)..."
  kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
  namespace: mental-health
type: Opaque
stringData:
  SECRET_KEY: "dev-secret-change-me"
  MONGO_URI: "mongodb://mongo:27017/mental_health_db"
  PORT: "5000"
  FLASK_DEBUG: "0"
YAML
fi

echo "==> Apply manifests (skip missing files without failing)..."
# If some files don’t exist, --ignore-not-found avoids stopping the run.
kubectl apply -f app/k8s/namespace.yaml --ignore-not-found=true
kubectl apply -f app/k8s/configmap.yaml --ignore-not-found=true
kubectl apply -f app/k8s/mongo-service.yaml --ignore-not-found=true
kubectl apply -f app/k8s/mongo-statefulset.yaml --ignore-not-found=true
kubectl apply -f app/k8s/app-deployment.yaml --ignore-not-found=true
kubectl apply -f app/k8s/app-service.yaml --ignore-not-found=true

echo "==> Wait for Mongo..."
kubectl -n mental-health rollout status statefulset/mongo

echo "==> Wait for Flask app..."
kubectl -n mental-health rollout status deploy/flask-app

echo "==> Listing resources:"
kubectl -n mental-health get pods,svc

echo "==> Health check:"
curl -i http://localhost:30080/healthz || true

echo "==> Open app at: http://localhost:30080"
