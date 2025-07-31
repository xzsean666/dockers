#!/bin/bash

start=60000
end=60100

for ((port=start; port<=end; port++)); do
  cat <<EOF
[[proxies]]
name = "udp-$port"
type = "udp"
localPort = $port
remotePort = $port

EOF
done
