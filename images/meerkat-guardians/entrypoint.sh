#!/bin/sh
# Builds the omp agent dir from the mounted config (/config/guardians/omp/config.yml plus the
# image's credentials) with meerkat-guardians' own script, then runs the program with the image's token.
set -eu
GH_TOKEN=$(cat /etc/meerkat/gh-token)
export GH_TOKEN
/opt/meerkat-guardians/scripts/prepare-omp-dir.sh /config
exec meerkat-guardians --config-root /config "$@"
