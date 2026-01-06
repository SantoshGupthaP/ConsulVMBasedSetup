#!/bin/bash

set -e

CONFIGDIR=/ops/shared/config
# CONSULVERSION=1.18.1+ent
# ENVOYVERSION=1.27.7
CONSULCONFIGDIR=/etc/consul.d
HOME_DIR=ubuntu

# Wait for network
sleep 15

DOCKER_BRIDGE_IP_ADDRESS=(`ip -brief addr show docker0 | awk '{print $3}' | awk -F/ '{print $1}'`)
CLOUD=$1
SERVER_COUNT=$2
RETRY_JOIN=$3
CONSULVERSION=$4
ENVOYVERSION=$5

# Get IP from metadata service
case $CLOUD in
  aws)
    echo "CLOUD_ENV: aws"
    TOKEN=$(curl -X PUT "http://instance-data/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

    IP_ADDRESS=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://instance-data/latest/meta-data/local-ipv4)
    ;;
  gce)
    echo "CLOUD_ENV: gce"
    IP_ADDRESS=$(curl -H "Metadata-Flavor: Google" http://metadata/computeMetadata/v1/instance/network-interfaces/0/ip)
    ;;
  azure)
    echo "CLOUD_ENV: azure"
    IP_ADDRESS=$(curl -s -H Metadata:true --noproxy "*" http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0?api-version=2021-12-13 | jq -r '.["privateIpAddress"]')
    ;;
  *)
    echo "CLOUD_ENV: not set"
    ;;
esac


sudo apt-get install -y software-properties-common
sudo add-apt-repository universe && sudo apt-get update
sudo apt-get install -y unzip tree redis-tools jq curl tmux
sudo apt-get clean

# Install HashiCorp Apt Repository
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list

# Install HashiStack Packages
# sudo apt-get update && sudo apt-get -y install \
	# consul=$CONSULVERSION* \
	# nomad=$NOMADVERSION* \
	# vault=$VAULTVERSION* \
	# consul-template=$CONSULTEMPLATEVERSION*

# Install Consul only
sudo apt-get update && sudo apt-get -y install consul-enterprise=$CONSULVERSION* hashicorp-envoy=$ENVOYVERSION*

echo "Setup consul config"
# Consul
sed -i "s/IP_ADDRESS/$IP_ADDRESS/g" $CONFIGDIR/consul.hcl
sed -i "s/SERVER_COUNT/$SERVER_COUNT/g" $CONFIGDIR/consul.hcl
sed -i "s/RETRY_JOIN/$RETRY_JOIN/g" $CONFIGDIR/consul.hcl
sudo cp $CONFIGDIR/consul.hcl $CONSULCONFIGDIR

# install license file
# Create Consul log directory
sudo mkdir -p /var/log/consul
sudo chown consul:consul /var/log/consul
sudo chmod 755 /var/log/consul
# Set group-readable permissions for log files so Promtail can read them
sudo chmod g+r /var/log/consul/ 2>/dev/null || true

