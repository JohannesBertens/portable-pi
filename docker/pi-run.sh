#!/usr/bin/env bash
# Example host-side wrapper for running the pi agent interactively in a
# rootless podman container on Fedora. Everything stays local.
#
# Usage:
#   ./pi-run.sh build                 # build the image (needs the release tarball + apt once)
#   ./pi-run.sh run                   # interactive pi in $PWD (default action)
#   ./pi-run.sh shell                 # bash inside the container (debugging)
#   ./pi-run.sh print "question"      # one-shot: pi -p "<question>"
#   ./pi-run.sh save [file.tar]       # export image for transfer to a restricted host
#   ./pi-run.sh load [file.tar]       # import image on the restricted host
#
# Key environment variables (all optional except PI_LLM_BASE_URL on first run):
#   PI_LLM_BASE_URL          local OpenAI-compatible endpoint, WITH /v1 suffix
#                            bridge:  http://host.containers.internal:8080/v1  (server on same host)
#                            bridge:  http://192.168.1.247:8000/v1             (server on LAN)
#                            host:    http://127.0.0.1:8080/v1                 (server on same host)
#   PI_LLM_MODEL             model id as served by the endpoint (default: local-model)
#   PI_LLM_THINKING_FORMAT   e.g. qwen-chat-template for Qwen models (default: empty)
#   PI_LLM_NO_DEVELOPER_ROLE 1 for llama.cpp servers that reject the developer role
#   PI_LLM_CONTEXT_WINDOW    default 262144 | PI_LLM_MAX_TOKENS default 8192
#   PI_NETWORK               bridge (default) or host
#   PI_IMAGE                 image tag (default localhost/pi-interactive:1.3.0)
set -euo pipefail

IMAGE="${PI_IMAGE:-localhost/pi-interactive:1.3.0}"
NETWORK="${PI_NETWORK:-bridge}"

cmd="${1:-run}"; shift || true

case "$cmd" in
    build) exec podman build -t "$IMAGE" "$(dirname "$0")" ;;
    save)  exec podman save -o "${1:-pi-interactive.tar}" "$IMAGE" ;;
    load)  exec podman load -i "${1:-pi-interactive.tar}" ;;
esac

# -- common run flags -------------------------------------------------------
# - :Z relabels the bind mount for SELinux (required on Fedora; no-op elsewhere)
# - named volume keeps settings/sessions/auth across runs
# - --init reaps orphaned shell processes the agent spawns
# - workspace is the CURRENT directory, mounted at /workspace
FLAGS=( --rm --init
    --network "$NETWORK"
    -e TERM="${TERM:-xterm-256color}"
    -e PI_LLM_BASE_URL="${PI_LLM_BASE_URL:-}"
    -e PI_LLM_MODEL="${PI_LLM_MODEL:-local-model}"
    -e PI_LLM_THINKING_FORMAT="${PI_LLM_THINKING_FORMAT:-}"
    -e PI_LLM_NO_DEVELOPER_ROLE="${PI_LLM_NO_DEVELOPER_ROLE:-0}"
    -e PI_LLM_CONTEXT_WINDOW="${PI_LLM_CONTEXT_WINDOW:-262144}"
    -e PI_LLM_MAX_TOKENS="${PI_LLM_MAX_TOKENS:-8192}"
    -e PI_FORCE_CONFIG="${PI_FORCE_CONFIG:-0}"
    -v "$PWD":/workspace:Z
    -v pi-agent-home:/root/.pi/agent
)
# Optional: make the host git identity available (mounts the file read-only).
[ -f "${HOME}/.gitconfig" ] && FLAGS+=( -v "$HOME/.gitconfig":/root/.gitconfig:ro,Z )

# Allocate a TTY only when we actually have one (allows scripted/headless runs).
[ -t 0 ] && FLAGS+=( -it )

# -- sanity warning ----------------------------------------------------------
if [ "$NETWORK" = "bridge" ] && [[ "${PI_LLM_BASE_URL:-}" == *127.0.0.1* ]]; then
    echo "WARNING: PI_LLM_BASE_URL contains 127.0.0.1 but PI_NETWORK=bridge." >&2
    echo "         Use http://host.containers.internal:<port>/v1, or run with PI_NETWORK=host." >&2
fi

case "$cmd" in
    run)   exec podman run "${FLAGS[@]}" "$IMAGE" pi "$@" ;;
    shell) exec podman run "${FLAGS[@]}" "$IMAGE" bash "$@" ;;
    print) exec podman run "${FLAGS[@]}" "$IMAGE" pi -p "$*" ;;
    *) echo "unknown command: $cmd (use build|run|shell|print|save|load)" >&2; exit 2 ;;
esac
