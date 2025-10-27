
# Define a security group for the workload instances
resource "aws_security_group" "workload" {
  name        = "workload-sg"
  description = "Allow health check traffic from ESM"
  vpc_id      = module.vpc.vpc_id # Use the VPC ID of your existing cluster

  # Allow HTTP traffic on port 8080 from your ESM instance's security group
  ingress {
    description     = "Health Check from ESM"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.esm.id] # IMPORTANT: Use the SG ID of your ESM instance
  }

  # Allow SSH from your IP
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description     = "Allow ICMP (ping) from ESM"
    protocol        = "icmp"
    from_port       = -1 # For ICMP, -1 means "all types"
    to_port         = -1 # For ICMP, -1 means "all codes"
    security_groups = [aws_security_group.esm.id]
  }
  # ---

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "workload" {
  count                  = 5
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.minion-key.key_name
  subnet_id              = module.vpc.public_subnets[0]
  vpc_security_group_ids = [aws_security_group.workload.id]

  associate_public_ip_address = true
  user_data = file("${path.module}/shared/data-scripts/user-data-workload.sh")
  tags = {
    Name = "${var.name_prefix}-workload-${count.index + 1}"
  }
}