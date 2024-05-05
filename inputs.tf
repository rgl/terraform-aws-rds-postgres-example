# get the available locations with: aws ec2 describe-regions | jq -r '.Regions[].RegionName' | sort
variable "region" {
  type    = string
  default = "eu-west-1"
}

variable "owner" {
  type    = string
  default = "rgl"
}

variable "name_prefix" {
  type    = string
  default = "rgl-terraform-aws-rds-postgres-example"
}

# NB when you run make terraform-apply this is set from the TF_VAR_admin_ssh_key_data environment variable, which comes from the ~/.ssh/id_rsa.pub file.
variable "admin_ssh_key_data" {
  type = string
}
