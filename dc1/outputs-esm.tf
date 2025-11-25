output "ssh_to_esm" {
  description = "SSH command to connect to the ESM EC2 instance"
  value = [
    for i in aws_instance.esm :
    "ssh -i c1-key.pem ubuntu@${i.public_ip}"
  ]
}

output "ssh_to_workload" {
  description = "SSH commands to connect to workload EC2 instances"
  value = [
    for i in aws_instance.workload :
    "ssh -i c1-key.pem ubuntu@${i.public_ip}"
  ]
}