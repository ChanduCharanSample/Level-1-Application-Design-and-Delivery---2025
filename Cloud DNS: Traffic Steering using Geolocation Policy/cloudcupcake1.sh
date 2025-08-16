#!/bin/bash

# ---- SET ZONE ----
ZONE="example"

# ---- FETCH INTERNAL IPs (update with your VM names + zones) ----
US_WEB_IP=$(gcloud compute instances describe us-web-vm --zone=us-central1-a --format='get(networkInterfaces[0].networkIP)')
EUROPE_WEB_IP=$(gcloud compute instances describe europe-web-vm --zone=europe-west1-b --format='get(networkInterfaces[0].networkIP)')

# Fallback if instances are not found
if [[ -z "$US_WEB_IP" || -z "$EUROPE_WEB_IP" ]]; then
  echo "❌ Could not fetch VM IPs. Please check VM names and zones."
  exit 1
fi

echo "✅ US Web VM IP: $US_WEB_IP"
echo "✅ Europe Web VM IP: $EUROPE_WEB_IP"

# ---- DELETE OLD GEO RECORD IF EXISTS ----
gcloud dns record-sets delete geo.example.com. \
  --type=A \
  --zone=$ZONE \
  --quiet || echo "ℹ️ No old record to delete."

# ---- CREATE GEO RECORD with NEW SYNTAX ----
gcloud dns record-sets create geo.example.com. \
  --ttl=5 \
  --type=A \
  --zone=$ZONE \
  --routing-policy-type=GEO \
  --routing-policy-item=location=us-central1,rrdatas=$US_WEB_IP \
  --routing-policy-item=location=europe-west1,rrdatas=$EUROPE_WEB_IP

# ---- VERIFY ----
gcloud dns record-sets list --zone=$ZONE
