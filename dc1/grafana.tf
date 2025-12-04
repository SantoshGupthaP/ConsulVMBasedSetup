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

# Grafana EC2 instance
resource "aws_instance" "grafana" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.minion-key.key_name
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
    consul_private_ip     = aws_instance.consul[0].private_ip
    prometheus_private_ip = aws_instance.prometheus.private_ip
    loki_private_ip       = aws_instance.loki.private_ip
  })

  depends_on = [aws_instance.consul, aws_instance.prometheus, aws_instance.loki]
}

# Grafana Provider Configuration
provider "grafana" {
  url  = "http://${aws_instance.grafana.public_ip}:3000"
  auth = "admin:admin" # Default credentials - should be changed in production
}

# Wait for Grafana to be ready
resource "time_sleep" "wait_for_grafana" {
  depends_on      = [aws_instance.grafana]
  create_duration = "120s" # Wait for Grafana to initialize
}

# Create Prometheus data source
resource "grafana_data_source" "prometheus" {
  type = "prometheus"
  name = "Prometheus-1"
  url  = "http://${aws_instance.prometheus.private_ip}:9090"
  
  is_default = true

  json_data_encoded = jsonencode({
    httpMethod    = "GET"
    timeInterval  = "15s"
  })

  depends_on = [time_sleep.wait_for_grafana]
}

# Create ESM Dashboard
resource "grafana_dashboard" "esm_dashboard" {
  config_json = templatefile("${path.module}/shared/config/esm-dashboard.json", {
    datasource_uid = grafana_data_source.prometheus.uid
  })

  depends_on = [grafana_data_source.prometheus]
}

// ...existing code...