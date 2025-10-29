terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.0"  # Use stable version
    }
  }
}

provider "aws" {
  region = var.region
}

# create vpc
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "${var.name_prefix}-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["ap-south-1a", "ap-south-1b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.3.0/24", "10.0.4.0/24"]

  enable_nat_gateway   = true
  enable_vpn_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true
}

resource "aws_security_group" "consul_sg" {
  name   = "${var.name_prefix}-sg"
  vpc_id = module.vpc.vpc_id

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Consul
  ingress {
    from_port       = 8500
    to_port         = 8500
    protocol        = "tcp"
    cidr_blocks     = ["0.0.0.0/0"]
  }

  # hello-service
  ingress {
    from_port       = 5050
    to_port         = 5050
    protocol        = "tcp"
    cidr_blocks     = ["0.0.0.0/0"]
  }

  # response-service
  ingress {
    from_port       = 6060
    to_port         = 6060
    protocol        = "tcp"
    cidr_blocks     = ["0.0.0.0/0"]
  }

  # api-gw/mgw-service
  ingress {
    from_port       = 8443
    to_port         = 8443
    protocol        = "tcp"
    cidr_blocks     = ["0.0.0.0/0"]
  }

  # envoy admin
  ingress {
    from_port       = 19000
    to_port         = 19000
    protocol        = "tcp"
    cidr_blocks     = ["0.0.0.0/0"]
  }

  # allow_all_internal_traffic
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# use ubuntu 22.04 ami
data "aws_ami" "ubuntu" {
  most_recent = true

  owners = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# Add EC2 instance for Consul
resource "aws_instance" "consul" {
  count = 3
  instance_type = var.consul_instance_type
  ami = data.aws_ami.ubuntu.id
  key_name      = aws_key_pair.minion-key.key_name
  associate_public_ip_address = true    # Enable public IP

  # instance tags
  # ConsulAutoJoin is necessary for nodes to automatically join the cluster
  tags = merge(
    {
      "Name" = "${var.name_prefix}-consul-service-${count.index + 1}"
    },
    {
      "ConsulAutoJoin" = var.retry_join_tag
    },
    {
      "NomadType" = "client"
    }
  )

  root_block_device {
    volume_size = 300         # Set to 300 or 500 as needed
    volume_type = "gp3"       # gp3 is recommended for new workloads
    delete_on_termination = true
    encrypted = true
  }

  iam_instance_profile = aws_iam_instance_profile.instance_profile.name

  # Enables access to the metadata endpoint (http://169.254.169.254).
  metadata_options {
    http_endpoint          = "enabled"
    instance_metadata_tags = "enabled"
  }

  # copy files from ./shared to /ops with private key permissions
  provisioner "file" {
    source      = "${path.module}/shared"
    destination = "/tmp"
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = tls_private_key.pk.private_key_pem
    host        = self.public_ip
  }

  user_data = templatefile("${path.module}/shared/data-scripts/user-data-server.sh", {
    server_count              = 3
    region                    = var.region
    cloud_env                 = "aws"
    retry_join                = var.retry_join
    consul_version = var.consul_version
    envoy_version = var.envoy_version
    application_name          = "${var.name_prefix}-consul-server"
  })

  vpc_security_group_ids = [aws_security_group.consul_sg.id]
  # associate the public subnet with the instance
  subnet_id = module.vpc.public_subnets[0]
}

resource "aws_security_group" "load_generator" {
  name   = "${var.name_prefix}-load-generator-sg"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # Add other ports as needed for your testing
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "load_generator" {
  ami                    = data.aws_ami.ubuntu.id # data.aws_ami.amazon_linux.id
  instance_type          = "t3.large"
  key_name               = aws_key_pair.minion-key.key_name
  subnet_id              = module.vpc.public_subnets[0]
  vpc_security_group_ids = [aws_security_group.load_generator.id]
  associate_public_ip_address = true

  # Simple user data to just install the Consul CLI

  user_data = templatefile("${path.module}/shared/data-scripts/user-data-loadgenerator.sh.tpl", {
    consul_version = var.consul_version
    CONSUL_IP = aws_instance.consul[0].private_ip
  })

  # copy files from ./shared to /ops with private key permissions
  provisioner "file" {
    source      = "${path.module}/shared/load-scripts"
    destination = "/tmp"
  }
  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = tls_private_key.pk.private_key_pem
    host        = self.public_ip
  }

  tags = {
    Name = "${var.name_prefix}-load-generator"
  }
}

resource "aws_iam_instance_profile" "instance_profile" {
  name_prefix = var.name_prefix
  role        = aws_iam_role.instance_role.name
}

resource "aws_iam_role" "instance_role" {
  name_prefix        = var.name_prefix
  assume_role_policy = data.aws_iam_policy_document.instance_role.json
}

data "aws_iam_policy_document" "instance_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "auto_discover_cluster" {
  name   = "${var.name_prefix}-auto-discover-cluster"
  role   = aws_iam_role.instance_role.id
  policy = data.aws_iam_policy_document.auto_discover_cluster.json
}

data "aws_iam_policy_document" "auto_discover_cluster" {
  statement {
    effect = "Allow"

    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeTags",
      "autoscaling:DescribeAutoScalingGroups",
    ]

    resources = ["*"]
  }
}

# generate a new key pair
resource "tls_private_key" "pk" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "minion-key" {
  key_name   = "c1-key-1"
  public_key = tls_private_key.pk.public_key_openssh
}

resource "local_file" "minion-key" {
  content         = tls_private_key.pk.private_key_pem
  filename        = "./c1-key.pem"
  file_permission = "0400"
}
