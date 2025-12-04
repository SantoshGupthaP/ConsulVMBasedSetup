
variable "esm_version" {
  description = "Consul ESM version to install"
  type        = string
  default     = "0.9.0" # "1.6.0"
}

variable "consul_esm_instance_type" {
  description = "EC2 instance type"
  default     = "m6i.4xlarge"
}

variable "node_exporter_version" {
  description = "Node Exporter version for ESM monitoring"
  type        = string
  default     = "1.9.1" #1.8.0. 
}

variable "consul_token" {
  description = "Consul ACL token for ESM node"
  type        = string
  default     = "e95b599e-166e-7d80-08ad-aee76e7ddf19"
}

variable "consul_datacenter" {
  description = "Consul datacenter name"
  type        = string
  default     = "dc1"
}

variable "ping_interval" {
  description = "ESM node probe interval"
  type        = string
  default     = "10s"
}

variable "subnet_ids" {
  description = "List of subnet IDs for ESM deployment"
  type        = list(string)
  default     = []
}