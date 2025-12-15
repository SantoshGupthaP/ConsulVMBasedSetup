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

  user_data = <<-EOF
    #!/bin/bash
    sudo apt-get update
    sudo apt-get install -y wget tar

    # Install Prometheus
    wget https://github.com/prometheus/prometheus/releases/download/v2.52.0/prometheus-2.52.0.linux-amd64.tar.gz
    tar xvf prometheus-2.52.0.linux-amd64.tar.gz
    sudo mv prometheus-2.52.0.linux-amd64/prometheus /usr/local/bin/
    sudo mv prometheus-2.52.0.linux-amd64/promtool /usr/local/bin/
    sudo mkdir -p /etc/prometheus /var/lib/prometheus
    sudo mv prometheus-2.52.0.linux-amd64/consoles /etc/prometheus/
    sudo mv prometheus-2.52.0.linux-amd64/console_libraries /etc/prometheus/

    # Install Consul Exporter
    # wget https://github.com/prometheus-community/consul_exporter/releases/download/v0.11.0/consul_exporter-0.11.0.linux-amd64.tar.gz
    wget https://github.com/prometheus/consul_exporter/releases/download/v0.11.0/consul_exporter-0.11.0.linux-amd64.tar.gz
    tar xvf consul_exporter-0.11.0.linux-amd64.tar.gz
    sudo mv consul_exporter-0.11.0.linux-amd64/consul_exporter /usr/local/bin/

    # Create Prometheus config
    cat <<EOC | sudo tee /etc/prometheus/prometheus.yml
    global:
      scrape_interval: 15s

    scrape_configs:
      - job_name: 'Consul'
        static_configs:
          - targets: ['localhost:9107']
      - job_name: 'Consul-Server0-Node'
        # scrape_offset: 0s, use rule_query_offset instead
        static_configs:
          - targets: [
              "${aws_instance.consul[0].private_ip}:9100"
            ]
      - job_name: 'Consul-Server1-Node'
        # scrape_offset: 5s
        static_configs:
          - targets: [
              "${aws_instance.consul[1].private_ip}:9100"
            ]
      - job_name: 'Consul-Server2-Node'
        # scrape_offset: 10s
        static_configs:
          - targets: [
              "${aws_instance.consul[2].private_ip}:9100"
            ]
      - job_name: 'Consul-ESM-Node'
        static_configs:
          - targets: [
              "${aws_instance.esm[0].private_ip}:9100"
            ]
      - job_name: 'Consul-ESM-Agent'
        static_configs:
          - targets: [
              "${aws_instance.esm[0].private_ip}:8080"
            ]
      - job_name: 'Consul-ESM-Node2'
        static_configs:
          - targets: [
              "${aws_instance.esm[1].private_ip}:9100"
            ]
      - job_name: 'Consul-ESM-Agent2'
        static_configs:
          - targets: [
              "${aws_instance.esm[1].private_ip}:8080"
            ]
      - job_name: 'Consul-ESM-Node3'
        static_configs:
          - targets: [
              "${aws_instance.esm[2].private_ip}:9100"
            ]
      - job_name: 'Consul-ESM-Agent3'
        static_configs:
          - targets: [
              "${aws_instance.esm[2].private_ip}:8080"
            ]
      - job_name: 'Consul-Server0-Agent'
        metrics_path: /v1/agent/metrics
        params:
          format: ['prometheus']
        bearer_token: 'e95b599e-166e-7d80-08ad-aee76e7ddf19'
        static_configs:
          - targets: [
              "${aws_instance.consul[0].private_ip}:8500"
            ]
      - job_name: 'Consul-Server1-Agent'
        metrics_path: /v1/agent/metrics
        params:
          format: ['prometheus']
        bearer_token: 'e95b599e-166e-7d80-08ad-aee76e7ddf19'
        static_configs:
          - targets: [
              "${aws_instance.consul[1].private_ip}:8500"
            ]
      - job_name: 'Consul-Server2-Agent'
        metrics_path: /v1/agent/metrics
        params:
          format: ['prometheus']
        bearer_token: 'e95b599e-166e-7d80-08ad-aee76e7ddf19'
        static_configs:
          - targets: [
              "${aws_instance.consul[2].private_ip}:8500"
            ]
    EOC

    # Create systemd service for Prometheus
    cat <<EOP | sudo tee /etc/systemd/system/prometheus.service
    [Unit]
    Description=Prometheus
    After=network.target

    [Service]
    User=root
    ExecStart=/usr/local/bin/prometheus --config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/var/lib/prometheus --storage.tsdb.retention.time=15d --storage.tsdb.retention.size=20GB
    Restart=always

    [Install]
    WantedBy=multi-user.target
    EOP

    # Create systemd service for Consul Exporter
    cat <<EOE | sudo tee /etc/systemd/system/consul_exporter.service
    [Unit]
    Description=Consul Exporter
    After=network.target

    [Service]
    User=root
    # Add the token as an environment variable
    Environment="CONSUL_HTTP_TOKEN=e95b599e-166e-7d80-08ad-aee76e7ddf19"
    ExecStart=/usr/local/bin/consul_exporter --consul.server=http://${aws_instance.consul[0].private_ip}:8500
    Restart=always

    [Install]
    WantedBy=multi-user.target
    EOE

    sudo systemctl daemon-reload
    sudo systemctl enable prometheus
    sudo systemctl start prometheus
    sudo systemctl enable consul_exporter
    sudo systemctl start consul_exporter
  EOF
}

// ...existing code...