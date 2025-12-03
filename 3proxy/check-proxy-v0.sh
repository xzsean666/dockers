#!/bin/bash

PROXY_URL="http://astrid:4CBa737x10IgZU676z@31.58.137.32:13128"
CHECK_URL="http://clients3.google.com/generate_204"

if ! curl --proxy "$PROXY_URL" --max-time 5 --silent --fail "$CHECK_URL" > /dev/null; then
    echo "$(date) ❌ Proxy check failed. Restarting container..."
    docker restart local-proxy
else
    echo "$(date) ✅ Proxy OK"
fi
