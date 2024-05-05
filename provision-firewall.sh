#!/bin/bash
set -euxo pipefail

# create the imds group.
# NB users in this supplementary group will have access to the AWS EC2
#    Instance Metadata IP address (169.254.169.254).
# NB users in the root primary group too.
addgroup --system imds

# update the package cache.
apt-get update

# install the firewall.
# these anwsers were obtained (after installing iptables-persistent) with:
#   #sudo debconf-show iptables-persistent
#   sudo apt-get install debconf-utils
#   # this way you can see the comments:
#   sudo debconf-get-selections
#   # this way you can just see the values needed for debconf-set-selections:
#   sudo debconf-get-selections | grep -E '^iptables-persistent\s+' | sort
debconf-set-selections <<'EOF'
iptables-persistent iptables-persistent/autosave_v4 boolean false
iptables-persistent iptables-persistent/autosave_v6 boolean false
EOF
apt-get install -y iptables iptables-persistent

# configure the IPv4 firewall.
cat >/etc/iptables/rules.v4 <<'EOF'
*filter
:INPUT DROP [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:IMDS - [0:0]
# configure ingress rules.
-A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
-A INPUT -p icmp -j ACCEPT
-A INPUT -i lo -j ACCEPT
-A INPUT -p tcp -m state --state NEW -m tcp --dport 80 -j ACCEPT
-A INPUT -p tcp -m state --state NEW -m tcp --dport 22 -j ACCEPT
# log and reject.
-A INPUT -m limit --limit 2/min -j LOG --log-prefix "iptables-reject-INPUT " --log-level 4
-A INPUT -j REJECT --reject-with icmp-admin-prohibited
# configure AWS IMDS access rules.
# limit the users that can access the aws instance metadata service ip address
# to the root primary group and the imds supplementary group.
# NB the amazon-ssm-agent snap runs as root.
#    see snap info --verbose amazon-ssm-agent
#    see ps axuw | grep amazon-ssm-agent
# see https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instancedata-data-retrieval.html#instance-metadata-limiting-access
-A OUTPUT -p tcp --destination 169.254.169.254 -j IMDS
-A IMDS --match owner --gid-owner root -j ACCEPT
-A IMDS --match owner --gid-owner imds --suppl-groups -j ACCEPT
# log and reject.
-A IMDS -m limit --limit 2/min -j LOG --log-prefix "iptables-reject-IMDS " --log-level 4
-A IMDS -j REJECT --reject-with icmp-admin-prohibited
COMMIT

*nat
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
COMMIT
EOF
iptables-restore </etc/iptables/rules.v4

# configure the IPv6 firewall.
cat >/etc/iptables/rules.v6 <<'EOF'
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT DROP [0:0]
# log and reject.
-A INPUT -m limit --limit 2/min -j LOG --log-prefix "ip6tables-reject-INPUT " --log-level 4
-A INPUT -j REJECT --reject-with icmp6-adm-prohibited
# log and reject.
-A FORWARD -m limit --limit 2/min -j LOG --log-prefix "ip6tables-reject-FORWARD " --log-level 4
-A FORWARD -j REJECT --reject-with icmp6-adm-prohibited
# log and reject.
-A OUTPUT -m limit --limit 2/min -j LOG --log-prefix "ip6tables-reject-OUTPUT " --log-level 4
-A OUTPUT -j REJECT --reject-with icmp6-adm-prohibited
COMMIT
EOF
ip6tables-restore </etc/iptables/rules.v6
