locals {
  # see https://github.com/porsager/postgres/blob/v3.4.4/src/index.js#L535-L557
  example_db_admin_connection_string = format(
    "postgres://%s:%s@%s?sslmode=verify-full",
    urlencode(aws_db_instance.example.username),
    urlencode(aws_db_instance.example.password),
    aws_db_instance.example.endpoint
  )
}

# see https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password
resource "random_password" "example_db_admin_password" {
  length           = 16 # min 8.
  min_lower        = 1
  min_upper        = 1
  min_numeric      = 1
  min_special      = 1
  override_special = "!#$%&*()-_=+[]{}<>:?" # NB cannot contain /'"@
}

# see https://awscli.amazonaws.com/v2/documentation/api/latest/reference/rds/create-db-instance.html
# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_instance
resource "aws_db_instance" "example" {
  availability_zone      = local.vpc_az_a
  db_subnet_group_name   = aws_db_subnet_group.db.name
  vpc_security_group_ids = [aws_security_group.db.id]
  identifier             = var.name_prefix
  engine                 = "postgres"
  engine_version         = "16.2"
  instance_class         = "db.t3.micro"
  username               = "postgres" # NB cannot be admin.
  password               = random_password.example_db_admin_password.result
  storage_type           = "gp2"
  allocated_storage      = 20 # [GiB]. min 20 (for ssd based storage_type).
  skip_final_snapshot    = true
  apply_immediately      = true
  tags = {
    Name = var.name_prefix
  }
}
