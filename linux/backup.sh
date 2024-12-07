#!/usr/bin/env bash

sudogroup="wheel"
grep $sudogroup /etc/group || sudogroup="sudo"
echo "Sudo group: $sudogroup"


[ -n "$TARBALLS" ] || read -p "Tarballs: " TARBALLS

mkdir -p $(dirname ${TARBALLS})

echo 'Note that /etc,' /var/{lib,www}, {/usr,}/lib/systemd 'are handled by default'
[ -n "$BACKUP_TARGETS" ] || read -p "Extra files to backup: " BACKUP_TARGETS

tar -czpf /tmp/i.tgz /etc /var/lib /var/www /lib/systemd /usr/lib/systemd $BACKUP_TARGETS
echo $TARBALLS | xargs -n 1 cp /tmp/i.tgz &&
    rm /tmp/i.tgz

while read -p "Backup user to add: " BACKUP_USER; do
    useradd -r -s /usr/bin/bash -G sudo ${BACKUP_USER} &&
        passwd $BACKUP_USER
done
