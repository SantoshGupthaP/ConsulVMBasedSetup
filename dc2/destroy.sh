#!/bin/bash
# Proper destroy script to handle Consul provider resources before AWS infrastructure

set -e

echo "Step 1: Destroying Consul config entries first..."
terraform destroy \
  -target=consul_config_entry.mesh \
  -target=consul_config_entry.mesh_default \
  -target=consul_admin_partition.global \
  -var-file=variables.hcl \
  -auto-approve

echo ""
echo "Step 2: Destroying all remaining resources..."
terraform destroy -var-file=variables.hcl -auto-approve

echo ""
echo "Destroy complete!"
