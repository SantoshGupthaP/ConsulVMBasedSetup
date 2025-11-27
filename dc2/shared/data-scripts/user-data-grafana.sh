#!/bin/bash

exec > >(sudo tee /var/log/user-data-grafana.log|logger -t user-data-grafana -s 2>/dev/console) 2>&1
set -ex

echo "Starting Grafana installation..."

# Update system
sudo apt-get update
sudo apt-get install -y apt-transport-https software-properties-common wget

# Install Grafana
wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add -
echo "deb https://packages.grafana.com/oss/deb stable main" | sudo tee /etc/apt/sources.list.d/grafana.list
sudo apt-get update
sudo apt-get install -y grafana

# Enable and start Grafana
sudo systemctl enable grafana-server
sudo systemctl start grafana-server

# Wait for Grafana to start
echo "Waiting for Grafana to start..."
for i in {1..30}; do
  if curl -s http://localhost:3000/api/health | grep -q "ok"; then
    echo "Grafana is ready!"
    break
  fi
  echo "Waiting for Grafana... ($i/30)"
  sleep 5
done

# Configure datasources via provisioning
echo "Configuring datasources..."
sudo mkdir -p /etc/grafana/provisioning/datasources

# Create datasources configuration
cat <<EOF | sudo tee /etc/grafana/provisioning/datasources/datasources.yaml
apiVersion: 1

datasources:
  # Prometheus datasource
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://${prometheus_private_ip}:9090
    isDefault: true
    editable: true
    jsonData:
      timeInterval: "15s"

  # Loki datasource
  - name: Loki
    type: loki
    access: proxy
    url: http://${loki_private_ip}:3100
    isDefault: false
    editable: true
    jsonData:
      maxLines: 1000

  # Consul datasource (optional)
  # - name: Consul
  #   type: grafana-consul-datasource
  #   access: proxy
  #   url: http://<CONSUL_PRIVATE_IP>:8500
  #   isDefault: false
  #   editable: true
EOF

sudo chown -R grafana:grafana /etc/grafana/provisioning/datasources

# Restart Grafana to apply datasource configuration
sudo systemctl restart grafana-server

echo "Waiting for Grafana to restart..."
sleep 10
for i in {1..30}; do
  if curl -s http://localhost:3000/api/health | grep -q "ok"; then
    echo "Grafana is ready!"
    break
  fi
  echo "Waiting for Grafana... ($i/30)"
  sleep 5
done

echo "Grafana installation and configuration completed!"
echo "Access Grafana at: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):3000"
echo "Default credentials: admin/admin"
