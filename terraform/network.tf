# 3 AZs - one Kafka broker / Mongo member / node in each
# use1-az3 is skipped: EKS can't place its control plane there
data "aws_availability_zones" "available" {
  state            = "available"
  exclude_zone_ids = ["use1-az3"]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "${var.project}-vpc"
  cidr = var.vpc_cidr
  azs  = slice(data.aws_availability_zones.available.names, 0, 3)

  # public: ALB + NAT only
  public_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  # private: EKS nodes + pods (big, every pod gets a VPC IP)
  private_subnets = ["10.0.16.0/20", "10.0.32.0/20", "10.0.48.0/20"]

  # one NAT for all private subnets - saves cost, tradeoff: if its AZ dies nodes lose outbound internet
  enable_nat_gateway = true
  single_nat_gateway = true

  enable_dns_hostnames = true

  # tell the AWS Load Balancer Controller where it may put load balancers
  public_subnet_tags  = { "kubernetes.io/role/elb" = 1 }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = 1 }
}