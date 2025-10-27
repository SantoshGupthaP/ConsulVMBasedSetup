output "consul_ui_urls" {
  value = [for i in aws_instance.consul : "http://${i.public_ip}:8500"]
}

output "ssh_to_consul" {
  value = [for i in aws_instance.consul : "ssh -i c1-key.pem ubuntu@${i.public_ip}"]
}

output "ssh_to_mgw" {
  value = [for i in aws_instance.mgw_service : "ssh -i c1-key.pem ubuntu@${i.public_ip}"]
}

output "CONSUL_HTTP_ADDR" {
  value = <<CONFIGURATION
${aws_instance.consul[0].public_ip}:8500
${aws_instance.consul[1].public_ip}:8500
${aws_instance.consul[2].public_ip}:8500
  CONFIGURATION
}

output "grafana_ui_url" {
  description = "Grafana Web UI URL"
  value       = "http://${aws_instance.grafana.public_ip}:3000"
}

output "ssh_to_grafana" {
  description = "SSH command to connect to Grafana EC2 instance"
  value       = "ssh -i c1-key.pem ubuntu@${aws_instance.grafana.public_ip}"
}

# output "grafana_default_login" {
#   description = "Default Grafana login credentials"
#   value       = "Username: admin, Password: admin (unless changed during provisioning)"
# }

output "prometheus_ui_url" {
  description = "Prometheus Web UI URL"
  value       = "http://${aws_instance.prometheus.public_ip}:9090"
}

output "ssh_to_prometheus" {
  description = "SSH command to connect to Prometheus EC2 instance"
  value       = "ssh -i c1-key.pem ubuntu@${aws_instance.prometheus.public_ip}"
}

output "ssh_to_load_generator" {
  description = "SSH command to connect to Load Generator EC2 instance"
  value       = "ssh -i c1-key.pem ubuntu@${aws_instance.load_generator.public_ip}"
}

output "Private_IPs_of_Worker_Nodes" {
  value = [for i in aws_instance.workload : "${i.private_ip}"]
}