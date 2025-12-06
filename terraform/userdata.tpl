#!/bin/bash
set -e

apt-get update -y
apt-get install -y nginx git

rm -rf /var/www/html/*
mkdir -p /var/www/html

cd /tmp

git clone --depth 1 --branch ${site_ref} ${website_repo} repo || {
  rm -rf repo && git clone ${website_repo} repo
  cd repo && git checkout ${site_ref} || true
}

cd repo
cp -r ./* /var/www/html/

echo "Deployed from ${website_repo}@${site_ref} at $(date)" \
  > /var/www/html/DEPLOYED.txt

systemctl enable nginx
systemctl restart nginx

