# Meerkat's web build behind Meerkat's own same-origin proxy (mouriya-s-lab/meerkat deploy/Caddyfile).
# Built only by scripts/release.sh, whose staged context holds: site/ (`nsh package --target web`
# of mouriya-s-lab/meerkat origin/main), Caddyfile, entrypoint.sh and gh-token, the same `gh auth token`
# the guardians and council images carry. The image holds no Meerkat config: the
# Stack mounts this repository's meerkat/ and shared/ under /config, which the Caddyfile serves out
# of CONFIG_DIR. The token can write; the Caddyfile's /gh/* guard passes reads and, of the writes,
# only a contents PUT to CONFIG_REPO.
FROM caddy:latest
COPY site/ /srv/site/
COPY Caddyfile /etc/caddy/Caddyfile
COPY --chmod=0600 gh-token /etc/meerkat/gh-token
COPY --chmod=0755 entrypoint.sh /usr/local/bin/meerkat-entrypoint
# The base image keeps Caddy's own config (autosave.json) under /config, the directory served
# at /config/*; it is moved out of the served tree.
ENV SITE_DIR=/srv/site XDG_CONFIG_HOME=/var/lib/caddy-config
EXPOSE 8088
ENTRYPOINT ["/usr/local/bin/meerkat-entrypoint"]
