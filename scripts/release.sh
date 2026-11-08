#!/bin/bash
# Builds the deployed instance's images on this machine and loads them onto the Docker host
# $MEERKAT_RELEASE_HOST (an ssh destination); no registry is involved: images reach the host by
# `docker save | ssh $MEERKAT_RELEASE_HOST docker load`.
#
# usage: scripts/release.sh [--load-only] <stack>...
#   meerkat-guardians   image meerkat-local/meerkat-guardians:current
#   meerkat-council     images meerkat-local/meerkat-council:current and meerkat-local/meerkat-council-tunnel:current
#   meerkat-web         image meerkat-local/meerkat-web:current
#
# Program sources are the implementation repositories' origin/main, exported from local clones
# under $MEERKAT_SRC_ROOT (default: the directory holding this repository's main checkout); Meerkat's
# clone is $MEERKAT_SRC_ROOT/meerkat (mouriya-s-lab/meerkat). The meerkat-web image holds no Meerkat config:
# its Stack mounts meerkat/ and shared/ at run time.
# Credentials are copied from this machine into a staging context under /tmp that is removed on
# exit:
#   ~/.omp/agent/agent.db (sqlite backup) and ~/.omp/agent/models.yml (both program images),
#   `gh auth token` (both program images and meerkat-web, whose Caddyfile passes GitHub reads and,
#   of the writes, only contents PUTs to the config repo), and
#   ~/.config/meerkat-config/{council-webhook-secret,council-tunnel-token}.
# The webhook secret is generated on the first council release and reused afterwards.
# Without --load-only every named stack is then redeployed with `km x deploy-stack`, using the km
# profile $KM_PROFILE when it is set.
set -euo pipefail
umask 077

usage() {
	echo "usage: scripts/release.sh [--load-only] meerkat-guardians|meerkat-council|meerkat-web..." >&2
	exit 2
}

deploy=1
stacks=
for arg in "$@"; do
	case "$arg" in
	--load-only) deploy=0 ;;
	meerkat-guardians | meerkat-council | meerkat-web) stacks="$stacks $arg" ;;
	*) usage ;;
	esac
done
[ -n "$stacks" ] || usage

repo=$(cd "$(dirname "$0")/.." && pwd)
host=${MEERKAT_RELEASE_HOST:?set MEERKAT_RELEASE_HOST to the ssh destination of the Docker host}
omp_dir=$HOME/.omp/agent
cfg_dir=$HOME/.config/meerkat-config
meerkat_cache=${XDG_CACHE_HOME:-$HOME/.cache}/meerkat-config/meerkat

# Every credential file and tool a named stack needs is checked before anything is built.
missing=
tools="git tar docker ssh"
need() {
	[ -s "$1" ] && return
	case " $missing " in
	*" $1 "*) ;;
	*) missing="$missing $1" ;;
	esac
}
for s in $stacks; do
	case "$s" in
	meerkat-guardians)
		need "$omp_dir/agent.db"
		need "$omp_dir/models.yml"
		tools="$tools go sqlite3 gh"
		;;
	meerkat-council)
		need "$omp_dir/agent.db"
		need "$omp_dir/models.yml"
		need "$cfg_dir/council-tunnel-token"
		tools="$tools go sqlite3 gh openssl"
		;;
	meerkat-web)
		tools="$tools nsh cargo wasm-bindgen gh"
		;;
	esac
done
if [ -n "$missing" ]; then
	for f in $missing; do
		echo "release: missing credential file $f" >&2
	done
	exit 1
fi
[ "$deploy" = 0 ] || tools="$tools km"
for t in $tools; do
	command -v "$t" >/dev/null || {
		echo "release: required tool $t is not on PATH" >&2
		exit 1
	}
done
gh auth token >/dev/null || {
	echo "release: gh auth token failed; log in with gh first" >&2
	exit 1
}

