#!/bin/sh
set -e

# Start ttyd on localhost only (Nginx will proxy /ttyd/ to it)
# --base-path /ttyd  → ttyd serves its own JS/CSS assets under /ttyd/
# --writable          → allow keyboard input
# --once              → do NOT exit after one client disconnects
ttyd \
  --port 7681 \
  --interface 127.0.0.1 \
  --base-path /ttyd \
  --writable \
  /bin/sh &

# Start Nginx in the foreground (keeps the container alive)
exec nginx -c /etc/nginx/nginx.conf -g "daemon off;"
