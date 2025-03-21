export ELKIP=172.20.241.20

setup_beat() {
    export E=$([ -f /etc/redhat-release ] && echo "rpm" || echo "deb")
    export B=$([ -f /etc/redhat-release ] && echo "rpm" || echo "dpkg")
    curl -o /tmp/$1.$E http://$ELKIP:8080/$1.$E
    $B -i /tmp/$1.$E
    curl -o /etc/$1/$1.yml http://$ELKIP:8080/$1.yml
}

# Run all the below on all systems
setup_beat auditbeat
setup_beat filebeat
setup_beat packetbeat
# if filebeat is setup...
# Check for all modules available with `filebeat modules list`
# Modify each module to set enabled to true
filebeat modules enable system
#filebeat modules enable nginx
#filebeat modules enable apache
sed -i.bak 's/false/true/g' /etc/filebeat/modules.d/system.yml

systemctl enable {filebeat,auditbeat,packetbeat}
systemctl start {filebeat,auditbeat,packetbeat}
