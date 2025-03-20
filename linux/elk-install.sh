#!/usr/bin/env bash
#
# Sets up and prepares the local machine to serve as the ELK stack for the network
#
# Installs Elasticsearch and sets the password to what is provided or made available in the environment
# Installs Logstash and configures it to route Winlogbeat and Filebeat records, and to accept general beats
# Installs Kibana and registers it in Elasticsearch
# Installs Auditbeat, Filebeat, and Packetbeat to set up the indices and dashboards for each, and then reconfigures them to
#   point to Logstash
# Creates a directory which can be used to serve beats RPMs
#

hostnamectl | grep -Eq 'Static hostname: *\(unset\)' && echo "Please ensure that a hostname is set!!" && exit 1

set -e

export ELASTIC_VERSION="${ELASTIC_VERSION:-8.17.3}"
export DOWNLOAD_URL="${DOWNLOAD_URL:-https://artifacts.elastic.co/downloads}"
export BEATS_DOWNLOAD_URL="${BEATS_DOWLOAD_URL:-${DOWNLOAD_URL}/beats}"
export EXTERNAL_IP=`ip -br a | awk '/UP/ { print $3 }' | head -n 1 | cut -d '/' -f1`
PATH_CONFIG='${path.config}'

[ -z "${ELASTIC_PASSWORD}" ] && echo -n "Enter the password for the elastic user: " && read -r ELASTIC_PASSWORD

print_msg() {
    echo "$(printf '\033[0;32m')--- ${1}$(printf '\033[0m')"
}

setup_zram() {
    print_msg "Setting up ZRAM"

    if ! lsmod | grep -q zram; then
        modprobe zram || echo "Could not load ZRAM module"
        zramctl /dev/zram0 --size=4G || echo "Could not initialize /dev/zram0"
        mkswap /dev/zram0 || echo "Could not initialize zram swap space"
        swapon --priority=100 /dev/zram0 || echo "Could not enable zram swap space"
        print_msg "ZRAM set up!"
    else
        print_msg "Skipping zram setup!"
    fi
}

download_file() {
    if which curl >/dev/null; then
        curl -o "$1" "$2" 2>/dev/null >/dev/null
    elif which wget >/dev/null; then
        wget -O "$1" "$2" 2>/dev/null >/dev/null
    else
        echo "Can't find a program to download files with!"
        exit 1
    fi
}

download_packages() {
    print_msg "Downloading Elastic packages"

    mkdir -p /opt/es
    cd /opt/es

    if [[ -f /etc/redhat-release ]]; then
        for pkg in elasticsearch logstash kibana; do
            echo "Downloading $pkg rpm..."
            (download_file $pkg.rpm "$DOWNLOAD_URL/$pkg/$pkg-$ELASTIC_VERSION-x86_64.rpm" && echo "Done downloading $pkg!") &
        done

        for beat in filebeat auditbeat packetbeat; do
            echo "Downloading $beat rpm and deb..."
            (download_file $beat.rpm "$BEATS_DOWNLOAD_URL/$beat/$beat-$ELASTIC_VERSION-x86_64.rpm" && echo "Done downloading $beat rpm!") &
            (download_file $beat.deb "$BEATS_DOWNLOAD_URL/$beat/$beat-$ELASTIC_VERSION-amd64.deb" && echo "Done downloading $beat deb!") &
        done

	wait

        for pkg in elasticsearch logstash kibana filebeat auditbeat packetbeat; do
            echo "Installing $pkg..."
            rpm -i $pkg.rpm
        done
    else
        for pkg in elasticsearch logstash kibana; do
            echo "Downloading $pkg deb..."
            (download_file $pkg.deb "$DOWNLOAD_URL/$pkg/$pkg-$ELASTIC_VERSION-amd64.deb" && echo "Done downloading $pkg!") &
        done

        for beat in filebeat auditbeat packetbeat; do
            echo "Downloading $beat rpm and deb..."
            (download_file $beat.deb "$BEATS_DOWNLOAD_URL/$beat/$beat-$ELASTIC_VERSION-amd64.deb" && echo "Done downloading $beat deb!") &
            (download_file $beat.rpm "$BEATS_DOWNLOAD_URL/$beat/$beat-$ELASTIC_VERSION-x86_64.rpm" && echo "Done downloading $beat rpm!") &
        done

        wait

        for pkg in elasticsearch logstash kibana filebeat auditbeat packetbeat; do
            echo "Installing $pkg..."
            sudo dpkg -i $pkg.deb
        done
    fi

    print_msg "Done downloading packages!"
}

