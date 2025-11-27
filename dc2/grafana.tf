// ...existing code...

# Add Grafana port to security group
# resource "aws_security_group_rule" "grafana_ingress" {
#   type              = "ingress"
#   from_port         = 3000
#   to_port           = 3000
#   protocol          = "tcp"
#   cidr_blocks       = ["0.0.0.0/0"]
#   security_group_id = aws_security_group.consul_sg.id
# }

resource "aws_security_group" "grafana_sg" {
  name   = "${var.name_prefix}-prometheus-sg"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port   = 3000
    to_port     = 3000
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

# # Grafana EC2 instance
resource "aws_instance" "grafana" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.minion-key.key_name
  associate_public_ip_address = true

  tags = {
    Name = "${var.name_prefix}-grafana"
  }

  iam_instance_profile = aws_iam_instance_profile.instance_profile.name

  metadata_options {
    http_endpoint          = "enabled"
    instance_metadata_tags = "enabled"
  }

  vpc_security_group_ids = [aws_security_group.consul_sg.id, aws_security_group.grafana_sg.id]
  subnet_id              = module.vpc.public_subnets[0]

  user_data = templatefile("${path.module}/shared/data-scripts/user-data-grafana.sh", {
    prometheus_private_ip = aws_instance.prometheus.private_ip
    loki_private_ip       = aws_instance.loki.private_ip
  })

  depends_on = [aws_instance.prometheus, aws_instance.loki]
}

// ...existing code...