common=$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)
main_checkout=${common%/*}
src_root=${MEERKAT_SRC_ROOT:-${main_checkout%/*}}
config_rev=$(git -C "$repo" rev-parse HEAD)

stage=$(mktemp -d /tmp/meerkat-config-build.XXXXXX)
trap 'rm -rf "$stage"' EXIT
trap 'exit 130' INT TERM

# export_source <repo> <dir>: fetches the clone $src_root/<repo>, extracts its origin/main into
# <dir> and sets rev to that commit.
export_source() {
	git -C "$src_root/$1" fetch --quiet origin main
	rev=$(git -C "$src_root/$1" rev-parse origin/main)
	mkdir -p "$2"
	git -C "$src_root/$1" archive "$rev" | tar -x -C "$2"
}

# stage_omp <ctx>: the omp credentials. agent.db is written by running omp processes in WAL mode,
# so it is copied with sqlite's online backup rather than cp.
stage_omp() {
	sqlite3 "$omp_dir/agent.db" ".backup '$1/agent.db'"
	cp "$omp_dir/models.yml" "$1/models.yml"
	gh auth token >"$1/gh-token"
}

# build_load <image> <ctx>: builds meerkat-local/<image>:current for the host's platform with the
# revision labels, then loads it onto the host.
build_load() {
	docker buildx build --platform linux/amd64 -f "$repo/images/$1/Dockerfile" \
		--label "org.opencontainers.image.revision=$rev" \
		--label "meerkat-config.revision=$config_rev" \
		-t "meerkat-local/$1:current" --load "$2"
	docker save "meerkat-local/$1:current" | ssh "$host" docker load
}

# release_program <repo>: meerkat-guardians or meerkat-council, with its plugin, its prepare-omp-dir.sh and
# the image entrypoint.
release_program() {
	local src=$stage/src/$1 ctx=$stage/ctx/$1
	export_source "$1" "$src"
	mkdir -p "$ctx/plugin"
	(cd "$src" && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -o "$ctx/$1" "./cmd/$1")
	cp -R "$src/plugin/." "$ctx/plugin/"
	cp "$src/scripts/prepare-omp-dir.sh" "$repo/images/$1/entrypoint.sh" "$ctx/"
	stage_omp "$ctx"
}

release_guardians() {
	release_program meerkat-guardians
	build_load meerkat-guardians "$stage/ctx/meerkat-guardians"
}

release_council() {
	local secret=$cfg_dir/council-webhook-secret tctx=$stage/ctx/meerkat-council-tunnel
	if [ ! -s "$secret" ]; then
		mkdir -p "$cfg_dir"
		openssl rand -hex 32 >"$secret"
	fi
	release_program meerkat-council
	cp "$secret" "$stage/ctx/meerkat-council/webhook-secret"
	build_load meerkat-council "$stage/ctx/meerkat-council"
	mkdir -p "$tctx"
	cp "$cfg_dir/council-tunnel-token" "$tctx/tunnel-token"
	rev=$config_rev
	build_load meerkat-council-tunnel "$tctx"
}

# release_meerkat_web: Meerkat's web build, its Caddyfile and the gh token; no Meerkat config.
# The source is exported afresh at a fixed path under $meerkat_cache and compiled into
# $meerkat_cache/target, which outlives the release, so a release recompiles only what changed
# since the last one instead of every dependency (nsh's cargo honours CARGO_TARGET_DIR).
# `nsh package -o <dir>` writes the site to <dir>/Meerkat.
release_meerkat_web() {
	local src=$meerkat_cache/src ctx=$stage/ctx/meerkat-web
	rm -rf "$src"
	export_source meerkat "$src"
	mkdir -p "$ctx"
	(cd "$src" && CARGO_TARGET_DIR=$meerkat_cache/target PATH=/opt/homebrew/opt/llvm/bin:$PATH \
		nsh package --target web -o "$stage/web")
	mv "$stage/web/Meerkat" "$ctx/site"
	cp "$src/deploy/Caddyfile" "$repo/images/meerkat-web/entrypoint.sh" "$ctx/"
	gh auth token >"$ctx/gh-token"
	build_load meerkat-web "$ctx"
}

for s in $stacks; do
	case "$s" in
	meerkat-guardians) release_guardians ;;
	meerkat-council) release_council ;;
	meerkat-web) release_meerkat_web ;;
	esac
done

if [ "$deploy" = 1 ]; then
	for s in $stacks; do
		km ${KM_PROFILE:+-p "$KM_PROFILE"} x deploy-stack "$s"
	done
fi
