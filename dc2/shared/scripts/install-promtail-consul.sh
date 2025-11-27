#!/bin/bash
set -ex

LOKI_IP="$1"
COUNT_INDEX="$2"

echo "Installing Promtail on Consul Server $COUNT_INDEX..."

# Ensure required packages are installed (may already be present)
echo "Ensuring required packages are installed..."
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -y || true
sudo apt-get install -y wget unzip curl || true

# Wait for Loki to be available
echo "Waiting for Loki at $LOKI_IP:3100 to be ready..."
for i in {1..60}; do
  if curl -s http://$LOKI_IP:3100/ready | grep -q 'ready'; then
    echo 'Loki is ready!'
    break
  fi
  echo "Waiting for Loki... ($i/60)"
  sleep 5
done

# Create promtail user
sudo useradd --system --no-create-home --shell /bin/false promtail || true

# Download and install Promtail
PROMTAIL_VERSION='2.9.3'
cd /tmp
wget -q https://github.com/grafana/loki/releases/download/v$PROMTAIL_VERSION/promtail-linux-amd64.zip
unzip -o promtail-linux-amd64.zip
sudo mv promtail-linux-amd64 /usr/local/bin/promtail
sudo chmod +x /usr/local/bin/promtail
rm -f promtail-linux-amd64.zip

# Create Promtail directories
sudo mkdir -p /etc/promtail /var/lib/promtail /var/log/consul

# Get instance metadata
TOKEN=$(curl -X PUT 'http://instance-data/latest/api/token' -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600')
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
  - url: http://$LOKI_IP:3100/loki/api/v1/push
    backoff_config:
      min_period: 1s
      max_period: 10s
      max_retries: 10

scrape_configs:
  - job_name: consul-server
    static_configs:
      - targets:
          - localhost
        labels:
          job: consul-server
          instance: $INSTANCE_ID
          hostname: $HOSTNAME
          private_ip: $PRIVATE_IP
          __path__: /var/log/consul/consul*.log
    pipeline_stages:
      - regex:
          expression: '^(?P<timestamp>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+Z)\s+\[(?P<level>\w+)\]\s+(?P<message>.*)$'
      - labels:
          level:
      - timestamp:
          source: timestamp
          format: RFC3339Nano

  - job_name: system
    static_configs:
      - targets:
          - localhost
        labels:
          job: system
          instance: $INSTANCE_ID
          hostname: $HOSTNAME
          private_ip: $PRIVATE_IP
          __path__: /var/log/syslog

  - job_name: user-data
    static_configs:
      - targets:
          - localhost
        labels:
          job: user-data
          instance: $INSTANCE_ID
          hostname: $HOSTNAME
          private_ip: $PRIVATE_IP
          __path__: /var/log/user-data.log
EOF

sudo chown -R promtail:promtail /etc/promtail /var/lib/promtail
sudo usermod -a -G adm promtail
# Add promtail user to consul group to read log files
sudo usermod -a -G consul promtail

# Create Promtail systemd service
cat <<'EOF' | sudo tee /etc/systemd/system/promtail.service
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
sudo systemctl restart promtail

echo "Promtail installation completed for Consul Server $COUNT_INDEX"
