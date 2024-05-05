locals {
  vpc_az_a                              = "${var.region}a"
  vpc_az_b                              = "${var.region}b"
  vpc_cidr                              = "10.0.0.0/16"
  vpc_public_az_a_subnet_cidr           = "10.0.0.0/24"
  vpc_public_az_a_subnet_app_ip_address = "10.0.0.4"
  vpc_db_az_a_subnet_cidr               = "10.0.11.0/24"
  vpc_db_az_b_subnet_cidr               = "10.0.12.0/24"
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.example.id
  tags = {
    Name = var.name_prefix
  }
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc
resource "aws_vpc" "example" {
  cidr_block = local.vpc_cidr
  tags = {
    Name = var.name_prefix
  }
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet
resource "aws_subnet" "public_az_a" {
  vpc_id            = aws_vpc.example.id
  availability_zone = local.vpc_az_a
  cidr_block        = local.vpc_public_az_a_subnet_cidr
  tags = {
    Name = "${var.name_prefix}-public-az-a"
  }
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.example.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = {
    Name = "${var.name_prefix}-public"
  }
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association
resource "aws_route_table_association" "public_az_a" {
  subnet_id      = aws_subnet.public_az_a.id
  route_table_id = aws_route_table.public.id
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet
resource "aws_subnet" "db_az_a" {
  vpc_id            = aws_vpc.example.id
  availability_zone = local.vpc_az_a
  cidr_block        = local.vpc_db_az_a_subnet_cidr
  tags = {
    Name = "${var.name_prefix}-db-az-a"
  }
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet
resource "aws_subnet" "db_az_b" {
  vpc_id            = aws_vpc.example.id
  availability_zone = local.vpc_az_b
  cidr_block        = local.vpc_db_az_b_subnet_cidr
  tags = {
    Name = "${var.name_prefix}-db-az-b"
  }
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_subnet_group
resource "aws_db_subnet_group" "db" {
  name       = "${var.name_prefix}-db"
  subnet_ids = [aws_subnet.db_az_a.id, aws_subnet.db_az_b.id]
  tags = {
    Name = var.name_prefix
  }
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group
resource "aws_security_group" "db" {
  vpc_id      = aws_vpc.example.id
  name        = "db"
  description = "PostgreSQL Database"
  tags = {
    Name = "${var.name_prefix}-db"
  }
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule
resource "aws_vpc_security_group_ingress_rule" "db_postgresql" {
  security_group_id = aws_security_group.db.id
  ip_protocol       = "tcp"
  cidr_ipv4         = local.vpc_public_az_a_subnet_cidr
  from_port         = 5432
  to_port           = 5432
  tags = {
    Name = "${var.name_prefix}-db-postgresql"
  }
}
