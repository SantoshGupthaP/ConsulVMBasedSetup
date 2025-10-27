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

  user_data = <<-EOF
    #!/bin/bash
    sudo apt-get update
    sudo apt-get install -y apt-transport-https software-properties-common wget
    wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add -
    echo "deb https://packages.grafana.com/oss/deb stable main" | sudo tee /etc/apt/sources.list.d/grafana.list
    sudo apt-get update
    sudo apt-get install -y grafana

    sudo systemctl enable grafana-server
    sudo systemctl start grafana-server

    # Install Consul datasource plugin (optional, for advanced dashboards)
    # sudo grafana-cli plugins install grafana-consul-datasource
    # sudo systemctl restart grafana-server

    # Configure Consul datasource via provisioning (recommended)
    sudo mkdir -p /etc/grafana/provisioning/datasources
    cat <<EOD | sudo tee /etc/grafana/provisioning/datasources/consul.yaml
    apiVersion: 1
    datasources:
      - name: Consul
        type: grafana-consul-datasource
        access: proxy
        url: http://${aws_instance.consul[0].private_ip}:8500
        isDefault: false
    EOD

    sudo systemctl restart grafana-server
  EOF
}

// ...existing code...