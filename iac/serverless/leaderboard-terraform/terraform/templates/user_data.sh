#!/bin/bash
# Runs once at boot
# The actual dashboard files are copied in later by scripts/setup-www.sh.
set -euxo pipefail

apt-get update -y
apt-get install -y nginx

rm -f /var/www/html/index.nginx-debian.html

if [ -x "/bin/systemctl" ]; then
  systemctl enable nginx
  systemctl restart nginx
else
  service nginx restart || /etc/init.d/nginx restart || nginx
fi
