#!/usr/bin/env sh

[ -n "$TARBALLS" ] || read -p "Tarballs: " TARBALLS

mkdir -p $(dirname ${TARBALLS})

echo "Note that /etc and /var/lib are handled by default!"
[ -z "$BACKUP_TARGETS" ] || read -p "Extra files to backup: " BACKUP_TARGETS

echo $TARBALLS | xargs -I '{}' -n 1 tar -cvzpf '{}' /etc /var/lib /var/www $BACKUP_TARGETS

while read -p "Backup user to add: " BACKUP_USER; do
    useradd -r -s /usr/bin/bash -G sudo ${BACKUP_USER}
    passwd $BACKUP_USER
done
