#!/bin/bash

exec > >(sudo tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
set -ex

sudo apt-get update -y
sudo apt-get install -y wget tar

# Install Prometheus
wget https://github.com/prometheus/prometheus/releases/download/v2.52.0/prometheus-2.52.0.linux-amd64.tar.gz
tar xvf prometheus-2.52.0.linux-amd64.tar.gz
sudo mv prometheus-2.52.0.linux-amd64/prometheus /usr/local/bin/
sudo mv prometheus-2.52.0.linux-amd64/promtool /usr/local/bin/
sudo mkdir -p /etc/prometheus /var/lib/prometheus
sudo mv prometheus-2.52.0.linux-amd64/consoles /etc/prometheus/
sudo mv prometheus-2.52.0.linux-amd64/console_libraries /etc/prometheus/

# Install Consul Exporter
wget https://github.com/prometheus/consul_exporter/releases/download/v0.11.0/consul_exporter-0.11.0.linux-amd64.tar.gz
tar xvf consul_exporter-0.11.0.linux-amd64.tar.gz
sudo mv consul_exporter-0.11.0.linux-amd64/consul_exporter /usr/local/bin/

# Create Prometheus config
cat << 'EOC' | sudo tee /etc/prometheus/prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'Consul'
    static_configs:
      - targets: ['localhost:9107']
  - job_name: 'Consul-Server0-Node'
    static_configs:
      - targets: ['${consul_server_0_ip}:9100']
  - job_name: 'Consul-Server1-Node'
    static_configs:
      - targets: ['${consul_server_1_ip}:9100']
  - job_name: 'Consul-Server2-Node'
    static_configs:
      - targets: ['${consul_server_2_ip}:9100']
${esm_node_configs}
${esm_agent_configs}
  - job_name: 'Consul-Server0-Agent'
    metrics_path: /v1/agent/metrics
    params:
      format: ['prometheus']
    bearer_token: '${consul_token}'
    static_configs:
      - targets: ['${consul_server_0_ip}:8500']
  - job_name: 'Consul-Server1-Agent'
    metrics_path: /v1/agent/metrics
    params:
      format: ['prometheus']
    bearer_token: '${consul_token}'
    static_configs:
      - targets: ['${consul_server_1_ip}:8500']
  - job_name: 'Consul-Server2-Agent'
    metrics_path: /v1/agent/metrics
    params:
      format: ['prometheus']
    bearer_token: '${consul_token}'
    static_configs:
      - targets: ['${consul_server_2_ip}:8500']
EOC

# Create systemd service for Prometheus
cat << 'EOP' | sudo tee /etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus
After=network.target

[Service]
User=root
ExecStart=/usr/local/bin/prometheus --config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/var/lib/prometheus --storage.tsdb.retention.time=15d --storage.tsdb.retention.size=20GB
Restart=always

[Install]
WantedBy=multi-user.target
EOP

# Create systemd service for Consul Exporter
cat << 'EOE' | sudo tee /etc/systemd/system/consul_exporter.service
[Unit]
Description=Consul Exporter
After=network.target

[Service]
User=root
Environment="CONSUL_HTTP_TOKEN=${consul_token}"
ExecStart=/usr/local/bin/consul_exporter --consul.server=http://${consul_server_0_ip}:8500
Restart=always

[Install]
WantedBy=multi-user.target
EOE

sudo systemctl daemon-reload
sudo systemctl enable prometheus
sudo systemctl start prometheus
sudo systemctl enable consul_exporter
sudo systemctl start consul_exporter

echo "Prometheus setup complete!"
echo "Prometheus Status: $(systemctl is-active prometheus)"
echo "Consul Exporter Status: $(systemctl is-active consul_exporter)"
