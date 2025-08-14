#!/bin/bash
# cloudcupcake1.sh - Automates 12-task Kubernetes lab
# Author: CloudCupcake 🍰

set -e

echo "========== CloudCupcake Kubernetes Lab =========="
echo "Current GCP Project: $(gcloud config get-value project)"
PROJECT_ID=$(gcloud config get-value project)

DEFAULT_REGION=$(gcloud config get-value compute/region)
echo "Detected default region: $DEFAULT_REGION"

read -p "Enter zone for Kubernetes cluster (e.g., us-east1-d): " ZONE

if [ -z "$ZONE" ]; then
  echo "Zone cannot be empty. Exiting."
  exit 1
fi

echo "Using Project: $PROJECT_ID | Region: $DEFAULT_REGION | Zone: $ZONE"
echo "================================================="

# Task 1: Create Kubernetes Cluster
echo "========== Task 1: Create Kubernetes Cluster =========="
gcloud container clusters create cloudcupcake-cluster \
  --zone "$ZONE" \
  --num-nodes 3

# Task 2: Get credentials for cluster
echo "========== Task 2: Get credentials for cluster =========="
gcloud container clusters get-credentials cloudcupcake-cluster --zone "$ZONE"

# Task 3: Create deployment
echo "========== Task 3: Create deployment =========="
kubectl create deployment hello-server --image=gcr.io/google-samples/hello-app:1.0

# Task 4: Expose deployment as LoadBalancer
echo "========== Task 4: Expose deployment as LoadBalancer =========="
kubectl expose deployment hello-server \
  --type=LoadBalancer \
  --port 80 \
  --target-port 8080

# Task 5: Scale deployment
echo "========== Task 5: Scale deployment =========="
kubectl scale deployment hello-server --replicas=3

# Task 6: Create namespace
echo "========== Task 6: Create namespace =========="
kubectl create namespace cupcake-ns

# Task 7: Deploy in namespace
echo "========== Task 7: Deploy in namespace =========="
kubectl create deployment cupcake-server \
  --image=gcr.io/google-samples/hello-app:2.0 \
  -n cupcake-ns

# Task 8: Expose namespace deployment
echo "========== Task 8: Expose namespace deployment =========="
kubectl expose deployment cupcake-server \
  --type=NodePort \
  --port 80 \
  --target-port 8080 \
  -n cupcake-ns

# Task 9: Create ConfigMap
echo "========== Task 9: Create ConfigMap =========="
kubectl create configmap app-config --from-literal=APP_COLOR=blue

# Task 10: Create Secret
echo "========== Task 10: Create Secret =========="
kubectl create secret generic db-secret \
  --from-literal=DB_USER=admin \
  --from-literal=DB_PASS=secret123

# Task 11: Enable autoscaling
echo "========== Task 11: Enable autoscaling =========="
kubectl autoscale deployment hello-server \
  --cpu-percent=80 \
  --min=1 \
  --max=5

# Task 12: Rolling update
echo "========== Task 12: Rolling update =========="
kubectl set image deployment hello-server \
  hello-server=gcr.io/google-samples/hello-app:2.0

echo "========== All tasks completed! =========="
echo "🎉 Subscribe to CloudCupcake 🍰 for more labs!"
