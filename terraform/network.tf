# the 2 availability zones we use (ALB needs at least 2)
data "aws_availability_zones" "available" {
  state = "available"
}

# the private network for the whole project
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true # needed so the apps can find each other by name (kafka.shop.local)
  enable_dns_hostnames = true

  tags = { Name = "${var.project}-vpc" }
}

# the door between the VPC and the internet
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${var.project}-igw" }
}

# 2 public subnets: 10.0.1.0/24 in AZ a, 10.0.2.0/24 in AZ b
resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 1)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = { Name = "${var.project}-public-${count.index + 1}" }
}

# send all internet traffic through the internet gateway
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.project}-public-rt" }
}

# attach the route table to both subnets
resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}