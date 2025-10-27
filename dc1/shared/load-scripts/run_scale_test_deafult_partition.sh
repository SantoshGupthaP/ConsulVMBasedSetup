#!/bin/bash

# This script creates partitions and registers external services with health checks
# pointing to a pool of real workload IPs. It includes an auth token and reports
# the status of each registration with detailed debug output on failure.

# USAGE: ./run_scale_test.sh <MAX_PARTITIONS> <IP1> <IP2> <IP3> <IP4> <IP5>
# Example: ./run_scale_test.sh 5000 10.0.1.12 10.0.1.23 10.0.1.34 10.0.1.45 10.0.1.56

MAX_PARTITIONS=$1
# Put all the workload IPs into an array
WORKLOAD_IPS=("${@:2}")
NUM_WORKLOADS=${#WORKLOAD_IPS[@]}

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <MAX_PARTITIONS> <IP1> <IP2> ..."
  exit 1
fi

# Make sure the token and address are set
if [[ -z "$CONSUL_HTTP_TOKEN" || -z "$CONSUL_HTTP_ADDR" ]]; then
    echo "Error: CONSUL_HTTP_TOKEN or CONSUL_HTTP_ADDR environment variables are not set."
    echo "Please export your Consul token and address before running."
    exit 1
fi

echo "--- Starting Scale Test ---"
echo "Target: ${MAX_PARTITIONS} loops, 10 Namespaces/loop, 10 Services/namespace in 'default' partition"
echo "Workload IPs: ${WORKLOAD_IPS[*]}"
echo "Total services to register: $(($MAX_PARTITIONS * 10 * 10))"

start_time=$(date +%s)
service_count=0

for ((p=1; p<=$MAX_PARTITIONS; p++)); do
  partition_name="ap1"

  for ((n=1; n<=1; n++)); do
    ns_name="ns-${p}-${n}"
    consul namespace create -partition="${partition_name}" -name="${ns_name}"

    for ((s=1; s<=5; s++)); do
      ip_index=$((service_count % NUM_WORKLOADS))
      target_ip=${WORKLOAD_IPS[$ip_index]}

      node_name="ext-node-${p}-${n}-${s}"
      service_name="workload-${s}"
      service_id="workload-${p}-${n}-${s}"

      # --- START: Modified Section ---
      # 1. Generate a new, valid UUID for each registration event.
      registration_uuid=$(cat /proc/sys/kernel/random/uuid)

      read -r -d '' SERVICE_JSON << EOM
      {
        "Datacenter": "dc1",
        "Node": "${node_name}",
        "ID": "${registration_uuid}",
        "Address": "${target_ip}",
        "NodeMeta": {
          "external-node": "true",
          "external-probe": "true"
        },
        "Service": {
          "ID": "${service_id}",
          "Service": "${service_name}",
          "Tags": [ "external", "${ns_name}" ],
          "Address": "${target_ip}",
          "Port": 8080
        },
        "Checks": [{
          "CheckID": "${service_id}-check",
          "Name": "Workload HTTP Health Check",
          "Status": "passing",
          "ServiceID": "${service_id}",
          "Definition": {
            "HTTP": "http://${target_ip}:8080/health",
            "Interval": "10s",
            "Timeout": "5s",
            "DeregisterCriticalServiceAfter": "60m"
           }
        }]
      }
EOM
      # --- END: Modified Section ---

      echo "Registering service ${service_id}..."
      
      response=$(curl -s --connect-timeout 5 -w "\n%{http_code}" \
        --request PUT \
        --header "X-Consul-Token: $CONSUL_HTTP_TOKEN" \
        --data "$SERVICE_JSON" \
        "$CONSUL_HTTP_ADDR/v1/catalog/register?ns=${ns_name}&partition=${partition_name}")
      
      http_code=$(tail -n1 <<< "$response")
      body=$(sed '$ d' <<< "$response")

      if [[ "$http_code" -eq 200 ]]; then
        echo "SUCCESS: Registered service ${service_id} (Status: ${http_code})"
      elif [[ "$http_code" -eq 000 ]]; then
        echo "ERROR: Could not connect to the Consul server (Status: 000)."
        echo "--- DEBUG INFO ---"
        echo "CONSUL_HTTP_ADDR: $CONSUL_HTTP_ADDR"
        echo "CONSUL_HTTP_TOKEN: $CONSUL_HTTP_TOKEN"
        echo "------------------"
        exit 1
      else
        echo "ERROR: Failed to register service ${service_id} (Status: ${http_code}) - Response: ${body}"
        echo "--- DEBUG INFO ---"
        echo "CONSUL_HTTP_ADDR: $CONSUL_HTTP_ADDR"
        echo "CONSUL_HTTP_TOKEN: $CONSUL_HTTP_TOKEN"
        echo "SERVICE_JSON PAYLOAD:"
        echo "$SERVICE_JSON"
        echo "------------------"
      fi

      ((service_count++))
    done
  done
 
  if (( $p % 100 == 0 )); then
    echo "$(date): Progress - Loops: ${p}/${MAX_PARTITIONS}, Total Services Registered: ${service_count}"
  fi
done

end_time=$(date +%s)
echo "--- Scale Test Finished ---"
echo "Total execution time: $((end_time - start_time)) seconds."

