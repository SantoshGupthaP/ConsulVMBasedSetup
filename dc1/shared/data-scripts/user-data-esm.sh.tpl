#!/bin/bash

exec > >(sudo tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
set -ex

# Install necessary packages
sudo apt-get update -y
sudo apt-get install -y wget unzip jq awscli

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

# Install Consul ESM (Custom Binary)
# Option 1: Download from S3 (replace with your bucket/path)
# aws s3 cp s3://consul-esm-scale-testing/consul-esm-linux2 /usr/local/bin/consul-esm --region ap-south-1
aws s3 cp s3://consul-esm-scale-testing/consul-esm-shashank-7 /usr/local/bin/consul-esm --region ap-south-1

# Make binary executable
chmod +x /usr/local/bin/consul-esm

# Create ESM config directory
mkdir -p /etc/consul-esm

# Create log directory for ESM with proper permissions for Promtail
sudo mkdir -p /var/log/consul-esm
sudo chmod 755 /var/log/consul-esm
sudo chown root:adm /var/log/consul-esm
# Pre-create log file with readable permissions for Promtail
sudo touch /var/log/consul-esm/consul-esm.log
sudo chmod 644 /var/log/consul-esm/consul-esm.log
# Set group ownership to adm so promtail user can read logs
sudo chgrp adm /var/log/consul-esm/consul-esm.log
sudo chmod 644 /var/log/consul-esm/consul-esm.log
# Ensure log file has proper permissions for promtail access
chown root:adm /var/log/consul-esm/consul-esm.log

# Create proper ESM configuration for version 0.7.1
cat << EOF | sudo  tee /etc/consul-esm/config.hcl > /dev/null
# Consul ESM Configuration for version \${esm_version}
log_level = "INFO"
enable_syslog = false
# Enable file-based logging with rotation
log_file = "/var/log/consul-esm/consul-esm.log"
log_rotate_duration = "24h"
log_rotate_max_files = 30

instance_id = "${instanceid}"
# For emitting Consul ESM metrics to Prometheus
client_address = "0.0.0.0:8080"
# service registration 
consul_service = "consul-esm"
consul_service_tag = "consul-esm"

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
datacenter = "dc1"

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


# Start ESM service
systemctl daemon-reload
systemctl enable consul-esm
systemctl start consul-esm

# Setup file permissions management script for ESM logs
cat << 'EOF' | sudo tee /usr/local/bin/fix-esm-log-perms.sh > /dev/null
#!/bin/bash
# Fix permissions for all ESM log files
find /var/log/consul-esm -name "consul-esm*.log*" -type f -exec chown root:adm {} \;
find /var/log/consul-esm -name "consul-esm*.log*" -type f -exec chmod 644 {} \;
EOF

sudo chmod +x /usr/local/bin/fix-esm-log-perms.sh

# Create cron job to fix permissions hourly for any new log files
echo "0 * * * * root /usr/local/bin/fix-esm-log-perms.sh > /dev/null 2>&1" | sudo tee -a /etc/crontab

# Remove old logrotate config that conflicts with ESM's rotation
sudo rm -f /etc/logrotate.d/consul-esm


echo "Consul ESM setup complete!"
echo "ESM Status: $(systemctl is-active consul-esm)"
echo "ESM is now monitoring external services and performing health checks" 