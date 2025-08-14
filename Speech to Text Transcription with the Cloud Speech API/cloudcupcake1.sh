#!/bin/bash
set -e  # Exit if any command fails

# ====== CONFIG ======
ZONE=$(gcloud config get-value compute/zone)
PROJECT_ID=$(gcloud config get-value project)
GITHUB_EMAIL="your-email@example.com"  # CHANGE to your GitHub email
APP_NAME="gceme"
CLUSTER="jenkins-cd"

echo "==== Setting Zone ===="
gcloud config set compute/zone $ZONE

# ====== Task 1: Download Source Code ======
echo "==== Downloading Lab Source Code ===="
gsutil cp gs://spls/gsp051/continuous-deployment-on-kubernetes.zip .
unzip -q continuous-deployment-on-kubernetes.zip
cd continuous-deployment-on-kubernetes

# ====== Task 2: Provision Jenkins ======
echo "==== Creating Kubernetes Cluster ===="
gcloud container clusters create $CLUSTER \
  --num-nodes 2 \
  --machine-type e2-standard-2 \
  --scopes "https://www.googleapis.com/auth/source.read_write,cloud-platform"

gcloud container clusters get-credentials $CLUSTER
kubectl cluster-info

# ====== Task 3: Set up Helm ======
echo "==== Setting up Helm ===="
helm repo add jenkins https://charts.jenkins.io
helm repo update

# ====== Task 4: Install Jenkins ======
echo "==== Installing Jenkins via Helm ===="
helm install cd jenkins/jenkins -f jenkins/values.yaml --wait

kubectl create clusterrolebinding jenkins-deploy \
  --clusterrole=cluster-admin \
  --serviceaccount=default:cd-jenkins

POD_NAME=$(kubectl get pods -l "app.kubernetes.io/component=jenkins-master" -o jsonpath="{.items[0].metadata.name}")
kubectl port-forward $POD_NAME 8080:8080 >> /dev/null &

ADMIN_PASS=$(kubectl get secret cd-jenkins -o jsonpath="{.data.jenkins-admin-password}" | base64 --decode)
echo "==== Jenkins Admin Password ===="
echo "$ADMIN_PASS"

# ====== Task 6-7: Deploy Sample App ======
echo "==== Deploying Sample App to Production and Canary ===="
cd sample-app
kubectl create ns production
kubectl apply -f k8s/production -n production
kubectl apply -f k8s/canary -n production
kubectl apply -f k8s/services -n production
kubectl scale deployment gceme-frontend-production -n production --replicas 4

FRONTEND_SERVICE_IP=""
while [ -z "$FRONTEND_SERVICE_IP" ]; do
  FRONTEND_SERVICE_IP=$(kubectl get svc gceme-frontend -n production -o jsonpath="{.status.loadBalancer.ingress[0].ip}" 2>/dev/null || true)
  [ -z "$FRONTEND_SERVICE_IP" ] && echo "Waiting for LoadBalancer IP..." && sleep 10
done
echo "Production Service IP: $FRONTEND_SERVICE_IP"
curl http://$FRONTEND_SERVICE_IP/version

# ====== Task 8-9: GitHub Setup for Jenkins ======
echo "==== Setting up GitHub Repo ===="
curl -sS https://webi.sh/gh | sh
gh auth login --web
GITHUB_USERNAME=$(gh api user -q ".login")
git config --global user.name "$GITHUB_USERNAME"
git config --global user.email "$GITHUB_EMAIL"
gh repo create default --private --confirm

git init
git remote add origin https://github.com/${GITHUB_USERNAME}/default
git add .
git commit -m "Initial commit"
git push origin master

# ====== Create SSH Key for GitHub Access ======
echo "==== Creating SSH Key for GitHub ===="
ssh-keygen -t rsa -b 4096 -N '' -f id_github -C "$GITHUB_EMAIL"
gh ssh-key add id_github.pub --title "SSH_KEY_LAB"

ssh-keyscan -t rsa github.com > known_hosts.github

# ====== Modify Jenkinsfile ======
echo "==== Modifying Jenkinsfile ===="
sed -i "s/REPLACE_WITH_YOUR_PROJECT_ID/$PROJECT_ID/" Jenkinsfile
sed -i "s/CLUSTER_ZONE = \"\"/CLUSTER_ZONE = \"$ZONE\"/" Jenkinsfile

# ====== Task 9-10: Development Branch ======
git checkout -b new-feature
sed -i 's/card blue/card orange/g' html.go
sed -i 's/1.0.0/2.0.0/' main.go
git add Jenkinsfile html.go main.go
git commit -m "Version 2.0.0"
git push origin new-feature

# ====== Task 11: Canary Release ======
git checkout -b canary
git push origin canary

# ====== Task 12: Deploy to Production ======
git checkout master
git merge canary
git push origin master

echo "==== Waiting for Production to Update ===="
while true; do
  curl http://$FRONTEND_SERVICE_IP/version
  sleep 2
done
