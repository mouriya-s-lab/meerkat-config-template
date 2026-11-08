#!/bin/sh
# The Caddyfile reads GH_TOKEN from the environment; the token lives in a file so it stays out of
# the image config and the container's inspect output. LISTEN, CONFIG_DIR, CONFIG_REPO and the
# program addresses come from the Stack's compose file.
set -eu
GH_TOKEN=$(cat /etc/pm/gh-token)
export GH_TOKEN
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
