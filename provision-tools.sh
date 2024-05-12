#!/bin/bash
set -euxo pipefail

# install dependencies.
sudo apt-get install -y apt-transport-https make unzip jq

# install terraform.
# see https://www.terraform.io/downloads.html
# see https://github.com/hashicorp/terraform/releases
# renovate: datasource=github-releases depName=hashicorp/terraform
terraform_version='1.8.3'
artifact_url="https://releases.hashicorp.com/terraform/$terraform_version/terraform_${terraform_version}_linux_amd64.zip"
artifact_path="/tmp/$(basename $artifact_url)"
wget -qO $artifact_path $artifact_url
sudo unzip -o $artifact_path -d /usr/local/bin
rm $artifact_path
CHECKPOINT_DISABLE=1 terraform version

# install aws-cli.
# download and install.
# see https://docs.aws.amazon.com/cli/latest/userguide/getting-started-version.html
# see https://github.com/aws/aws-cli/tags
# see https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html#cliv2-linux-install
# renovate: datasource=github-tags depName=aws/aws-cli
AWS_VERSION='2.15.48'
aws_url="https://awscli.amazonaws.com/awscli-exe-linux-x86_64-${AWS_VERSION}.zip"
t="$(mktemp -q -d --suffix=.aws)"
wget -qO "$t/awscli.zip" "$aws_url"
unzip "$t/awscli.zip" -d "$t"
"$t/aws/install" \
    --bin-dir /usr/local/bin \
    --install-dir /usr/local/aws-cli \
    --update
rm -rf "$t"
aws --version
