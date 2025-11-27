# Application Load Balancer for Consul Cluster
resource "aws_security_group" "consul_alb_sg" {
  name        = "${var.name_prefix}-consul-alb-sg"
  description = "Security group for Consul ALB"
  vpc_id      = module.vpc.vpc_id

  # HTTP access for Consul UI
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP access"
  }

  # HTTPS access for Consul UI
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS access"
  }

  # Direct Consul access (when domain not configured)
  ingress {
    from_port   = 8500
    to_port     = 8500
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Consul HTTP API access"
  }

  # Consul gRPC for peering
  ingress {
    from_port   = 8503
    to_port     = 8503
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Consul gRPC peering"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-consul-alb-sg"
  }
}

# Target Group for Consul HTTP API/UI
resource "aws_lb_target_group" "consul_http" {
  name     = "${var.name_prefix}-consul-http-tg"
  port     = 8500
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    enabled             = true
    path                = "/v1/status/leader"
    protocol            = "HTTP"
    port                = "8500"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }

  deregistration_delay = 30

  tags = {
    Name = "${var.name_prefix}-consul-http-tg"
  }
}

# Register Consul servers with target group
resource "aws_lb_target_group_attachment" "consul_http" {
  count            = 3
  target_group_arn = aws_lb_target_group.consul_http.arn
  target_id        = aws_instance.consul[count.index].id
  port             = 8500
}

# Application Load Balancer
resource "aws_lb" "consul" {
  name               = "${var.name_prefix}-consul-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.consul_alb_sg.id]
  subnets            = module.vpc.public_subnets

  enable_deletion_protection = false
  enable_http2              = true

  tags = {
    Name = "${var.name_prefix}-consul-alb"
  }
}

# Route53 and ACM certificate configuration for custom domain

data "aws_route53_zone" "main" {
  count = var.domain_name != "" && var.hosted_zone_name != "" ? 1 : 0
  name  = var.hosted_zone_name
}

resource "aws_acm_certificate" "consul" {
  count             = var.domain_name != "" ? 1 : 0
  domain_name       = var.domain_name
  validation_method = "DNS"

  tags = {
    Name = "${var.name_prefix}-consul-cert"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = var.domain_name != "" ? {
    for dvo in aws_acm_certificate.consul[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main[0].zone_id
}

resource "aws_acm_certificate_validation" "consul" {
  count                   = var.domain_name != "" ? 1 : 0
  certificate_arn         = aws_acm_certificate.consul[0].arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

resource "aws_lb_listener" "consul_https" {
  count             = var.domain_name != "" ? 1 : 0
  load_balancer_arn = aws_lb.consul.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = aws_acm_certificate.consul[0].arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.consul_http.arn
  }

  depends_on = [aws_acm_certificate_validation.consul]
}

# HTTP listener redirects to HTTPS when domain is configured
resource "aws_lb_listener" "consul_http" {
  count             = var.domain_name != "" ? 1 : 0
  load_balancer_arn = aws_lb.consul.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_route53_record" "consul" {
  count   = var.domain_name != "" ? 1 : 0
  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.consul.dns_name
    zone_id                = aws_lb.consul.zone_id
    evaluate_target_health = true
  }
}

# Target Group for Consul gRPC (for peering)
resource "aws_lb_target_group" "consul_grpc" {
  name     = "${var.name_prefix}-consul-grpc-tg"
  port     = 8503
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    enabled             = true
    path                = "/v1/status/leader"
    protocol            = "HTTP"
    port                = "8500"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }

  deregistration_delay = 30

  tags = {
    Name = "${var.name_prefix}-consul-grpc-tg"
  }
}

# Register Consul servers with gRPC target group
resource "aws_lb_target_group_attachment" "consul_grpc" {
  count            = 3
  target_group_arn = aws_lb_target_group.consul_grpc.arn
  target_id        = aws_instance.consul[count.index].id
  port             = 8503
}

# Port 8500 listener for Consul API (always enabled)
resource "aws_lb_listener" "consul_api" {
  load_balancer_arn = aws_lb.consul.arn
  port              = "8500"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.consul_http.arn
  }
}

# Port 8503 listener for Consul gRPC peering (always enabled)
resource "aws_lb_listener" "consul_grpc" {
  load_balancer_arn = aws_lb.consul.arn
  port              = "8503"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.consul_grpc.arn
  }
}

# Outputs
output "consul_alb_dns" {
  value       = aws_lb.consul.dns_name
  description = "DNS name of the Consul ALB"
}

output "consul_alb_url" {
  value       = "http://${aws_lb.consul.dns_name}:8500"
  description = "URL to access Consul UI via ALB"
}

output "consul_alb_zone_id" {
  value       = aws_lb.consul.zone_id
  description = "Zone ID of the Consul ALB for Route53"
}

output "consul_url" {
  value       = var.domain_name != "" ? "https://${var.domain_name}" : "http://${aws_lb.consul.dns_name}:8500"
  description = "Primary URL to access Consul UI (HTTPS with custom domain if configured, otherwise HTTP via ALB)"
}
