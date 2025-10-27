#!/bin/bash

set -e

exec > >(sudo tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

# wait until the file is copied
if [ ! -f /tmp/shared/scripts/client.sh ]; then
  echo "Waiting for client.sh to be copied..."
  while [ ! -f /tmp/shared/scripts/client.sh ]; do
    sleep 5
  done
fi

sudo mkdir -p /ops/shared
# sleep for 10s to ensure the file is copied
sleep 10
sudo cp -R /tmp/shared /ops/

sudo bash /ops/shared/scripts/client.sh "${cloud_env}" "${retry_join}" "${consul_version}" "${envoy_version}"

# Install and configure Node Exporter for system monitoring
echo "Installing Node Exporter..."

# Create node_exporter user
sudo useradd --system --no-create-home --shell /bin/false node_exporter

# Download and install Node Exporter
cd /tmp
curl -LO https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
tar -xzf node_exporter-1.7.0.linux-amd64.tar.gz
sudo mv node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/
sudo chown node_exporter:node_exporter /usr/local/bin/node_exporter
rm -rf node_exporter-1.7.0.linux-amd64*

# Create Node Exporter systemd service
sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<EOF
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=node_exporter
Group=node_exporter
ExecStart=/usr/local/bin/node_exporter
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Enable and start Node Exporter
sudo systemctl daemon-reload
sudo systemctl enable node_exporter
sudo systemctl start node_exporter

echo "Node Exporter installation completed"

# wait for consul to start
sleep 10

# Get EC2 metadata token for IMDSv2
TOKEN=$(curl -X PUT "http://instance-data/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

PUBLIC_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://instance-data/latest/meta-data/public-ipv4)
PRIVATE_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://instance-data/latest/meta-data/local-ipv4)
INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://instance-data/latest/meta-data/instance-id)

export CONSUL_HTTP_TOKEN=e95b599e-166e-7d80-08ad-aee76e7ddf19

# Debug application name
# echo "Debug: application_name=${application_name}"

  echo "Setting up mesh gateway for ${CLUSTER_PREFIX}..."
  
  # Wait for consul to be ready
  echo "Waiting for Consul to be ready..."
  for i in {1..20}; do
    if consul members > /dev/null 2>&1; then
      echo "Consul is ready!"
      break
    fi
    echo "Waiting... (attempt $i/20)"
    sleep 10
  done

  # Create proxy defaults configuration for mesh gateway
  sudo tee /tmp/proxy-default.hcl > /dev/null << 'PROXY_EOF'
Kind = "proxy-defaults"
Name = "global"
MeshGateway {
  Mode = "local"
}
PROXY_EOF

  # Create mesh configuration for peering
  sudo tee /tmp/mesh-config.hcl > /dev/null << 'MESH_EOF'
Kind = "mesh"
TransparentProxy {
  MeshDestinationsOnly = true
}
Peering {
  PeerThroughMeshGateways = true
}
MESH_EOF

  # Apply configurations with retries
  echo "Applying Consul configurations..."
  for i in {1..5}; do
    if consul config write /tmp/proxy-default.hcl; then
      echo "✓ Proxy defaults configuration applied"
      break
    else
      echo "⚠ Failed to apply proxy defaults (attempt $i/5), retrying..."
      sleep 5
    fi
  done

  for i in {1..5}; do
    if consul config write /tmp/mesh-config.hcl; then
      echo "✓ Mesh configuration applied"
      break
    else
      echo "⚠ Failed to apply mesh config (attempt $i/5), retrying..."
      sleep 5
    fi
  done

  # Kill any existing envoy processes
  sudo pkill -f envoy || true
  sleep 3

  # Create log file with proper permissions
  sudo touch /var/log/envoy-mgw.log
  sudo chmod 666 /var/log/envoy-mgw.log

  # Start mesh gateway with Envoy and improved error handling
  echo "Starting mesh gateway with Envoy..."
  #TODO register it to background instead of running it once, that way machine restarts will also restart the gateway
  nohup consul connect envoy \
    -gateway mesh \
    -register \
    -service mesh-gateway \
    -address $PRIVATE_IP:8443 \
    -wan-address $PUBLIC_IP:8443 \
    -token "$CONSUL_HTTP_TOKEN" \
    -- --log-level info > /var/log/envoy-mgw.log 2>&1 &

  # Wait for registration
  sleep 15

  # Verify mesh gateway is registered
  echo "Verifying mesh gateway registration..."
  for i in {1..10}; do
    if consul catalog services | grep -q mesh-gateway; then
      echo "✅ Mesh gateway successfully registered!"
      #consul catalog services | grep -q mesh-gateway 
      break
    else
      echo "⚠ Waiting for mesh gateway registration... (attempt $i/10)"
      sleep 10
    fi
  done

  # Final verification
  if ! consul catalog services | grep -q mesh-gateway; then
    echo "❌ Mesh gateway registration failed after multiple attempts"
    echo "Checking logs..."
    tail -20 /var/log/envoy-mgw.log
    exit 1
  fi

  echo "✅ Mesh gateway setup completed for ${CLUSTER_PREFIX}"
