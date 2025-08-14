#!/usr/bin/env bash
# cloudcupcake1.sh — Continuous Deployment on Kubernetes (12 tasks)
# Works around SSD quota by forcing pd-standard disks.

set -Eeuo pipefail

log() { echo -e "\n\033[1m[$(date +%H:%M:%S)] $*\033[0m"; }

# --- Detect project and prompt for zone ---
PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"
if [[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "(unset)" ]]; then
  read -rp "Enter your GCP Project ID: " PROJECT_ID
  gcloud config set project "$PROJECT_ID"
fi
log "Using Project: $PROJECT_ID"

read -rp "Enter GKE zone (default: us-east1-d): " ZONE
ZONE="${ZONE:-us-east1-d}"
gcloud config set compute/zone "$ZONE" >/dev/null

# Derive region from zone (e.g. us-east1-d -> us-east1)
REGION="${ZONE%-*}"
gcloud config set compute/region "$REGION" >/dev/null
log "Region: $REGION | Zone: $ZONE"

# --- Enable required APIs ---
log "Enabling required APIs (may be already enabled)"
gcloud services enable \
  container.googleapis.com \
  containerregistry.googleapis.com \
  cloudbuild.googleapis.com \
  sourcerepo.googleapis.com >/dev/null

# ========== Task 1. Download the source code ==========
log "Task 1: Downloading lab source code"
gsutil cp gs://spls/gsp051/continuous-deployment-on-kubernetes.zip ./
unzip -qo continuous-deployment-on-kubernetes.zip
cd continuous-deployment-on-kubernetes

# ========== Task 2. Provision Jenkins ==========
log "Task 2: Creating GKE cluster 'jenkins-cd' (pd-standard to avoid SSD quota)"
gcloud container clusters create jenkins-cd \
  --zone "$ZONE" \
  --num-nodes 2 \
  --machine-type e2-standard-2 \
  --disk-type pd-standard \
  --disk-size 30 \
  --scopes "https://www.googleapis.com/auth/source.read_write,cloud-platform"

log "Getting credentials and verifying cluster"
gcloud container clusters get-credentials jenkins-cd --zone "$ZONE"
kubectl cluster-info

# ========== Task 3. Set up Helm ==========
log "Task 3: Adding Helm repo"
helm repo add jenkins https://charts.jenkins.io
helm repo update

# ========== Task 4. Install and configure Jenkins ==========
log "Task 4: Installing Jenkins Helm chart (with provided values.yaml)"
helm install cd jenkins/jenkins -f jenkins/values.yaml --wait

log "Granting Jenkins service account cluster-admin to deploy"
kubectl create clusterrolebinding jenkins-deploy \
  --clusterrole=cluster-admin \
  --serviceaccount=default:cd-jenkins \
  --dry-run=none >/dev/null 2>&1 || true

# Port-forward Jenkins (background)
POD_NAME=$(kubectl get pods \
  -l "app.kubernetes.io/component=jenkins-master,app.kubernetes.io/instance=cd" \
  -o jsonpath="{.items[0].metadata.name}")
log "Port-forwarding Jenkins UI to localhost:8080"
kubectl port-forward "$POD_NAME" 8080:8080 >/dev/null 2>&1 &

# Print admin password for convenience
ADMIN_PASS=$(kubectl get secret cd-jenkins -o jsonpath="{.data.jenkins-admin-password}" | base64 --decode)
log "Jenkins admin password (username: admin): $ADMIN_PASS"

kubectl get svc

# ========== Task 6 & 7. Understand + Deploy the application ==========
log "Task 7: Deploying gceme app (production + canary) and services"
cd sample-app
kubectl create ns production || true
kubectl apply -f k8s/production -n production
kubectl apply -f k8s/canary -n production
kubectl apply -f k8s/services -n production
kubectl scale deployment gceme-frontend-production -n production --replicas 4

# Wait for LoadBalancer external IP
log "Waiting for gceme-frontend LoadBalancer IP..."
for i in {1..40}; do
  FRONTEND_SERVICE_IP=$(kubectl get svc gceme-frontend -n production \
    -o jsonpath="{.status.loadBalancer.ingress[0].ip}" 2>/dev/null || true)
  [[ -n "${FRONTEND_SERVICE_IP}" ]] && break
  sleep 10
done
if [[ -z "${FRONTEND_SERVICE_IP}" ]]; then
  log "WARNING: External IP not ready yet. Continuing..."
else
  log "gceme-frontend external IP: $FRONTEND_SERVICE_IP"
  log "Checking version endpoint (expect 1.0.0)..."
  curl -sf "http://${FRONTEND_SERVICE_IP}/version" || true
fi

