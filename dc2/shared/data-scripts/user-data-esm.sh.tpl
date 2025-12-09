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
# Consul ESM Configuration for version \${esm_version}
log_level = "INFO"
enable_syslog = false
# Enable file-based logging with rotation
log_file = "/var/log/consul-esm/consul-esm.log"
log_rotate_duration = "24h"
log_rotate_max_files = 30

instance_id = "${instanceid}"

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
# Ensure log directory has proper permissions before starting
ExecStartPre=/bin/sh -c 'mkdir -p /var/log/consul-esm && chown root:adm /var/log/consul-esm && chmod 755 /var/log/consul-esm'
# Let ESM handle its own file logging
ExecStart=/usr/local/bin/consul-esm -config-file=/etc/consul-esm/config.hcl
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
Restart=on-failure
RestartSec=10
LimitNOFILE=65536
StandardOutput=journal
StandardError=journal
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