FROM steamcmd/steamcmd:ubuntu-24

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# GMod's stable Linux dedicated server is still 32-bit. Keep the compatibility
# libraries in the image so the persistent server install remains disposable.
# The base image already reserves UID/GID 1000 for ubuntu. Rename that account
# so bind-mounted files match the host without creating a conflicting user.
RUN apt-get update \
    && apt-get install --no-install-recommends -y \
        lib32gcc-s1 \
        lib32stdc++6 \
        tini \
    && groupmod --new-name steam ubuntu \
    && usermod --login steam --home /home/steam --move-home \
        --comment "Steam game server" --groups "" ubuntu \
    && install -d -o steam -g steam /data /home/steam/.steam/sdk32 \
    && rm -rf /var/lib/apt/lists/*

COPY --chown=steam:steam entrypoint.sh /usr/local/bin/gmod-entrypoint
COPY --chown=steam:steam presets /presets
RUN chmod 0755 /usr/local/bin/gmod-entrypoint

ENV HOME=/home/steam
WORKDIR /home/steam
USER steam

EXPOSE 27015/udp

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/gmod-entrypoint"]
