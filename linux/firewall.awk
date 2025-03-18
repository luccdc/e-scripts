#!/usr/bin/env -S awk -f

# To use this script, pipe in as input /proc/net/tcp and /proc/net/udp.
# As output, this program will create a sh script that can be used to configure the firewall
#   to allow all programs that are currently listening and to maintain current outbound connections
#
# Example invocations:
#   cat /proc/net/{tcp,udp} | FIREWALL=nft ./firewall.awk | tee firewall.conf | nft -f /dev/stdin
#   FIREWALL=ufw awk -f firewall.awk < /proc/net/tcp | bash
#
# On certain older systems, env does not have a -S flag. On those systems, use `awk -f firewall.awk` instead of `./firewall.awk`
#
# To customize the output, there are two environment variables that control how this program functions:
# FIREWALL: determines what firewall program to output commands for. Currently supports iptables (default),
#   nft, and ufw
# ELK_IP: adds an extra rule to allow traffic to go to port 5044 and port 8080 at this IP address
BEGIN {
	RENDERER = ENVIRON["FIREWALL"] ? ENVIRON["FIREWALL"] : "iptables"
	if (ENVIRON["ELK_IP"]) {
		ESTAB_ADDR[ENVIRON["ELK_IP"]][5044]++
		ESTAB_ADDR[ENVIRON["ELK_IP"]][8080]++
	}
}

{
	# Column 4 is "st", or socket state
	switch ($4) {	# State 0A is LISTEN
	case "0A":
		split($2, local_address, ":")
		# ignore localhost
		if (local_address[1] != "0100007F") {
			TCP_LISTEN_PORTS[strtonum("0x" local_address[2])]++
		}
		break
		# State 01 is ESTAB
	case "01":
		split($3, remote_address, ":")
		split($2, local_address, ":")
		if (remote_address[1] != "0100007F") {
			d = strtonum("0x" remote_address[1])
			prettyd = sprintf("%d.%d.%d.%d", and(d, 255), and(rshift(d, 8), 255), and(rshift(d, 16), 255), rshift(d, 24))
			# ignore established connections to a service that is listening locally
			if (! (strtonum("0x" local_address[2]) in TCP_LISTEN_PORTS)) {
				ESTAB_ADDR[prettyd][strtonum("0x" remote_address[2])]++
			}
		}
		break
		# State 07 is actually UDP's UNCONN
	case "07":
		split($2, local_address, ":")
		if (local_address[1] != "0100007F") {
			UDP_LISTEN_PORTS[strtonum("0x" local_address[2])]++
		}
		break
	}
}

END {
	switch (RENDERER) {
	case "iptables":
		# perform a reset
		printf "iptables -P INPUT ACCEPT; "
		printf "iptables -P OUTPUT ACCEPT; "
		printf "iptables -F INPUT; "
		print "iptables -F OUTPUT"
		print "iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT"
		print "iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT"
		for (p in TCP_LISTEN_PORTS) {
			print "iptables -A INPUT -p tcp --dport", p, "-j ACCEPT"
		}
		for (p in UDP_LISTEN_PORTS) {
			print "iptables -A INPUT -p udp --dport", p, "-j ACCEPT"
		}
		for (d in ESTAB_ADDR) {
			for (p in ESTAB_ADDR[d]) {
				print "iptables -A OUTPUT -p tcp --dport", p, "-d", d, "-j ACCEPT"
			}
		}
		print "iptables -A OUTPUT -o lo -j ACCEPT"
		print "iptables -A INPUT -i lo -j ACCEPT"
		print "iptables -P INPUT DROP"
		print "iptables -P OUTPUT DROP"
		break
	case "ufw":
		print "ufw reset"
		for (p in TCP_LISTEN_PORTS) {
			printf "ufw allow in %d/tcp\n", p
		}
		for (p in UDP_LISTEN_PORTS) {
			printf "ufw allow in %d/udp\n", p
		}
		for (d in ESTAB_ADDR) {
			for (p in ESTAB_ADDR[d]) {
				print "ufw allow out to", d, "port", p, "proto tcp"
			}
		}
		print "ufw default deny incoming"
		print "ufw default deny outgoing"
		print "ufw enable"
		break
	case "nft":
		print "flush ruleset"
		print "table inet firewall {"
		print "    chain input {"
		print "        type filter hook input priority 0; policy drop"
		print "        iifname lo accept"
		for (p in TCP_LISTEN_PORTS) {
			print "        tcp dport", p, "ct state new accept"
		}
		for (p in UDP_LISTEN_PORTS) {
			print "        udp dport", p, "ct state new accept"
		}
		print "        ct state established,related accept"
		print "    }"
		print "    chain output {"
		print "        type filter hook output priority 0; policy drop"
		print "        oifname lo accept"
		for (d in ESTAB_ADDR) {
			for (p in ESTAB_ADDR[d]) {
				print "        ip daddr", d, "tcp dport", p, "ct state new accept"
			}
		}
		print "        ct state established,related accept"
		print "    }"
		print "}"
		break

	case "firewalld":
		print "firewall-cmd --set-default-zone=public"
		for (p in TCP_LISTEN_PORTS) {
			printf "firewall-cmd --permanent --add-port %d/tcp\n", p
		}
		for (p in UDP_LISTEN_PORTS) {
			printf "firewall-cmd --permanent --add-port %d/tcp\n", p
		}

		print "firewall-cmd --direct --permanent --add-rule ipv4 filter OUTPUT 2 -j DROP"
		print "firewall-cmd --direct --permanent --add-rule ipv4 filter OUTPUT 1 -m conntrack --ctstate ESTABLISHED -j ACCEPT"
		print "firewall-cmd --direct --permanent --add-rule ipv4 filter OUTPUT 0 -p udp -m udp --dport=53 -j ACCEPT"
		print "firewall-cmd --direct --permanent --add-rule ipv4 filter OUTPUT 0 -p tcp -m tcp --dport=80 -j ACCEPT"
		print "firewall-cmd --direct --permanent --add-rule ipv4 filter OUTPUT 0 -p tcp -m tcp --dport=443 -j ACCEPT"

		for(d in ESTAB_ADDR[d]) {
			printf "firewall-cmd --direct --permanent --add-rule ipv4 filter OUTPUT 0 -p tcp -m tcp --dport=%d -j ACCEPT\n", d
		}
	}
}