setup_elasticsearch() {
    print_msg "Configuring Elasticsearch"

    systemctl enable --now elasticsearch
    cat - <<EOF | /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic -i
y
${ELASTIC_PASSWORD}
${ELASTIC_PASSWORD}
EOF
    mkdir -p /etc/es_certs
    cp /etc/elasticsearch/certs/http_ca.crt /etc/es_certs
    chmod -R +r /etc/es_certs

    print_msg "Elasticsearch configured!"
}

setup_kibana() {
    print_msg "Configuring Kibana"

    sudo -u kibana /usr/share/kibana/bin/kibana-setup -t $(/usr/share/elasticsearch/bin/elasticsearch-create-enrollment-token -s kibana)
    sed -i -e 's/.*server.host:.*/server.host: "0.0.0.0"/' /etc/kibana/kibana.yml
    systemctl enable --now kibana

    print_msg "Kibana configured!"
}

setup_logstash() {
    print_msg "Configuring Logstash"

    API_KEY_INFO="$(curl -k -u "elastic:${ELASTIC_PASSWORD}" https://localhost:9200/_security/api_key?pretty -X POST -H 'content-type: application/json' -d '{"name":"logstash-api-key","role_descriptors":{"logstash_writer":{"cluster":["monitor","manage_index_templates","manage_ilm"],"index":[{"names":["filebeat-*","winlogbeat-*","auditbeat-*","packetbeat-*","logs-*"],"privileges":["view_index_metadata","read","create","manage","manage_ilm"]}]}}}')"

    ID=`echo "$API_KEY_INFO" | grep -Po '(?<="id" : ")[^"]+'`
    KEY=`echo "$API_KEY_INFO" | grep -Po '(?<="api_key" : ")[^"]+'`

    cat - <<EOF > /etc/logstash/conf.d/pipeline.conf
input {
    beats {
        port => 5044
    }
}

output {
    if [@metadata][beat] == "winlogbeat" {
        elasticsearch {
            hosts => "https://localhost:9200"
            manage_template => false
            action => "create"
            ssl => true
            ssl_certificate_authorities => "/etc/es_certs/http_ca.crt"
            api_key => "${ID}:${KEY}"

            pipeline => "%{[@metadata][beat]}-%{[@metadata][version]}-routing"
            data_stream => true
        }
    } else if [@metadata][pipeline] {
        elasticsearch {
            hosts => "https://localhost:9200"
            manage_template => false
            action => "create"
            ssl => true
            ssl_certificate_authorities => "/etc/es_certs/http_ca.crt"
            api_key => "${ID}:${KEY}"

            pipeline => "%{[@metadata][pipeline]}"
            data_stream => true
        }

        elasticsearch {
            hosts => "https://localhost:9200"
            manage_template => false
            action => "create"
            ssl => true
            ssl_certificate_authorities => "/etc/es_certs/http_ca.crt"
            api_key => "${ID}:${KEY}"

            index => "%{[@metadata][beat]}-%{[@metadata][version]}"
        }
    } else {
        elasticsearch {
            hosts => "https://localhost:9200"
            manage_template => false
            action => "create"
            ssl => true
            ssl_certificate_authorities => "/etc/es_certs/http_ca.crt"
            api_key => "${ID}:${KEY}"

            index => "%{[@metadata][beat]}-%{[@metadata][version]}"
        }
    }
}
EOF

    systemctl enable --now logstash

    print_msg "Done configuring Logstash"
}

