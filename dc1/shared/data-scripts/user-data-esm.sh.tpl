#!/bin/bash

exec > >(sudo tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
set -ex

# Install necessary packages
sudo apt-get update -y
sudo apt-get install -y wget unzip jq gpg coreutils

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

# Install Consul Enterprise
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update && sudo apt-get install -y consul-enterprise

# Create Consul directories
sudo mkdir -p /etc/consul.d
sudo mkdir -p /opt/consul

# Install license file
sudo tee /etc/consul.d/license.hclic <<EOF
02MV4UU43BK5HGYYTOJZWFQMTMNNEWU33JJV5FM3KOI5NGQWSEM52FUR2ZGVGUGMLLLFKFKM2MKRAXQWSEMN2E23K2NBHHURTKLJDVCM2ZPJTXOSLJO5UVSM2WPJSEOOLULJMEUZTBK5IWST3JJJUVSMSKNRNGURJTJ5JTC3C2IRHGWTCUIJUFURCFORHHU2ZSJZUTC2COI5KTEWTKJF4U42SBPBNFIVLJJRBUU4DCNZHDAWKXPBZVSWCSOBRDENLGMFLVC2KPNFEXCSLJO5UWCWCOPJSFOVTGMRDWY5C2KNETMSLKJF3U22SRORGUI23UJVCEUVKNIRRTMTKEJE3E4RCVOVGUI2ZQJV5FKMCPIRVTGV3JJFZUS3SOGBMVQSRQLAZVE4DCK5KWST3JJF4U2RCJGBGFIQJVJRKEC6CWIRAXOT3KIF3U62SBO5LWSSLTJFWVMNDDI5WHSWKYKJYGEMRVMZSEO3DULJJUSNSJNJEXOTLKKV2E2VCJORGXURSVJVCECNSNIRATMTKEIJQUS2LXNFSEOVTZMJLWY5KZLBJHAYRSGVTGIR3MORNFGSJWJFVES52NNJKXITKUJF2E26SGKVGUIQJWJVCECNSNIRBGCSLJO5UWGSCKOZNEQVTKMRBUSNSJNVHHMYTOJYYWEQ2JONEW2WTTLFLWI6SJNJYDOSLNGF3FUSCWONNFQTLJJ5WHG2K2GI4TEWSYJJ2VSVZVNJNFGMLXMIZHQ4CZGNVWSTCDJJXGERZZNFMVO53UMRWWY6TBK5FHAYSHNQYGKUZRPFRDGVRQMFLTK3SMLBHGUWKXPBWES3BRHFTFCPJ5FZZDARTUORMVM4SLPB2XQ2DXKZJFGRTMIJEUG6CPGY2W25BQOFLGITDRORCEG3RPLIZU2TTMK5HUU2CCIZVTSWRXLEYVMMSXOBLCWVRYJZSDINKGG55EIK2ZG5KEI52ZGREUQUCCII2TCZCBNNRWCNDEKYYDGMZYKB3W2VTMMF3EUUBUOBFHQSKJHFCDMVKGJRKWCVSQNJVVOSTUMNCDM4DBNQ3G6T3GI5XEWMT2KBFUUUTNI5EFMM3FLJ3XCRTFFNXTO2ZPOMVUCVCONBIFUZ2TF5FVMWLHF5FSW3CHKB3UYN3KIJ4ESN2HJ5QWWNSVMFUWCSDPMVVTAUSUN43TERCRHU6Q
EOF
sudo chmod a+r /etc/consul.d/license.hclic

# Create Consul log directory with proper permissions
sudo mkdir -p /var/log/consul
sudo chown consul:consul /var/log/consul
sudo chmod 755 /var/log/consul

# Create Consul client configuration
cat << CONSULEOF | sudo tee /etc/consul.d/consul.hcl > /dev/null
datacenter = "dc1"
data_dir = "/opt/consul"
log_level = "INFO"
log_file = "/var/log/consul/"
log_rotate_duration = "24h"
log_rotate_max_files = 30
server = false
retry_join = ["${consul_address}"]
bind_addr = "{{ GetPrivateIP }}"
client_addr = "127.0.0.1"

# Partition configuration - must match ESM partition
partition = "global"

# Gossip encryption - must match server configuration
encrypt = "aPuGh+5UDskRAbkLaXRzFoSOcSM+5vAK+NEYOWHJH7w="

# License configuration
license_path = "/etc/consul.d/license.hclic"

acl {
  enabled = true
  default_policy = "deny"
  enable_token_persistence = true
  tokens {
    agent = "${consul_token}"
    default = "${consul_token}"
  }
}

ports {
  grpc = 8502
  http = 8500
  dns = 8600
}

# Auto-config disabled for clients to avoid license fetch issues
auto_config {
  enabled = false
}
CONSULEOF

# Configure systemd to not suppress Consul logs
sudo mkdir -p /etc/systemd/system/consul.service.d
sudo tee /etc/systemd/system/consul.service.d/override.conf > /dev/null <<CONSULOVERRIDEEOF
[Service]
StandardOutput=journal+console
StandardError=journal+console
SyslogIdentifier=consul
CONSULOVERRIDEEOF

# Start Consul client
sudo systemctl daemon-reload
sudo systemctl enable consul.service
sudo systemctl start consul.service

# Wait for Consul to be ready
echo "Waiting for Consul client to be ready..."
for i in {1..30}; do
  if consul members &>/dev/null; then
    echo "Consul client is ready"
    break
  fi
  echo "Waiting for Consul... ($i/30)"
  sleep 2
done

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

# Running in agentful mode - ESM will connect to local Consul client
enable_agentless = false

# Consul connection configuration

# The address of the local Consul client agent
# Can also be provided through the CONSUL_HTTP_ADDR environment variable.
http_addr = "127.0.0.1:8500"

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
Requires=network-online.target consul.service
After=network-online.target consul.service
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