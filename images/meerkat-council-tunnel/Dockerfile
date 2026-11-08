# Connector of the council webhook's Cloudflare tunnel: the tunnel
# routes POST /webhook to http://app:7420 in the meerkat-council Stack. Built only by scripts/release.sh,
# whose staged context holds tunnel-token.
FROM cloudflare/cloudflared:latest
# The base image runs as nonroot (65532); the token file must be readable by it. It goes straight
# into /etc: COPY --chmod also applies to directories it creates, so a new /etc/cloudflared would
# be 0400 and untraversable.
COPY --chown=65532:65532 --chmod=0400 tunnel-token /etc/cloudflared-token
ENTRYPOINT ["cloudflared"]
CMD ["tunnel", "--no-autoupdate", "run", "--token-file", "/etc/cloudflared-token"]
