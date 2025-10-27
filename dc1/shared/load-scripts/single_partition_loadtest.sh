#!/bin/bash

# This script creates Consul Admin Partitions at a controlled rate. For each partition,
# it then creates 10 namespaces and registers 10 services in each namespace.
# It simulates the MAXIMUM possible service footprint (~32KB) for this environment
# by creating 64 key-value pairs of 512 bytes each.

# --- Argument Parsing and Validation ---
if [[ $# -lt 5 ]]; then
  echo "Usage: $0 <TOTAL_NAMESPACES> <RATE> <DELAY> <START_INDEX> <IP1> <IP2> ..."
  echo "Example: ./create_partitions_with_services.sh 2000 10 1 1 10.0.1.10 10.0.1.11"
  exit 1
fi

TOTAL_NAMESPACES=$1
RATE_PER_SECOND=$2
BATCH_DELAY=$3
START_INDEX=$4
WORKLOAD_IPS=("${@:5}")
NUM_WORKLOADS=${#WORKLOAD_IPS[@]}

# Check for required environment variables
if [[ -z "$CONSUL_HTTP_ADDR" || -z "$CONSUL_HTTP_TOKEN" ]]; then
    echo "Error: CONSUL_HTTP_ADDR or CONSUL_HTTP_TOKEN environment variables are not set."
    exit 1
fi

# --- Global Counter for Round-Robin IP Selection ---
global_service_counter=0

# ==============================================================================
# API FUNCTIONS
# ==============================================================================

create_namespace() {
  local partition_name=$1; local namespace_name=$2; local retries=3; local delay=1
  local json_payload="{\"Name\": \"${namespace_name}\", \"Description\": \"Description for ${namespace_name}\"}"
  for ((attempt=1; attempt<=retries; attempt++)); do
    echo "    Attempt ${attempt}: Creating namespace ${namespace_name} in ${partition_name}..."
    local response=$(curl -s --connect-timeout 10 -w "\n%{http_code}" --request PUT --header "X-Consul-Token: $CONSUL_HTTP_TOKEN" --header "Content-Type: application/json" --data "$json_payload" "$CONSUL_HTTP_ADDR/v1/namespace?partition=${partition_name}")
    local http_code=$(echo "$response" | tail -n1)
    if [[ "$http_code" -eq 200 || "$http_code" -eq 201 ]]; then echo "    SUCCESS: Created namespace ${namespace_name}"; return 0; fi
    local body=$(echo "$response" | sed '$d'); echo "    WARN: Failed namespace ${namespace_name} (Status: ${http_code}) - Body: ${body}"
    if [[ $attempt -lt $retries ]]; then sleep $delay; delay=$((delay * 2)); fi
  done
  echo "    ERROR: Failed to create namespace ${namespace_name} after ${retries} attempts."; return 1
}

# --- Function to register a single service ---
register_service() {
    local partition_name=$1; local namespace_name=$2; local service_id=$3; local node_name=$4; local service_base_name=$5

    local ip_index=$((global_service_counter % NUM_WORKLOADS))
    local target_ip=${WORKLOAD_IPS[$ip_index]}
    local service_name="${service_base_name}-${target_ip}"
    local registration_uuid=$(cat /proc/sys/kernel/random/uuid)

    local meta_object_json="{"
  
    local j
    for j in $(seq 1 16); do #  64 keys (the max), would give 32Kb payload, 16 would give 8KB payload
      local chunk=$(head -c 384 /dev/urandom | base64 -w 0)
      meta_object_json+="\"chunk_${j}\": \"${chunk}\","
    done
    meta_object_json=$(echo "$meta_object_json" | sed 's/,$//')
    meta_object_json+="}"
    
    local SERVICE_JSON
    SERVICE_JSON=$(jq -n \
      --arg node_name "$node_name" \
      --arg reg_uuid "$registration_uuid" \
      --arg target_ip "$target_ip" \
      --arg svc_id "$service_id" \
      --arg svc_name "$service_name" \
      --arg ns_name "$namespace_name" \
      --argjson meta_obj "$meta_object_json" \
      '{
        "Datacenter": "dc1",
        "Node": $node_name,
        "ID": $reg_uuid,
        "Address": $target_ip,
        "NodeMeta": { "external-node": "true", "external-probe": "false" },
        "Service": {
          "ID": $svc_id,
          "Service": $svc_name,
          "Tags": [ $svc_name, $ns_name ],
          "Address": $target_ip,
          "Port": 8080,
          "Meta": $meta_obj
        },
        "Checks": [{
          "CheckID": ($svc_id + "-check"),
          "Name": "Workload HTTP Health Check",
          "Status": "passing",
          "ServiceID": $svc_id,
          "Definition": {
            "HTTP": ("http://" + $target_ip + ":8080/health"),
            "Interval": "30s", "Timeout": "5s", "DeregisterCriticalServiceAfter": "60m"
          }
        }]
      }')

    echo "      Registering service ${service_id} pointing to ${target_ip}..."
    
    local response
    response=$(echo "$SERVICE_JSON" | curl -s --connect-timeout 5 -w "\n%{http_code}" --request PUT --header "X-Consul-Token: $CONSUL_HTTP_TOKEN" --data @- "$CONSUL_HTTP_ADDR/v1/catalog/register?ns=${namespace_name}&partition=${partition_name}")
    
    local http_code=$(tail -n1 <<< "$response"); local body=$(sed '$ d' <<< "$response")

    if [[ "$http_code" -eq 200 ]]; then
      echo "      SUCCESS: Registered service ${service_id} (Status: ${http_code})"
    elif [[ "$http_code" -eq 000 ]]; then
      echo "      ERROR: Could not connect to the Consul server (Status: 000)."; exit 1
    else
      echo "      ERROR: Failed to register service ${service_id} (Status: ${http_code}) - Response: ${body}"
    fi
    ((global_service_counter++))
}

# ==============================================================================
# Main Execution Loop
# ==============================================================================
echo "--- Starting Partition and Service Creation ---"
echo "Workload IPs being used: ${WORKLOAD_IPS[*]}"
start_time=$(date +%s)
end_index=$((START_INDEX + TOTAL_PARTITIONS - 1))
created_count=0
partition_name="global"

for (( n=1; n<=10; n++ )); do
      namespace_name="ns-${n}"
      if create_namespace "$partition_name" "$namespace_name"; then
        for (( s=1; s<=10; s++ )); do
          service_id="workload-${partition_name}-${namespace_name}-${s}"
          node_name="node-${service_id}"
          service_base_name="workload-${s}"
          register_service "$partition_name" "$namespace_name" "$service_id" "$node_name" "$service_base_name"
        done
      fi
    echo "DEBUG: AFTER functions, main loop variable i = ${i}"
  echo "=============================================================================="

  ((created_count++))
  if (( created_count % RATE_PER_SECOND == 0 && created_count > 0 )); then
    echo "--- Batch of ${RATE_PER_SECOND} partitions processed. Waiting for ${BATCH_DELAY}s... ---"
    sleep "$BATCH_DELAY"
  fi
done
end_time=$(date +%s)
echo "--- Script Finished ---"
echo "Total execution time: $((end_time - start_time)) seconds."
