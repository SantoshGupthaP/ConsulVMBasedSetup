// ...existing code...

# Add Prometheus port to security group
# resource "aws_security_group_rule" "prometheus_ingress" {
#   type              = "ingress"
#   from_port         = 9090
#   to_port           = 9090
#   protocol          = "tcp"
#   cidr_blocks       = ["0.0.0.0/0"]
#   security_group_id = aws_security_group.consul_sg.id
# }

resource "aws_security_group" "prometheus_sg" {
  name   = "${var.name_prefix}-prom-sg"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Add other ingress rules as needed

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# # # Prometheus EC2 instance
resource "aws_instance" "prometheus" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.minion-key.key_name
  associate_public_ip_address = true
  depends_on = [
    aws_instance.consul,
    aws_instance.esm
  ]
  tags = {
    Name = "${var.name_prefix}-prometheus"
  }

  iam_instance_profile = aws_iam_instance_profile.instance_profile.name

  metadata_options {
    http_endpoint          = "enabled"
    instance_metadata_tags = "enabled"
  }

  vpc_security_group_ids = [aws_security_group.consul_sg.id, aws_security_group.prometheus_sg.id]
  subnet_id              = module.vpc.public_subnets[0]

  # Increase disk space to prevent running out of storage
  root_block_device {
    volume_size           = 30  # Increased from default 8GB to 30GB
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  user_data = templatefile("${path.module}/shared/data-scripts/user-data-prometheus.sh.tpl", {
    consul_server_0_ip = aws_instance.consul[0].private_ip
    consul_server_1_ip = aws_instance.consul[1].private_ip
    consul_server_2_ip = aws_instance.consul[2].private_ip
    consul_token       = var.consul_token
    esm_node_configs = join("", [
      for idx in range(length(aws_instance.esm)) :
      "  - job_name: 'Consul-ESM-Node${idx}'\n    static_configs:\n      - targets: ['${aws_instance.esm[idx].private_ip}:9100']\n"
    ])
    esm_agent_configs = join("", [
      for idx in range(length(aws_instance.esm)) :
      "  - job_name: 'Consul-ESM-Agent${idx}'\n    static_configs:\n      - targets: ['${aws_instance.esm[idx].private_ip}:8080']\n"
    ])
  })
}

// ...existing code...