variable "region" {
  description = "AWS region for everything"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Name used in all resource names"
  type        = string
  default     = "leaky-pipeline"
}

variable "vpc_cidr" {
  description = "IP range of the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

# ECS version only - Kafka and Mongo now come from operators
# variable "kafka_image" {
#   description = "Official Kafka image (same as docker compose)"
#   type        = string
#   default     = "apache/kafka:4.2.0"
# }
#
# variable "mongo_image" {
#   description = "Official MongoDB image (same as docker compose)"
#   type        = string
#   default     = "mongo:8.0"
# }

variable "domain" {
  description = "Domain with an existing Route 53 hosted zone + wildcard cert (created once, outside Terraform)"
  type        = string
  default     = "mansuraforecast.online"
}

variable "subdomain" {
  description = "The shop lives at <subdomain>.<domain>"
  type        = string
  default     = "shop"
}

variable "cluster_version" {
  description = "Kubernetes version (kept in standard support)"
  type        = string
  default     = "1.36"
}

variable "node_instance_type" {
  description = "EC2 type for the worker nodes (largest free-plan type: 2 vCPU / 8 GB)"
  type        = string
  # default     = "t3.xlarge"
  default = "m7i-flex.large"
}

variable "admin_cidrs" {
  description = "IPs allowed to reach the EKS API (my laptop for kubectl) - set in terraform.tfvars"
  type        = list(string)
}