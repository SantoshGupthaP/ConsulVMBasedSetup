#!/bin/bash

set +e

exec > >(sudo tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

#sudo apt update && sudo apt install -y unzip
#curl -LO https://github.com/hashi-stack/minion-chat-advance-resources/archive/refs/heads/main.zip
#unzip main.zip -d /tmp
#sudo cp -R /tmp/minion-chat-advance-resources-main/4-consul-service-mesh-mgw-muti-dc/shared /ops/shared/

# wait until the file is copied
if [ ! -f /tmp/shared/scripts/server.sh ]; then
  echo "Waiting for server.sh to be copied..."
  while [ ! -f /tmp/shared/scripts/server.sh ]; do
    sleep 5
  done
fi
sleep 10
sudo mkdir -p /ops/shared && sudo chmod a+rwx /ops/shared
sudo cp -R /tmp/shared /ops/

set -e

sudo bash /ops/shared/scripts/server.sh "${cloud_env}" "${server_count}" "${retry_join}" "${consul_version}" "${envoy_version}"


CLOUD_ENV="${cloud_env}"

sed -i "s/RETRY_JOIN/${retry_join}/g" /etc/consul.d/consul.hcl

# for aws only
TOKEN=$(curl -X PUT "http://instance-data/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
PRIVATE_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://instance-data/latest/meta-data/local-ipv4)
sed -i "s/IP_ADDRESS/$PRIVATE_IP/g" /etc/consul.d/consul.hcl
sed -i "s/SERVER_COUNT/${server_count}/g" /etc/consul.d/consul.hcl

sudo systemctl restart consul.service

sleep 30

echo "Consul started"

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

# # starting the application
# if [ "${application_name}" = "consul-server=1" ]; then
#   # receiver
#   consul peering generate-token -name cluster-02
# elif [ "${application_name}" = "consul-server=0" ]; then
#   # dialer
#   consul peering establish -name cluster-01 -peering-token token-from-generate
# else
#   echo "Unknown application name: ${application_name}"
# fi

