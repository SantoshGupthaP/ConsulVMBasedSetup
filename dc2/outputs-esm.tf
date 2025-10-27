# output "esm_instance_id" {
#   description = "ID of the ESM EC2 instance"
#   value       = aws_autoscaling_group.esm.id
# }

# output "esm_config_ssm_parameter" {
#   description = "SSM Parameter name for ESM config"
#   value       = aws_ssm_parameter.esm_config.name
# }


# output "esm_instance_public_ips" {
#   description = "Public IPs of ESM EC2 instances"
#   value       = data.aws_instance.esm.public_ips
# }

# output "esm_instance_private_ips" {
#   description = "Private IPs of ESM EC2 instances"
#   value       = data.aws_instances.esm.private_ips
# }

# output "ssh_to_esm" {
#   description = "SSH command to connect to ESM EC2 instance(s)"
#   value = [for ip in aws_instances.esm.public_ips : "ssh -i c1-key.pem ubuntu@${ip}"]
# }

# output "esm_address" {
#   value = aws_instance.esm[0].public_ip
# }

# output "consul_token" {
#   value = var.consul_token
# }

output "ssh_to_esm" {
  description = "SSH command to connect to the ESM EC2 instance"
  value       = "ssh -i c1-key.pem ubuntu@${aws_instance.esm[0].public_ip}"
}

output "ssh_to_workload" {
  description = "SSH commands to connect to workload EC2 instances"
  value = [
    for i in aws_instance.workload :
    "ssh -i c1-key.pem ubuntu@${i.public_ip}"
  ]
}