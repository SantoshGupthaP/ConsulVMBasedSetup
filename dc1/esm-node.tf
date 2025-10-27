locals {
  name_prefix = "${var.name_prefix}-consul-esm"
  esm_config = {
    log_level       = "INFO"
    enable_syslog   = false

    # Basic ESM settings
    node_reconnect_timeout = "72h"
    node_probe_interval = var.ping_interval
    http_addr = "0.0.0.0:8080"
    disable_coordinate_updates = false
    instance_id = "consul-esm-${var.name_prefix}"

    # Consul connection configuration
    consul = {
      # address    = "consul.${var.consul_domain}:8500"
      address    = "${aws_instance.consul[0].private_ip}:8500"
      token      = var.consul_token
      datacenter = var.consul_datacenter
    }

    # Service registration
    service = {
      name = "consul-esm"
      tag  = "external-service-monitor"
    }

    # External node metadata - Using standard ESM detection keys
    external_node_meta = {
      "external-node" = "true"      # Standard ESM detection key
      "external-probe" = "true"     # Enable ESM node health probing
    }

    # Telemetry configuration
    telemetry = {
      disable_hostname = true
      prometheus_retention_time = "60s"
    }
  }
}

# IAM role for ESM instance
resource "aws_iam_role" "esm" {
  name = "${local.name_prefix}-role-singlepartitiontest30s"

  assume_role_policy = jsonencode({
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# IAM instance profile
resource "aws_iam_instance_profile" "esm" {
  name = "${local.name_prefix}-profile"
  role = aws_iam_role.esm.name
}

# Allow SSM access for remote management
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.esm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# # Allow CloudWatch agent access
# resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
#   role       = aws_iam_role.esm.name
#   policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
# }

# # Allow CloudWatch logs access
# resource "aws_iam_role_policy_attachment" "cloudwatch_logs" {
#   role       = aws_iam_role.esm.name
#   policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
# }

# Add IAM policy for reading SSM parameters
resource "aws_iam_role_policy" "ssm_parameters" {
  name = "${local.name_prefix}-ssm-parameters"
  role = aws_iam_role.esm.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = [
          aws_ssm_parameter.esm_config.arn
        ]
      }
    ]
  })
}

# Security group for ESM
resource "aws_security_group" "esm" {
  name_prefix = "${local.name_prefix}-sg-singlepartitiontest30s"
  vpc_id      = module.vpc.vpc_id

  # Allow all traffic from VPC for debugging
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all TCP traffic from private networks"
  }

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all UDP traffic from private networks"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "${local.name_prefix}-sg"
  }
}

# Create ESM configuration
resource "aws_ssm_parameter" "esm_config" {
  name  = "/${var.name_prefix}-consul/esm/config"
  type  = "SecureString"
  value = jsonencode(local.esm_config)
}

# # Launch template for ESM
# resource "aws_launch_template" "esm" {
#   name_prefix   = "${local.name_prefix}-lt"
#   image_id      = data.aws_ami.ubuntu.id
#   instance_type = var.instance_type

#   key_name = aws_key_pair.minion-key.key_name

#   network_interfaces {
#     associate_public_ip_address = true
#     security_groups             = [aws_security_group.esm.id]
#   }

#   iam_instance_profile {
#     name = aws_iam_instance_profile.esm.name
#   }

#   user_data = base64encode(templatefile("${path.module}/shared/data-scripts/user-data-esm.sh.tpl", {
#     esm_version           = var.esm_version
#     node_exporter_version = var.node_exporter_version
#     consul_address = aws_instance.consul[0].private_ip
#    # region                = data.aws_region.current.name  # not used
#     #consul_domain         = var.consul_domain
#     consul_token          = var.consul_token
#     consul_datacenter     = var.consul_datacenter   # is it mandatory/necessary ?
#     ping_interval         = var.ping_interval
#     environment           = var.name_prefix     # is it mandatory/necessary ?
#   }))

#   tag_specifications {
#     resource_type = "instance"
#     tags = {
#       Name = "${local.name_prefix}-instance"
#     }
#   }
# }

# # Auto Scaling Group for ESM
# resource "aws_autoscaling_group" "esm" {
#   name_prefix         = "${local.name_prefix}-asg"
#   desired_capacity    = 1
#   max_size            = 1
#   min_size            = 1
#   target_group_arns   = []
#   vpc_zone_identifier = module.vpc.private_subnets

#   launch_template {
#     id      = aws_launch_template.esm.id
#     version = "$Latest"
#   }

#   tag {
#     key                 = "Name"
#     value               = "${local.name_prefix}-instance"
#     propagate_at_launch = true
#   }
# }

# Launch instance for ESM
resource "aws_instance" "esm" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.consul_instance_type
  count = 3
  key_name               = aws_key_pair.minion-key.key_name
  subnet_id              = module.vpc.public_subnets[0]
  vpc_security_group_ids = [aws_security_group.esm.id]
  associate_public_ip_address = true

  iam_instance_profile   = aws_iam_instance_profile.esm.name
  depends_on = [ aws_instance.consul ]
  user_data = templatefile("${path.module}/shared/data-scripts/user-data-esm.sh.tpl", {
    esm_version           = var.esm_version
    node_exporter_version = var.node_exporter_version
    consul_address        = aws_instance.consul[0].private_ip
    consul_token          = var.consul_token
    consul_datacenter     = var.consul_datacenter
    ping_interval         = var.ping_interval
    environment           = var.name_prefix
    instanceid           = "consul-esm-${count.index}"
  })

  tags = {
    Name = "${local.name_prefix}-instance"
  }

  root_block_device {
    volume_size = 300         # Set to 300 or 500 as needed
    volume_type = "gp3"       # gp3 is recommended for new workloads
    delete_on_termination = true
    encrypted = true
  }
}
# Current region data source
data "aws_region" "current" {} 

# data "aws_instances" "esm" {
#   instance_tags = {
#     #Name = "${var.name_prefix}-consul-esm-instance"
#     Name = "${local.name_prefix}-instance"
#   }
#   filter {
#     name   = "instance-state-name"
#     values = ["running"]
#   }
#   depends_on = [aws_autoscaling_group.esm]
# }
