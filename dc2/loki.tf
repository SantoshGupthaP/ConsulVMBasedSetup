# Loki Security Group
resource "aws_security_group" "loki_sg" {
  name   = "${var.name_prefix}-loki-sg"
  vpc_id = module.vpc.vpc_id

  # Loki HTTP API
  ingress {
    from_port   = 3100
    to_port     = 3100
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Loki gRPC (for Promtail)
  ingress {
    from_port   = 9096
    to_port     = 9096
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-loki-sg"
  }
}

# Loki EC2 Instance
resource "aws_instance" "loki" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.minion-key.key_name
  associate_public_ip_address = true

  tags = {
    Name = "${var.name_prefix}-loki"
  }

  iam_instance_profile = aws_iam_instance_profile.instance_profile.name

  metadata_options {
    http_endpoint          = "enabled"
    instance_metadata_tags = "enabled"
  }

  vpc_security_group_ids = [aws_security_group.consul_sg.id, aws_security_group.loki_sg.id]
  subnet_id              = module.vpc.public_subnets[0]

  root_block_device {
    volume_size           = 100
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  user_data = templatefile("${path.module}/shared/data-scripts/user-data-loki.sh", {
    loki_version = "2.9.3"
  })

  depends_on = [aws_instance.consul]
}

# Output Loki endpoint
output "loki_endpoint" {
  value       = "http://${aws_instance.loki.public_ip}:3100"
  description = "Loki HTTP endpoint"
}

output "loki_private_ip" {
  value       = aws_instance.loki.private_ip
  description = "Loki private IP for Promtail configuration"
}
