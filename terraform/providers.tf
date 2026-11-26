terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # same state bucket as WeatherApp, own key for this project
  backend "s3" {
    bucket       = "andrei-tf-state-907538072652"
    key          = "python-kafka-mongo/terraform.tfstate"
    region       = "us-west-1"
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region

  # every resource gets these tags - easy to find in the console
  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
    }
  }
}