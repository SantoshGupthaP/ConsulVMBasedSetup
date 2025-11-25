variable "region" {
  description = "AWS region"
  default     = "ap-south-1"
}

variable "consul_instance_type" {
  description = "EC2 instance type"
  # default     = "m6i.4xlarge"
  default = "m5.2xlarge"
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
  default     = "jpmc-cluster1"
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

