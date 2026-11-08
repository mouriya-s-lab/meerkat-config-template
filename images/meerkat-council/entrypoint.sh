#!/bin/sh
# `app` needs only the mounted config and the webhook secret file. `daemon` reads and writes GitHub
# with the image's token and spawns omp, so its agent dir is built first with meerkat-council's own script.
set -eu
case "${1:-}" in
daemon)
	GH_TOKEN=$(cat /etc/pm/gh-token)
	export GH_TOKEN
	/opt/meerkat-council/scripts/prepare-omp-dir.sh /config
	;;
app) ;;
*)
	echo "usage: pm-entrypoint app|daemon" >&2
	exit 2
	;;
esac
exec meerkat-council "$1" --config-root /config
