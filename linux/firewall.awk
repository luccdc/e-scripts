#!/usr/bin/env -S awk -f
BEGIN {
	RENDERER = ENVIRON["FIREWALL"] ? ENVIRON["FIREWALL"] : "iptables"
	if (ENVIRON["ELK_IP"]) {
		ESTAB_ADDR[ENVIRON["ELK_IP"]][5044]++
	}
}

{
	# Column 4 is "st", or socket state
	switch ($4) {	# State 0A is LISTEN
	case "0A":
		split($2, local_address, ":")
		# ignore localhost
		if (local_address[1] != "0100007F") {
			LISTEN_PORTS[strtonum("0x" local_address[2])]++
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
			if (! (strtonum("0x" local_address[2]) in LISTEN_PORTS)) {
				ESTAB_ADDR[prettyd][strtonum("0x" remote_address[2])]++
			}
		}
		break
	}
}

END {
	switch (RENDERER) {
	case "iptables":
		# perform a reset
		printf "iptables -P INPUT ALLOW; "
		printf "iptables -P OUTPUT ALLOW; "
		printf "iptables -F INPUT; "
		print "iptables -F OUTPUT"
		print "iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT"
		print "iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT"
		for (p in LISTEN_PORTS) {
			print "iptables -A INPUT -p tcp --dport", p, "-j ALLOW"
		}
		for (d in ESTAB_ADDR) {
			for (p in ESTAB_ADDR[d]) {
				print "iptables -A OUTPUT -p tcp --dport", p, "-d", d, "-j ALLOW"
			}
		}
		print "iptables -P INPUT DROP"
		print "iptables -P OUTPUT DROP"
		break
	case "ufw":
		print "ufw reset"
		for (p in LISTEN_PORTS) {
			printf "ufw allow %d/tcp\n", p
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
	}
}
