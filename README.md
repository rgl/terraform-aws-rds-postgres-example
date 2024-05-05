# About

[![Lint](https://github.com/rgl/terraform-aws-rds-postgres-example/actions/workflows/lint.yml/badge.svg)](https://github.com/rgl/terraform-aws-rds-postgres-example/actions/workflows/lint.yml)

An example Amazon RDS for PostgreSQL database that can be used from an AWS EC2 Ubuntu Virtual Machine.

This will:

* Use the [Amazon RDS for PostgreSQL service](https://aws.amazon.com/rds/postgresql/).
  * Create a Database Instance.
* Create an example Ubuntu Virtual Machine.
  * Can be used to access the Database Instance.
* Create a VPC and all the required plumbing required for the Ubuntu Virtual
  Machine to use an Amazon RDS PostgreSQL Database Instance.

# Usage (on a Ubuntu Desktop)

Install the tools:

```bash
./provision-tools.sh
```

Set the account credentials using SSO:

```bash
# set the account credentials.
# see https://docs.aws.amazon.com/cli/latest/userguide/sso-configure-profile-token.html#sso-configure-profile-token-auto-sso
aws configure sso
# dump the configured profile and sso-session.
cat ~/.aws/config
# set the environment variables to use a specific profile.
export AWS_PROFILE=my-profile
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_DEFAULT_REGION
# show the user, user amazon resource name (arn), and the account id, of the
# profile set in the AWS_PROFILE environment variable.
aws sts get-caller-identity
```

Or, set the account credentials using an access key:

```bash
# set the account credentials.
# NB get these from your aws account iam console.
#    see Managing access keys (console) at
#        https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_access-keys.html#Using_CreateAccessKey
export AWS_ACCESS_KEY_ID='TODO'
export AWS_SECRET_ACCESS_KEY='TODO'
# set the default region.
export AWS_DEFAULT_REGION='eu-west-1'
# show the user, user amazon resource name (arn), and the account id.
aws sts get-caller-identity
```

Review `main.tf`.

Initialize terraform:

```bash
make terraform-init
```

Launch the example:

```bash
rm -f terraform.log
make terraform-apply
```

Show the terraform state:

```bash
make terraform-show
```

At VM initialization time [cloud-init](https://cloudinit.readthedocs.io/en/latest/index.html) will run the `provision-app.sh` script to launch the example application.

After VM initialization is done (check the instance system log for cloud-init entries), test the `app` endpoint:

```bash
while ! wget -qO- "http://$(terraform output --raw app_ip_address)/test"; do sleep 3; done
```

And open a shell inside the VM:

```bash
ssh "ubuntu@$(terraform output --raw app_ip_address)"
cloud-init status --wait
less /var/log/cloud-init-output.log
systemctl status app
journalctl -u app
exit
```

Try accessing the PostgreSQL Database Instance, from within the AWS VPC, using [`psql`](https://www.postgresql.org/docs/current/app-psql.html):

```bash
ssh "ubuntu@$(terraform output --raw app_ip_address)" \
  LC_ALL='C.UTF-8' \
  PGSSLMODE='verify-full' \
  PGHOST="$(printf '%q' "$(terraform output --raw db_address)")" \
  PGDATABASE='postgres' \
  PGUSER="$(printf '%q' "$(terraform output --raw db_admin_username)")" \
  PGPASSWORD="$(printf '%q' "$(terraform output --raw db_admin_password)")" \
  psql \
    --echo-all \
    --no-password \
    --variable ON_ERROR_STOP=1 \
    <<'EOF'
-- show information the postgresql version.
select version();
-- show information about the current connection.
select current_user, current_database(), inet_client_addr(), inet_client_port(), inet_server_addr(), inet_server_port(), pg_backend_pid(), pg_postmaster_start_time();
-- show information about the current tls connection.
select case when ssl then concat('YES (', version, ')') else 'NO' end as ssl from pg_stat_ssl where pid=pg_backend_pid();
-- list roles.
\dg
-- list databases.
\l
EOF
```

Open an interactive psql session, show the PostgreSQL version, and exit:

```bash
ssh -t "ubuntu@$(terraform output --raw app_ip_address)" \
  LC_ALL='C.UTF-8' \
  PGSSLMODE='verify-full' \
  PGHOST="$(printf '%q' "$(terraform output --raw db_address)")" \
  PGDATABASE='postgres' \
  PGUSER="$(printf '%q' "$(terraform output --raw db_admin_username)")" \
  PGPASSWORD="$(printf '%q' "$(terraform output --raw db_admin_password)")" \
  psql
select version();
exit
```

Destroy the example:

```bash
make terraform-destroy
```

# References

* [Environment variables to configure the AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-envvars.html)
* [Token provider configuration with automatic authentication refresh for AWS IAM Identity Center](https://docs.aws.amazon.com/cli/latest/userguide/sso-configure-profile-token.html) (SSO)
* [Managing access keys (console)](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_access-keys.html#Using_CreateAccessKey)
* [AWS General Reference](https://docs.aws.amazon.com/general/latest/gr/Welcome.html)
  * [Amazon Resource Names (ARNs)](https://docs.aws.amazon.com/general/latest/gr/aws-arns-and-namespaces.html)
* [Connect to the internet using an internet gateway](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Internet_Gateway.html#vpc-igw-internet-access)
* [Retrieve instance metadata](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instancedata-data-retrieval.html)
* [How Instance Metadata Service Version 2 works](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instance-metadata-v2-how-it-works.html)
* [Amazon RDS for PostgreSQL service](https://aws.amazon.com/rds/postgresql/)
* [Amazon RDS for PostgreSQL resources](https://aws.amazon.com/rds/postgresql/resources/)
* [Amazon RDS for PostgreSQL](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_PostgreSQL.html)
* [Common DBA tasks for Amazon RDS for PostgreSQL](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Appendix.PostgreSQL.CommonDBATasks.html)
* [Using SSL with a PostgreSQL DB instance](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/PostgreSQL.Concepts.General.SSL.html)
* [Using SSL/TLS to encrypt a connection to a DB instance or cluster](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.SSL.html)
* [PostgreSQL Environment Variables](https://www.postgresql.org/docs/16/libpq-envars.html)
* [PostgreSQL System Information Functions and Operators](https://www.postgresql.org/docs/16/functions-info.html)
