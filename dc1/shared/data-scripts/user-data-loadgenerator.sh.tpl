#!/bin/bash

exec > >(sudo tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
set -ex

sudo apt-get update -y

sudo apt-get install -y unzip wget

# Download Consul
wget https://releases.hashicorp.com/consul/${consul_version}/consul_${consul_version}_linux_amd64.zip

# Unzip and install
unzip consul_${consul_version}_linux_amd64.zip
sudo mv consul /usr/local/bin/
rm consul_${consul_version}_linux_amd64.zip

echo "export CONSUL_HTTP_TOKEN=e95b599e-166e-7d80-08ad-aee76e7ddf19" >> /home/ubuntu/.bashrc
echo "export CONSUL_HTTP_ADDR=${CONSUL_IP}:8500" >> /home/ubuntu/.bashrc