sudo tee $CONSULCONFIGDIR/license.hclic <<EOF
02MV4UU43BK5HGYYTOJZWFQMTMNNEWU33JJVVEK6KOIRGXUTKEMN2E6R2VGNHFGMLIJZCGQ2SMKRBGUWTNKV2FURCNGVNEIVJQJ5CFS6K2IRUGQSLJO5UVSM2WPJSEOOLULJMEUZTBK5IWST3JJEYFSVCBPFNEISTILJBTC3KNKRAXOTCUJJUFS2TLORGVIUTJLFJTAMSPK5EXQWKUKJUE6R2NPFMWUZ3JJRBUU4DCNZHDAWKXPBZVSWCSOBRDENLGMFLVC2KPNFEXCSLJO5UWCWCOPJSFOVTGMRDWY5C2KNETMSLKJF3U22SZORGUIRLUJVCFMVKNIRKTMTSEJE3E4RCNOVHVIY3XJ5KGONKONJGTIV3JJFZUS3SOGBMVQSRQLAZVE4DCK5KWST3JJF4U2RCJGJGFIQLYJRKECMKWIRAXOT3KIF3U62SBO5LWSSLTJFWVMNDDI5WHSWKYKJYGEMRVMZSEO3DULJJUSNSJNJEXOTLKLF2E2RCRORGUIUSVJVCECNSNIRATMTKEIJQUS2LXNFSEOVTZMJLWY5KZLBJHAYRSGVTGIR3MORNFGSJWJFVES52NNJMXITKEKF2E2RCSKVGUIQJWJVCECNSNIRBGCSLJO5UWGSCKOZNEQVTKMRBUSNSJNVHHMYTOJYYWEQ2JONEW2WTTLFLWI6SJNJYDOSLNGF3FUSCWONNFQTLJJ5WHG2K2GJ4HMWLNIZZUYWC2OBRTE3DJMFLXQ4DEJBVXIY3NHEYWIR3MOVNHSML2LEZEM422KNEXGSLNMR3GI3KWPFRG2RTVLEZFK5DDI44XGYKXJY2US3BRHFTFCPJ5FZZDAK2OF5ZHQNSBIEXXGUD2IFTDMZKZIFEXCMLBNNZFE5JZMRHFIL3FJVTGQSZPIVTEGSL2INFUYQRQOIZWE4BQMJKXKLZYJZCFM32GK5NEC2KVKVUHIOLKI5THKOKKIZATO6SZINYDCZCBNNRWCNDEKYYDGMZYKB3W2VTMMF3EUUBUOBFHQSKJHFCDMVKGJRKWCVSQNJVVOSTUMNCDM4DBNQ3G6T3GI5XEWMT2KBFUUUTNI5EFMM3FLJ3XCRTFFNXTO2ZPOMVUCVCONBIFUZ2TF5FVMWLHF5FSW3CHKB3UYN3KIJ4ESN2HJ5QWWNSVMFUWCSDPMVVTAUSUN43TERCRHU6Q
EOF
sudo chmod a+r $CONSULCONFIGDIR/license.hclic

# Copy CA files to current directory
sudo cp /ops/shared/certs/consul-agent-ca.pem .
sudo cp /ops/shared/certs/consul-agent-ca-key.pem .

sudo chmod a+r consul-agent-ca.pem consul-agent-ca-key.pem
# Generate Consul server agent certificate and key
consul tls cert create -server -dc dc1 -additional-ipaddress="$IP_ADDRESS"

# Move the generated certs to /ops/shared/certs
sudo mv dc1-server-consul-0.pem /ops/shared/certs/
sudo mv dc1-server-consul-0-key.pem /ops/shared/certs/

# Set permissions to allow all to read and write
sudo chmod a+rw /ops/shared/certs/dc1-server-consul-0.pem
sudo chmod a+rw /ops/shared/certs/dc1-server-consul-0-key.pem
echo "Consul client TLS certs and keys are set up in /ops/shared/certs"

# Configure systemd to not suppress Consul logs
sudo mkdir -p /etc/systemd/system/consul.service.d
sudo tee /etc/systemd/system/consul.service.d/override.conf > /dev/null <<EOF
[Service]
StandardOutput=journal+console
StandardError=journal+console
SyslogIdentifier=consul
EOF

sudo systemctl daemon-reload
sudo systemctl enable consul.service
sudo systemctl start consul.service
sleep 10
export CONSUL_HTTP_ADDR=$IP_ADDRESS:8500
export CONSUL_RPC_ADDR=$IP_ADDRESS:8400

# Add hostname to /etc/hosts

echo "127.0.0.1 $(hostname)" | sudo tee --append /etc/hosts

# Set env vars for tool CLIs
echo "export CONSUL_HTTP_TOKEN=e95b599e-166e-7d80-08ad-aee76e7ddf19" | sudo tee --append /home/$HOME_DIR/.bashrc
echo "export CONSUL_RPC_ADDR=$IP_ADDRESS:8400" | sudo tee --append /home/$HOME_DIR/.bashrc
echo "export CONSUL_HTTP_ADDR=$IP_ADDRESS:8500" | sudo tee --append /home/$HOME_DIR/.bashrc