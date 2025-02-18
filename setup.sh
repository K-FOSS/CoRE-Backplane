#!/bin/sh
echo "Creating Directory"

mkdir -p ./Meta/bin


echo "Getting MQTT CLI"


wget -O ./Meta/bin/mqttx https://www.emqx.com/en/downloads/MQTTX/v1.11.1/mqttx-cli-linux-x64
chmod +x ./Meta/bin/mqttx


echo "Getting MC CLI"

wget -O ./Meta/bin/mc https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x ./Meta/bin/mc


echo "Getting egctl"

wget -O - https://github.com/envoyproxy/gateway/releases/download/latest/egctl_latest_linux_amd64.tar.gz | tar -zxf - -C ./Meta/bin/ --strip-components=3