# ========== Task 8. Create the Jenkins pipeline ==========
log "Task 8: GitHub CLI setup"
# Install gh if needed
if ! command -v gh >/dev/null 2>&1; then
  curl -sS https://webi.sh/gh | sh
  export PATH="$HOME/.local/bin:$PATH"
fi

# Auth (interactive once)
if ! gh auth status >/dev/null 2>&1; then
  log "GitHub auth required. A browser window / URL will be provided."
  gh auth login
fi

GITHUB_USERNAME=$(gh api user -q ".login")
log "GitHub user: ${GITHUB_USERNAME}"

# Configure git user.name / user.email
if ! git config --global user.name >/dev/null; then
  git config --global user.name "${GITHUB_USERNAME}"
fi
if ! git config --global user.email >/dev/null; then
  read -rp "Enter your GitHub email (for git commits): " USER_EMAIL
  git config --global user.email "${USER_EMAIL}"
fi

# Initialize repo and push
log "Creating private repo 'default' (ignore warnings if exists)"
gh repo create default --private --confirm || true
git init
git config credential.helper gcloud.sh || true
git remote remove origin >/dev/null 2>&1 || true
git remote add origin "https://github.com/${GITHUB_USERNAME}/default"
git add .
git commit -m "Initial commit" || true
git branch -M master
git push -u origin master || true

# SSH key for Jenkins -> GitHub
log "Generating SSH key for Jenkins to access GitHub"
[[ -f id_github ]] || ssh-keygen -t rsa -b 4096 -N '' -f id_github -C "$(git config --global user.email)"
gh ssh-key add id_github.pub --title "SSH_KEY_LAB" --read-only=false || true

# Known hosts for GitHub
log "Writing known hosts for github.com"
ssh-keyscan -t rsa github.com > known_hosts.github
chmod 644 known_hosts.github
log "IMPORTANT (Jenkins UI): Set Git Host Key Verification to 'Manually provided keys' and paste contents of known_hosts.github."

# ========== Task 9. Create the development environment ==========
log "Task 9: Updating Jenkinsfile for project/zone & modifying app (orange, v2.0.0)"
# Update Jenkinsfile
PROJECT_SAFE="$PROJECT_ID"
ZONE_SAFE="$ZONE"
sed -i "s/REPLACE_WITH_YOUR_PROJECT_ID/${PROJECT_SAFE}/" Jenkinsfile
# Force CLUSTER_ZONE line to our zone
if grep -q '^CLUSTER_ZONE' Jenkinsfile; then
  sed -i "s/^CLUSTER_ZONE.*/CLUSTER_ZONE = \"${ZONE_SAFE}\"/" Jenkinsfile
else
  echo "CLUSTER_ZONE = \"${ZONE_SAFE}\"" >> Jenkinsfile
fi

# Modify site color and version
sed -i 's/class="card blue"/class="card orange"/g' html.go
sed -i 's/const version string = "1.0.0"/const version string = "2.0.0"/' main.go

git checkout -B new-feature
git add Jenkinsfile html.go main.go
git commit -m "Version 2.0.0 (orange card, Jenkinsfile project/zone)"
git push -u origin new-feature

log "Start kubectl proxy in background for dev checks"
kubectl proxy >/dev/null 2>&1 &

log "You can verify when Jenkins builds the 'new-feature' branch."
log "Once deployed, expect: curl http://localhost:8001/api/v1/namespaces/new-feature/services/gceme-frontend:80/proxy/version"

# ========== Task 11. Deploy a canary release ==========
log "Task 11: Creating 'canary' branch and pushing"
git checkout -B canary
git push -u origin canary

log "When Jenkins finishes canary, ~20% traffic should return 2.0.0:"
log "   export FRONTEND_SERVICE_IP=\$(kubectl get -o jsonpath='{.status.loadBalancer.ingress[0].ip}' --namespace=production services gceme-frontend)"
log "   while true; do curl http://\$FRONTEND_SERVICE_IP/version; sleep 1; done"

# ========== Task 12. Deploy to production ==========
log "Task 12: Merging 'canary' -> 'master' and pushing"
git checkout master
git merge --no-edit canary || true
git push origin master

log "After Jenkins master pipeline, all traffic should return 2.0.0:"
log "   export FRONTEND_SERVICE_IP=\$(kubectl get -o jsonpath='{.status.loadBalancer.ingress[0].ip}' --namespace=production services gceme-frontend)"
log "   while true; do curl http://\$FRONTEND_SERVICE_IP/version; sleep 1; done"

log "DONE. Notes:"
echo "- Jenkins UI is accessible via Cloud Shell Web Preview on port 8080."
echo "- Username: admin"
echo "- Password: ${ADMIN_PASS}"
echo "- For credentials and host key verification steps, follow the lab UI instructions."