setup_auditbeat() {
    print_msg "Setting up Auditbeat"

    cat - <<EOF > /etc/auditbeat/auditbeat.yml
auditbeat.modules:
- module: auditd
  audit_rules: |
    -a always,exit -F arch=b64 -S execve,execveat -k exec

- module: file_integrity
  paths:
  - /bin
  - /usr/bin
  - /sbin
  - /usr/sbin
  - /etc

- module: system
  datasets:
  - host
  - login
  - process
  - socket
  - user

  state.period: 12h
  user.detect_password_changes: true
  login.wtmp_file_pattern: /var/log/wtmp*
  login.btmp_file_pattern: /var/log/btmp*

setup.template.settings.index.number_of_shards: 1

processors:
  - add_host_metadata: ~
  - add_docker_metadata: ~

output.elasticsearch:
  hosts: ["https://localhost:9200"]
  transport: https
  username: "elastic"
  password: "${ELASTIC_PASSWORD}"
  ssl:
    enabled: true
    certificate_authorities: "/etc/es_certs/http_ca.crt"
EOF

    auditbeat setup

    cat - <<EOF > /etc/auditbeat/auditbeat.yml
auditbeat.modules:
- module: auditd
  audit_rules: |
    -a always,exit -F arch=b64 -S execve,execveat -k exec

- module: file_integrity
  paths:
  - /bin
  - /usr/bin
  - /sbin
  - /usr/sbin
  - /etc

- module: system
  datasets:
  - host
  - login
  - process
  - socket
  - user

  state.period: 12h
  user.detect_password_changes: true
  login.wtmp_file_pattern: /var/log/wtmp*
  login.btmp_file_pattern: /var/log/btmp*

processors:
  - add_host_metadata: ~
  - add_docker_metadata: ~

output.logstash:
  hosts: ["${EXTERNAL_IP}:5044"]
EOF

    systemctl enable auditbeat
    systemctl restart auditbeat

    cp /etc/auditbeat/auditbeat.yml /opt/es/auditbeat.yml

    print_msg "Auditbeat set up"
}

