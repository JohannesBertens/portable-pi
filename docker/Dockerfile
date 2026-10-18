# Example image: pi coding agent as a fully offline, self-contained container.
#
# - No Node.js, no npm: pi ships inside as the official Bun-compiled binary
#   (https://github.com/earendil-works/pi/releases — pi-linux-x64.tar.gz).
# - Build once on a connected machine, then `podman save | podman load`
#   (see pi-run.sh) to carry the image into a restricted environment.
# - Build context must contain pi-linux-x64.tar.gz (download once, ~41 MB).
#   For arm64 hosts use pi-linux-arm64.tar.gz and change the COPY line.
#
# Build:  podman build -t pi-interactive:1.3.0 .

FROM debian:bookworm-slim

# Tools pi and the model expect inside the container. Add what your
# workspaces need (build-essential, python3, ...). Keep it lean otherwise.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash ca-certificates git ripgrep procps curl less \
    && rm -rf /var/lib/apt/lists/*

# The offline pi bundle: binary + wasm + native sidecars + assets.
COPY pi-linux-x64.tar.gz /tmp/pi.tar.gz
RUN mkdir -p /opt/pi \
    && tar xzf /tmp/pi.tar.gz -C /opt/pi --strip-components=1 \
    && rm /tmp/pi.tar.gz \
    && chmod +x /opt/pi/pi \
    && /opt/pi/pi --version

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENV PATH="/opt/pi:${PATH}" \
    PI_TELEMETRY=0 \
    TERM=xterm-256color

WORKDIR /workspace

# Bind-mount your project here (see pi-run.sh). pi's agent state
# (settings, models.json, sessions, auth) lives in /root/.pi/agent —
# mount a named volume there to keep it between runs.
VOLUME ["/root/.pi/agent"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["pi"]
