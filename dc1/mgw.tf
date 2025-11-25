# resource "aws_instance" "mgw_service" {
#   count = 2
#   depends_on = [aws_instance.consul]
#   ami                    = data.aws_ami.ubuntu.id
#   instance_type          = var.consul_instance_type
#   key_name              = aws_key_pair.minion-key.key_name
#   associate_public_ip_address = true

#   tags = merge(
#     {
#         "Name" = "${var.name_prefix}-mesh-gateway-${count.index + 1}"
#         # "Name" = "cluster1-mesh-gateway"
#     },
#     {
#       "ConsulAutoJoin" = var.retry_join_tag
#     },
#     {
#       "NomadType" = "client"
#     },
#     {
#       "Type" = "mesh-gateway"
#       "Cluster" = "cluster1"
#     }
#   )

#   root_block_device {
#     volume_size = 30         # Set to 300 or 500 as needed
#     volume_type = "gp3"       # gp3 is recommended for new workloads
#     delete_on_termination = true
#     encrypted = true
#   }

#   iam_instance_profile = aws_iam_instance_profile.instance_profile.name

#   metadata_options {
#     http_endpoint          = "enabled"
#     instance_metadata_tags = "enabled"
#   }

#   provisioner "file" {
#     source      = "${path.module}/shared"
#     destination = "/tmp"
#   }
#     connection {
#       type        = "ssh"
#       user        = "ubuntu"
#       private_key = tls_private_key.pk.private_key_pem
#       host        = self.public_ip
#     }


#   user_data = templatefile("${path.module}/shared/data-scripts/user-data-client.sh", {
#     region               = var.region
#     cloud_env            = "aws"
#     retry_join           = var.retry_join
#     CLUSTER_PREFIX       = var.name_prefix
#     consul_version = var.consul_version
#     envoy_version = var.envoy_version
#     application_name   = "mgw-service"
#   })

#   vpc_security_group_ids = [aws_security_group.consul_sg.id]
#   subnet_id = module.vpc.public_subnets[count.index % length(module.vpc.public_subnets)]
# }
