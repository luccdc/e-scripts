#!/usr/bin/env sh

echo "This script will modify your repo list."
read -p "Continue? (y/n): " cont

[ "y" = "${cont,,}" ] &&
    ( find /etc/yum.repos.d -type f -exec sed -i {} -r -e 's~^mirrorlist~#mirrorlist~' \;
      find /etc/yum.repos.d -type f -exec sed -i {} -r -e 's~#?baseurl=http://mirror.centos~baseurl=http://vault.centos~' \; )
