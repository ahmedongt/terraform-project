# ====================================================================
# PHASE 1: HARDENED ENTERPRISE NETWORK BACKBONE
# ====================================================================

resource "aws_vpc" "custom_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "custom-vpc-lab" }
}

# --- PUBLIC NETWORKING TIER (For ALB & NAT Gateway) ---
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.custom_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags                    = { Name = "public-subnet-1a" }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.custom_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
  tags                    = { Name = "public-subnet-1b" }
}

# --- PRIVATE NETWORKING TIER (For Hidden App Instances) ---
resource "aws_subnet" "private_1" {
  vpc_id                  = aws_vpc.custom_vpc.id
  cidr_block              = "10.0.10.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = false
  tags                    = { Name = "private-subnet-1a" }
}

resource "aws_subnet" "private_2" {
  vpc_id                  = aws_vpc.custom_vpc.id
  cidr_block              = "10.0.20.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = false
  tags                    = { Name = "private-subnet-1b" }
}

# --- INTERNET GATEWAY ROUTING ---
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.custom_vpc.id
  tags   = { Name = "custom-vpc-igw" }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.custom_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "public-route-table" }
}

resource "aws_route_table_association" "public_1_assoc" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_2_assoc" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public_rt.id
}

# --- NAT GATEWAY ROUTING (Outbound Gateway for Private Subnets) ---
resource "aws_eip" "nat_eip" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]
  tags       = { Name = "nat-gateway-static-eip" }
}

resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_1.id  # Placed in public subnet to reach the IGW
  tags          = { Name = "vpc-secure-nat-gateway" }
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.custom_vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }
  tags = { Name = "private-route-table" }
}

resource "aws_route_table_association" "private_1_assoc" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "private_2_assoc" {
  subnet_id      = aws_subnet.private_2.id
  route_table_id = aws_route_table.private_rt.id
}