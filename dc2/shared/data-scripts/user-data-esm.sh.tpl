#!/bin/bash

exec > >(sudo tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
set -ex

# Install necessary packages
sudo apt-get update -y
sudo apt-get install -y wget unzip jq

# # Start SSM agent
# systemctl enable amazon-ssm-agent
# systemctl start amazon-ssm-agent

# Install node_exporter for monitoring
wget https://github.com/prometheus/node_exporter/releases/download/v${node_exporter_version}/node_exporter-${node_exporter_version}.linux-amd64.tar.gz
tar xvfz node_exporter-*.tar.gz
mv node_exporter-${node_exporter_version}.linux-amd64/node_exporter /usr/local/bin/
rm -rf node_exporter-*

# Create node_exporter service
cat << EOF | tee /etc/systemd/system/node_exporter.service > /dev/null
[Unit]
Description=Node Exporter
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF

# Start node_exporter
systemctl enable node_exporter
systemctl start node_exporter

# Install Consul ESM
wget https://releases.hashicorp.com/consul-esm/${esm_version}/consul-esm_${esm_version}_linux_amd64.zip
unzip consul-esm_${esm_version}_linux_amd64.zip
mv consul-esm /usr/local/bin/
rm consul-esm_${esm_version}_linux_amd64.zip

# Create ESM config directory
mkdir -p /etc/consul-esm

# Create log directory for ESM with proper permissions for Promtail
sudo mkdir -p /var/log/consul-esm
sudo chmod 755 /var/log/consul-esm
# Pre-create log file with readable permissions for Promtail
sudo touch /var/log/consul-esm/consul-esm.log
sudo chmod 644 /var/log/consul-esm/consul-esm.log
# Set group ownership to adm so promtail user can read logs
sudo chgrp adm /var/log/consul-esm/consul-esm.log
sudo chmod 644 /var/log/consul-esm/consul-esm.log

# Create proper ESM configuration for version 0.7.1
cat << EOF | sudo  tee /etc/consul-esm/config.hcl > /dev/null
# Consul ESM Configuration for version $${esm_version}
log_level = "INFO"
enable_syslog = false
log_file = "/var/log/consul-esm/consul-esm.log"

# instance_id = "consul-esm-${environment}"
# For emitting Consul ESM metrics to Prometheus
client_address = "0.0.0.0:8080"
# service registration 
consul_service = "consul-esm"
consul_service_tag = "consul-external-service-monitor-tag"

consul_kv_path = "consul-esm/"

# External node metadata - Standard ESM detection keys
external_node_meta {
  "external-node" = "true"
}

# Basic ESM settings
node_reconnect_timeout = "72h"
node_probe_interval = "${ping_interval}"
# node_probe_interval = "10s"
disable_coordinate_updates = false

enable_agentless = true

# Consul connection configuration

# The address of the Consul server to use if enable_agentless is set to true.
# Can also be provided through the CONSUL_HTTP_ADDR environment variable.
http_addr = "${consul_address}:8500"

# The ACL token to use when communicating with the local Consul agent. Can
# also be provided through the CONSUL_HTTP_TOKEN environment variable.
token = "${consul_token}"
#token = "e95b599e-166e-7d80-08ad-aee76e7ddf19"

# The Consul datacenter to use.
datacenter = "dc2"

# The target Admin Partition to use.
# Can also be provided through the CONSUL_PARTITION environment variable.
partition = "global"

# Telemetry configuration
telemetry {
  disable_hostname = false
  prometheus_retention_time = "24h"
  filter_default = true
}
EOF

# Create ESM service with enhanced configuration
cat << EOF | sudo tee /etc/systemd/system/consul-esm.service > /dev/null
[Unit]
Description=Consul ESM (External Service Monitor)
Documentation=https://github.com/hashicorp/consul-esm
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/consul-esm/config.hcl

[Service]
Type=simple
User=root
Group=root
# Ensure log file has proper permissions before starting
ExecStartPre=/bin/sh -c 'touch /var/log/consul-esm/consul-esm.log && chown root:adm /var/log/consul-esm/consul-esm.log && chmod 644 /var/log/consul-esm/consul-esm.log'
ExecStart=/usr/local/bin/consul-esm -config-file=/etc/consul-esm/config.hcl
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
Restart=on-failure
LimitNOFILE=65536
StandardOutput=journal+console
StandardError=journal+console
SyslogIdentifier=consul-esm

[Install]
WantedBy=multi-user.target
EOF

# Create ESM log directory with proper permissions
sudo mkdir -p /var/log/consul-esm
chown root:adm /var/log/consul-esm
chmod 755 /var/log/consul-esm
# Ensure log file has proper permissions for promtail access
touch /var/log/consul-esm/consul-esm.log
chown root:adm /var/log/consul-esm/consul-esm.log
chmod 644 /var/log/consul-esm/consul-esm.log

# Start ESM service
systemctl daemon-reload
systemctl enable consul-esm
systemctl start consul-esm

# Setup logrotate for ESM logs to maintain proper permissions
cat << EOF | sudo tee /etc/logrotate.d/consul-esm > /dev/null
/var/log/consul-esm/*.log {
    daily
    missingok
    rotate 7
    compress
    notifempty
    create 644 root adm
    postrotate
        systemctl reload consul-esm > /dev/null 2>&1 || true
    endscript
}
EOF


echo "Consul ESM setup complete!"
echo "ESM Status: $(systemctl is-active consul-esm)"
echo "ESM is now monitoring external services and performing health checks" 