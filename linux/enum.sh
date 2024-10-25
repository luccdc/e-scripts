#!/usr/bin/env sh

# Shamelessly borrowed from https://github.com/ActualTrash/bashutils/blob/main/bashutils.sh
export RED='\033[0;31m'
export YELLOW='\033[0;33m'
export PINK='\033[0;35m'
export RED_BG='\033[0;41m'
export GREEN='\033[0;32m'
export BLUE='\033[0;34m'
export NO_COLOR='\033[0m'
export BOLD="$(tput bold)"
# End shameless borrowing

KNOWN_SERVICES='postgresql mariadb mysql ssh sshd httpd apache2 nginx docker postfix named bind9'

SYSTEMD_SERVICES='reload-systemd-vconsole-setup.service
systemd-backlight@backlight:amdgpu_bl1.service
systemd-boot-random-seed.service
systemd-fsck@dev-disk-by\\x2duuid-E460\\x2d3F47.service
systemd-journal-flush.service
systemd-journald.service
systemd-logind.service
systemd-modules-load.service
systemd-oomd.service
systemd-random-seed.service
systemd-remount-fs.service
systemd-sysctl.service
systemd-timesyncd.service
systemd-tmpfiles-setup-dev-early.service
systemd-tmpfiles-setup-dev.service
systemd-tmpfiles-setup.service
systemd-udev-trigger.service
systemd-udevd.service
systemd-update-utmp.service
systemd-user-sessions.service
systemd-vconsole-setup.service
systemd-journald-dev-log.socket
systemd-journald.socket
systemd-oomd.socket
systemd-udevd-control.socket
systemd-udevd-kernel.socket'

function mk_header () {
    echo -e "${GREEN}${BOLD}----- ${1}${NO_COLOR}"
}

function grepify_list () {
   echo $1 | awk '{gsub(/ /,"|"); print}'
}

[ "$EUID" -ne 0 ] && echo "Run this script with sudo!" && exit 1

mk_header "enumerate the network"
ss -peanuts |
    awk '/LISTEN/{print $1, $5, $6, $7}' | column -t

mk_header "System IP addresses"
ip -c -br a 2>/dev/null || ip -br a


mk_header "enumerate running services (Probably Incomplete!)"
systemctl list-units --state=running | grep -E $(grepify_list "${KNOWN_SERVICES}")

mk_header "look for suspicious systemd-alikes (Non-listed units may still be sus!)"
systemctl list-units --state=running | grep systemd | grep -v -E $(grepify_list "${SYSTEMD_SERVICES}")

mk_header "System stats"
lscpu | grep Core | column -t
echo
free -h
echo
df -h /