setup_filebeat() {
    print_msg "Setting up Filebeat"

    cat - <<EOF > /etc/filebeat/filebeat.yml
filebeat.inputs:
- type: udp
  max_message_size: 10KiB
  host: "0.0.0.0:514"
  processors:
    - syslog:
        field: message

filebeat.config.modules:
  path: ${PATH_CONFIG}/modules.d/*.yml
  reload.enabled: false

processors:
  - add_host_metadata:
      when.not.contains.tags: forwarded
  - add_docker_metadata: ~

setup.template.settings.index.number_of_shards: 1

output.elasticsearch:
  hosts: ["https://localhost:9200"]
  transport: https
  username: "elastic"
  password: "${ELASTIC_PASSWORD}"
  ssl:
    enabled: true
    certificate_authorities: "/etc/es_certs/http_ca.crt"
EOF

    filebeat setup

    cat - <<EOF > /etc/filebeat/modules.d/netflow.yml
- module: netflow
  log:
    enabled: true
    var:
      netflow_host: localhost
      netflow_port: 2055
      internal_networks:
        - private
EOF

    cat - <<EOF > /etc/filebeat/modules.d/system.yml
- module: system
  syslog:
    enabled: true
  auth:
    enabled: true
EOF

    cat - <<EOF > /etc/filebeat/filebeat.yml
filebeat.inputs:
- type: udp
  max_message_size: 10KiB
  host: "0.0.0.0:514"
  processors:
    - syslog:
        field: message

filebeat.config.modules:
  path: ${PATH_CONFIG}/modules.d/*.yml
  reload.enabled: false

processors:
  - add_host_metadata:
      when.not.contains.tags: forwarded
  - add_docker_metadata: ~

output.logstash:
  hosts: ["${EXTERNAL_IP}:5044"]
EOF

    systemctl enable filebeat
    systemctl restart filebeat

    cp /etc/filebeat/filebeat.yml /opt/es/filebeat.yml

    print_msg "Filebeat set up"
}

setup_packetbeat() {
    print_msg "Setting up Packetbeat"

    cat - <<EOF > /etc/packetbeat/packetbeat.yml
packetbeat.interfaces.device: any
packetbeat.interfaces.poll_default_route: 1m
packetbeat.interfaces.internal_networks:
  - private
packetbeat.flows:
  timeout: 30s
  period: 10s
packetbeat.protocols:
- type: icmp
  enabled: true
- type: amqp
  ports: [5672]
- type: cassandra
  ports: [9042]
- type: dhcpv4
  ports: [67, 68]
- type: dns
  ports: [53]
- type: http
  ports: [80, 8080, 8000, 5000, 8002]
- type: memcache
  ports: [11211]
- type: mysql
  ports: [3306, 3307]
- type: pgsql
  ports: [5432]
- type: redis
  ports: [6379]
- type: thrift
  ports: [9090]
- type: mongodb
  ports: [27017]
- type: nfs
  ports: [2049]
- type: tls
  ports:
    - 8443
- type: sip
  ports: [5060]

setup.template.settings.index.number_of_shards: 1

processors:
  - if.contains.tags: forwarded
    then:
      - drop_fields:
          fields: [host]
    else:
      - add_host_metadata: ~
  - add_cloud_metadata: ~
  - add_docker_metadata: ~
  - detect_mime_type:
      field: http.request.body.content
      target: http.request.mime_type
  - detect_mime_type:
      field: http.response.body.content
      target: http.response.mime_type

output.elasticsearch:
  hosts: ["https://localhost:9200"]
  transport: https
  username: "elastic"
  password: "${ELASTIC_PASSWORD}"
  ssl:
    enabled: true
    certificate_authorities: "/etc/es_certs/http_ca.crt"
  pipeline: "packetbeat-%{[agent.version]}-routing"
EOF

    packetbeat setup

    cat - <<EOF > /etc/packetbeat/packetbeat.yml
packetbeat.interfaces.device: any
packetbeat.interfaces.poll_default_route: 1m
packetbeat.interfaces.internal_networks:
  - private
packetbeat.flows:
  timeout: 30s
  period: 10s
packetbeat.protocols:
- type: icmp
  enabled: true
- type: amqp
  ports: [5672]
- type: cassandra
  ports: [9042]
- type: dhcpv4
  ports: [67, 68]
- type: dns
  ports: [53]
- type: http
  ports: [80, 8080, 8000, 5000, 8002]
- type: memcache
  ports: [11211]
- type: mysql
  ports: [3306, 3307]
- type: pgsql
  ports: [5432]
- type: redis
  ports: [6379]
- type: thrift
  ports: [9090]
- type: mongodb
  ports: [27017]
- type: nfs
  ports: [2049]
- type: tls
  ports:
    - 8443
- type: sip
  ports: [5060]

setup.template.settings.index.number_of_shards: 1

processors:
  - if.contains.tags: forwarded
    then:
      - drop_fields:
          fields: [host]
    else:
      - add_host_metadata: ~
  - add_cloud_metadata: ~
  - add_docker_metadata: ~
  - detect_mime_type:
      field: http.request.body.content
      target: http.request.mime_type
  - detect_mime_type:
      field: http.response.body.content
      target: http.response.mime_type

output.logstash:
  hosts: ["${EXTERNAL_IP}:5044"]
EOF

    systemctl enable packetbeat
    systemctl restart packetbeat

    cp /etc/packetbeat/packetbeat.yml /opt/es/packetbeat.yml

    print_msg "Packetbeat set up"
}

setup_zram
download_packages
setup_elasticsearch
setup_kibana
setup_logstash

print_msg "Waiting for Kibana..."
while ! curl http://localhost:5601/api/status 2>/dev/null | grep -q '"level":"available"'; do
    print_msg "Waiting for Kibana..."
    sleep 1
done

setup_auditbeat
setup_filebeat
setup_packetbeat
wait

print_msg "Installation complete, no errors!"
