# meerkat-council (app and daemon) with its omp plugin and the credentials copied from the operator's
# machine. Built only by scripts/release.sh, whose staged context holds: meerkat-council
# (linux/amd64 binary), plugin/, prepare-omp-dir.sh, entrypoint.sh, agent.db, models.yml, gh-token
# and webhook-secret.
FROM debian:stable-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends bash ca-certificates curl gh git libgcc-s1 libstdc++6 procps \
    && rm -rf /var/lib/apt/lists/*
ADD --chmod=0755 https://github.com/can1357/oh-my-pi/releases/latest/download/omp-linux-x64 /usr/local/bin/omp
# prepare-omp-dir.sh needs mikefarah yq v4; Debian's `yq` package is a different tool.
ADD --chmod=0755 https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 /usr/local/bin/yq
# The panel checkout clones https://github.com/<pm repo>.git and relies on a credential helper.
RUN git config --system credential.https://github.com.helper '!gh auth git-credential'
COPY --chmod=0755 meerkat-council /usr/local/bin/meerkat-council
COPY plugin/ /opt/meerkat-council/plugin/
COPY --chmod=0755 prepare-omp-dir.sh /opt/meerkat-council/scripts/prepare-omp-dir.sh
COPY --chmod=0755 entrypoint.sh /usr/local/bin/pm-entrypoint
COPY --chmod=0600 agent.db models.yml /root/.omp/agent/
COPY --chmod=0600 gh-token webhook-secret /etc/pm/
WORKDIR /var/lib/meerkat-council
EXPOSE 7420 7421
ENTRYPOINT ["/usr/local/bin/pm-entrypoint"]
