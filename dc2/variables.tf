variable "region" {
  description = "AWS region"
   default     = "ap-northeast-3"
}

variable "consul_instance_type" {
  description = "EC2 instance type"
  # default     = "m6i.4xlarge"
  default     = "m5.2xlarge"
}

variable "instance_type" {
  description = "EC2 instance type"
  default     = "m5.2xlarge"
}

variable "retry_join" {
  description = "Used by Consul to automatically form a cluster."
  type        = string
  default     = "provider=aws tag_key=ConsulAutoJoin tag_value=auto-join-0"
}

variable "retry_join_tag" {
  description = "Used by Consul to automatically form a cluster."
  type        = string
  default     = "auto-join-0"
}

variable "name_prefix" {
  description = "Prefix used to name various infrastructure components. Alphanumeric characters only."
  default     = "jpmc-cluster2"
}

variable "consul_version" {
  description = "Consul version to install"
  type        = string
  default     = "1.21.0+ent"
}

variable "envoy_version" {
  description = "Envoy to install"
  type        = string
  default     = "1.33.2-1"
  # default     = "1.27.7"
}

variable "domain_name" {
  description = "Subdomain name for Consul (e.g., consul-dc2.example.com). If provided, HTTPS will be configured."
  type        = string
  default     = ""
}

variable "hosted_zone_name" {
  description = "Route53 hosted zone name (e.g., example.com). Required if domain_name is provided."
  type        = string
  default     = ""
}

variable "enable_consul_alb" {
  description = "Enable Application Load Balancer for Consul cluster"
  type        = bool
  default     = true
}

