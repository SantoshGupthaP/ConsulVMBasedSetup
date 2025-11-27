#!/bin/bash

exec > >(sudo tee /var/log/user-data-loki.log|logger -t user-data-loki -s 2>/dev/console) 2>&1
set -ex

echo "Starting Loki installation..."

# Update system
sudo apt-get update -y
sudo apt-get install -y wget unzip

# Create loki user
sudo useradd --system --no-create-home --shell /bin/false loki

# Download and install Loki
cd /tmp
wget https://github.com/grafana/loki/releases/download/v${loki_version}/loki-linux-amd64.zip
unzip loki-linux-amd64.zip
sudo mv loki-linux-amd64 /usr/local/bin/loki
sudo chmod +x /usr/local/bin/loki
rm loki-linux-amd64.zip

# Create Loki directories
sudo mkdir -p /etc/loki
sudo mkdir -p /var/lib/loki/{chunks,rules}
sudo chown -R loki:loki /var/lib/loki
sudo chown -R loki:loki /etc/loki

# Create Loki configuration
cat <<EOF | sudo tee /etc/loki/config.yml
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9096
  log_level: info

common:
  path_prefix: /var/lib/loki
  storage:
    filesystem:
      chunks_directory: /var/lib/loki/chunks
      rules_directory: /var/lib/loki/rules
  replication_factor: 1
  ring:
    instance_addr: 127.0.0.1
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

limits_config:
  enforce_metric_name: false
  reject_old_samples: true
  reject_old_samples_max_age: 168h
  ingestion_rate_mb: 10
  ingestion_burst_size_mb: 20

chunk_store_config:
  max_look_back_period: 0s

table_manager:
  retention_deletes_enabled: false
  retention_period: 0s

compactor:
  working_directory: /var/lib/loki/compactor
  shared_store: filesystem
  compaction_interval: 10m
  retention_enabled: true
  retention_delete_delay: 2h
  retention_delete_worker_count: 150

ruler:
  storage:
    type: local
    local:
      directory: /var/lib/loki/rules
  rule_path: /var/lib/loki/rules-temp
  alertmanager_url: http://localhost:9093
  ring:
    kvstore:
      store: inmemory
  enable_api: true
EOF

sudo chown loki:loki /etc/loki/config.yml

# Create Loki systemd service
cat <<EOF | sudo tee /etc/systemd/system/loki.service
[Unit]
Description=Loki Log Aggregation System
After=network.target

[Service]
Type=simple
User=loki
Group=loki
ExecStart=/usr/local/bin/loki -config.file=/etc/loki/config.yml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Enable and start Loki
sudo systemctl daemon-reload
sudo systemctl enable loki
sudo systemctl start loki

echo "Loki installation completed"

# Wait for Loki to be ready
echo "Waiting for Loki to be ready..."
for i in {1..30}; do
  if curl -s http://localhost:3100/ready | grep -q "ready"; then
    echo "Loki is ready!"
    break
  fi
  echo "Waiting for Loki to start... ($i/30)"
  sleep 5
done

echo "Loki setup complete!"
