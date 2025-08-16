#!/bin/bash

# Prompt user to enter zones
read -p "Enter ZONE1 (US client & server): " ZONE1
read -p "Enter ZONE2 (Europe client & server): " ZONE2
read -p "Enter ZONE3 (Asia client): " ZONE3

# 1. Enable APIs
gcloud services enable compute.googleapis.com
gcloud services enable dns.googleapis.com

# 2. Create Firewall Rules
gcloud compute firewall-rules create fw-default-iapproxy \
--direction=INGRESS \
--priority=1000 \
--network=default \
--action=ALLOW \
--rules=tcp:22,icmp \
--source-ranges=35.235.240.0/20

gcloud compute firewall-rules create allow-http-traffic \
--direction=INGRESS \
--priority=1000 \
--network=default \
--action=ALLOW \
--rules=tcp:80 \
--source-ranges=0.0.0.0/0 \
--target-tags=http-server

# 3. Launch Client VMs
gcloud compute instances create us-client-vm --machine-type=e2-micro --zone $ZONE1
gcloud compute instances create europe-client-vm --machine-type=e2-micro --zone $ZONE2
gcloud compute instances create asia-client-vm --machine-type=e2-micro --zone $ZONE3

# 4. Launch Server VMs with startup script
gcloud compute instances create us-web-vm \
--zone=$ZONE1 \
--machine-type=e2-micro \
--network=default \
--subnet=default \
--tags=http-server \
--metadata=startup-script='#! /bin/bash
apt-get update
apt-get install apache2 -y
echo "Page served from: REGION1" | tee /var/www/html/index.html
systemctl restart apache2'

gcloud compute instances create europe-web-vm \
--zone=$ZONE2 \
--machine-type=e2-micro \
--network=default \
--subnet=default \
--tags=http-server \
--metadata=startup-script='#! /bin/bash
apt-get update
apt-get install apache2 -y
echo "Page served from: REGION2" | tee /var/www/html/index.html
systemctl restart apache2'

# 5. Get Internal IPs
export US_WEB_IP=$(gcloud compute instances describe us-web-vm --zone=$ZONE1 --format="value(networkInterfaces.networkIP)")
export EUROPE_WEB_IP=$(gcloud compute instances describe europe-web-vm --zone=$ZONE2 --format="value(networkInterfaces.networkIP)")

# 6. Create private DNS zone
gcloud dns managed-zones create example \
--description=test \
--dns-name=example.com \
--networks=default \
--visibility=private

# 7. Create DNS Geolocation routing policy
gcloud dns record-sets create geo.example.com \
--ttl=5 --type=A --zone=example \
--routing-policy-type=GEO \
--routing-policy-data="REGION1=$US_WEB_IP;REGION2=$EUROPE_WEB_IP"

echo "Lab setup complete!"
