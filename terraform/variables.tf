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

variable "kafka_image" {
  description = "Official Kafka image (same as docker compose)"
  type        = string
  default     = "apache/kafka:4.2.0"
}

variable "mongo_image" {
  description = "Official MongoDB image (same as docker compose)"
  type        = string
  default     = "mongo:8.0"
}

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