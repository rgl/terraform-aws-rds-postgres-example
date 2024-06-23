# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity
data "aws_caller_identity" "current" {}

# also see https://cloud-images.ubuntu.com/locator/ec2/
# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical.
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/key_pair
resource "aws_key_pair" "admin" {
  key_name   = "${var.name_prefix}-app-admin"
  public_key = var.admin_ssh_key_data
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_interface
resource "aws_network_interface" "app" {
  subnet_id       = aws_subnet.public_az_a.id
  private_ips     = [local.vpc_public_az_a_subnet_app_ip_address]
  security_groups = [aws_security_group.app.id]
  tags = {
    Name = "${var.name_prefix}-app"
  }
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip
resource "aws_eip" "app" {
  domain                    = "vpc"
  associate_with_private_ip = aws_network_interface.app.private_ip
  instance                  = aws_instance.app.id
  depends_on                = [aws_internet_gateway.main]
  tags = {
    Name = "${var.name_prefix}-app"
  }
}

# NB the guest firewall is also configured by provision-firewall.sh.
# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group
resource "aws_security_group" "app" {
  vpc_id      = aws_vpc.example.id
  name        = "app"
  description = "Application"
  tags = {
    Name = "${var.name_prefix}-app"
  }
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule
resource "aws_vpc_security_group_ingress_rule" "app_ssh" {
  security_group_id = aws_security_group.app.id
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 22
  to_port           = 22
  tags = {
    Name = "${var.name_prefix}-app-ssh"
  }
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule
resource "aws_vpc_security_group_ingress_rule" "app_http" {
  security_group_id = aws_security_group.app.id
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  tags = {
    Name = "${var.name_prefix}-app-http"
  }
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule
resource "aws_vpc_security_group_egress_rule" "app_all" {
  security_group_id = aws_security_group.app.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  tags = {
    Name = "${var.name_prefix}-app-all"
  }
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role
resource "aws_iam_role" "app" {
  name = "${var.name_prefix}-app"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment
resource "aws_iam_role_policy_attachment" "app" {
  role       = aws_iam_role.app.name
  policy_arn = aws_iam_policy.app.arn
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy
resource "aws_iam_policy" "app" {
  name = "${var.name_prefix}-app"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ssm:GetParameters",
          "ssm:GetParameter",
        ]
        Resource = "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/${aws_iam_instance_profile.app.role}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:DescribeParameters"]
        Resource = "*"
      }
    ]
  })
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile
resource "aws_iam_instance_profile" "app" {
  name = "${var.name_prefix}-app"
  role = aws_iam_role.app.name
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter
resource "aws_ssm_parameter" "app_postgres_secret" {
  name  = "/${aws_iam_instance_profile.app.role}/secret/postgres"
  type  = "SecureString"
  value = local.example_db_admin_connection_string
}

# see https://registry.terraform.io/providers/hashicorp/cloudinit/latest/docs/data-sources/config
# NB this can be read from the instance-metadata-service.
#    see https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instancedata-data-retrieval.html
# NB ANYTHING RUNNING IN THE VM CAN READ THIS DATA FROM THE INSTANCE-METADATA-SERVICE
#    UNLESS the firewall limits the access, like we do in provision-firewall.sh.
# NB cloud-init executes **all** these parts regardless of their result. they
#    should be idempotent.
# NB the output is saved at /var/log/cloud-init-output.log
data "cloudinit_config" "app" {
  part {
    content_type = "text/cloud-config"
    content      = <<-EOF
    #cloud-config
    runcmd:
      - echo 'Hello from cloud-config runcmd!'
    EOF
  }
  part {
    content_type = "text/x-shellscript"
    content      = file("provision-firewall.sh")
  }
  part {
    content_type = "text/x-shellscript"
    content      = file("provision-app.sh")
  }
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance
resource "aws_instance" "app" {
  ami                  = data.aws_ami.ubuntu.id
  instance_type        = "t3.micro" # 2 cpu. 1 GiB RAM. Nitro System. see https://aws.amazon.com/ec2/instance-types/t3/
  iam_instance_profile = aws_iam_instance_profile.app.name
  key_name             = aws_key_pair.admin.key_name
  user_data_base64     = data.cloudinit_config.app.rendered
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
  network_interface {
    network_interface_id = aws_network_interface.app.id
    device_index         = 0
  }
  tags = {
    Name = "${var.name_prefix}-app"
  }
}
