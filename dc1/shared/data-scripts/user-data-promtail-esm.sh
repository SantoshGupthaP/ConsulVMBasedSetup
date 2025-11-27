#!/bin/bash

exec > >(sudo tee /var/log/user-data-promtail.log|logger -t user-data-promtail -s 2>/dev/console) 2>&1
set -ex

echo "Starting Promtail installation for Consul ESM..."

# Wait for main user-data to complete
sleep 30

# Update system
sudo apt-get update -y
sudo apt-get install -y wget unzip

# Create promtail user
sudo useradd --system --no-create-home --shell /bin/false promtail

# Download and install Promtail
PROMTAIL_VERSION="2.9.3"
cd /tmp
wget https://github.com/grafana/loki/releases/download/v${PROMTAIL_VERSION}/promtail-linux-amd64.zip
unzip promtail-linux-amd64.zip
sudo mv promtail-linux-amd64 /usr/local/bin/promtail
sudo chmod +x /usr/local/bin/promtail
rm promtail-linux-amd64.zip

# Create Promtail directories
sudo mkdir -p /etc/promtail
sudo mkdir -p /var/lib/promtail

# Get instance metadata
TOKEN=$(curl -X PUT "http://instance-data/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://instance-data/latest/meta-data/instance-id)
PRIVATE_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://instance-data/latest/meta-data/local-ipv4)
HOSTNAME=$(hostname)

# Create Promtail configuration
cat <<EOF | sudo tee /etc/promtail/config.yml
server:
  http_listen_port: 9080
  grpc_listen_port: 0
  log_level: info

positions:
  filename: /var/lib/promtail/positions.yaml

clients:
  - url: http://${loki_private_ip}:3100/loki/api/v1/push
    backoff_config:
      min_period: 1s
      max_period: 10s
      max_retries: 10

scrape_configs:
  # Consul ESM logs
  - job_name: consul-esm
    static_configs:
      - targets:
          - localhost
        labels:
          job: consul-esm
          instance: $INSTANCE_ID
          hostname: $HOSTNAME
          private_ip: $PRIVATE_IP
          esm_instance_id: ${esm_instance_id}
          __path__: /var/log/consul-esm/*.log

  # System logs
  - job_name: system
    static_configs:
      - targets:
          - localhost
        labels:
          job: system
          instance: $INSTANCE_ID
          hostname: $HOSTNAME
          private_ip: $PRIVATE_IP
          esm_instance_id: ${esm_instance_id}
          __path__: /var/log/syslog

  # User data logs
  - job_name: user-data
    static_configs:
      - targets:
          - localhost
        labels:
          job: user-data
          instance: $INSTANCE_ID
          hostname: $HOSTNAME
          private_ip: $PRIVATE_IP
          esm_instance_id: ${esm_instance_id}
          __path__: /var/log/user-data.log
EOF

sudo chown -R promtail:promtail /etc/promtail
sudo chown -R promtail:promtail /var/lib/promtail

# Add promtail user to adm group to read logs
sudo usermod -a -G adm promtail

# Create Promtail systemd service
cat <<EOF | sudo tee /etc/systemd/system/promtail.service
[Unit]
Description=Promtail Log Collector
After=network.target

[Service]
Type=simple
User=promtail
Group=promtail
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail/config.yml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Enable and start Promtail
sudo systemctl daemon-reload
sudo systemctl enable promtail
sudo systemctl start promtail

echo "Promtail installation completed for Consul ESM"
