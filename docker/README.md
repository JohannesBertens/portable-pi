# Interactive pi container (example)

Example Dockerfile + run script for running the **pi agent interactively in a
container** on a Fedora host, wired to **local vLLM / llama.cpp** endpoints.
Designed for restricted environments:

- **No Node.js, no npm, no registry access at run time** — pi ships inside the
  image as the official offline Bun-compiled binary.
- The built image is a single artifact you can carry in via `podman save/load`.
- All LLM traffic stays on the host / LAN.

Everything below was verified end-to-end on Fedora (rootless podman 5.8.7,
pi 1.3.0; build, `--version` and vLLM re-run on 1.4.0) against a real vLLM server and a real llama.cpp server — see
"Verified" at the bottom.

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Image: `debian:bookworm-slim` + tools + offline pi bundle |
| `entrypoint.sh` | Generates `models.json` / `settings.json` from `PI_LLM_*` env vars, then execs pi |
| `pi-run.sh` | Host wrapper: `build \| run \| shell \| print \| save \| load` |

## Build (once, on a connected machine)

```bash
# release archive must sit next to the Dockerfile (gitignored):
curl -sLO https://github.com/earendil-works/pi/releases/download/v1.4.0/pi-linux-x64.tar.gz
./pi-run.sh build                      # -> localhost/pi-interactive:1.4.0
```

For arm64 hosts, use `pi-linux-arm64.tar.gz` and adjust the `COPY` line.
During the build the image needs apt + the tarball — afterwards it never
touches the network again.

## Transfer into the restricted environment

```bash
./pi-run.sh save pi-interactive.tar    # on the connected machine (≈230 MB)
# carry the tar over...
./pi-run.sh load pi-interactive.tar    # on the restricted machine
```

## Run interactively

```bash
cd /path/to/project

# llama.cpp on the SAME host (published port, e.g. llama-server on :8080):
PI_LLM_BASE_URL=http://host.containers.internal:8080/v1 \
PI_LLM_MODEL=halogen-qwen3.8-flash-next \
PI_LLM_THINKING_FORMAT=qwen-chat-template PI_LLM_NO_DEVELOPER_ROLE=1 \
./pi-run.sh

# llama.cpp on the same host, host networking instead:
PI_NETWORK=host PI_LLM_BASE_URL=http://127.0.0.1:8080/v1 ... ./pi-run.sh

# vLLM on another machine in the LAN:
PI_LLM_BASE_URL=http://192.168.1.247:8000/v1 \
PI_LLM_MODEL=Qwen3.8-Flash-Next \
PI_LLM_THINKING_FORMAT=qwen-chat-template \
./pi-run.sh
```

One-shot: `./pi-run.sh print "summarize this repo"`.
Debug shell: `./pi-run.sh shell` (add `-c '<cmd>'` to run a command).

### Plain Docker (no wrapper)

`pi-run.sh` calls podman. With Docker, use the Dockerfile directly:

```bash
# once, on a connected machine (in this directory):
curl -sLO https://github.com/earendil-works/pi/releases/download/v1.4.0/pi-linux-x64.tar.gz
docker build -t pi-interactive:1.4.0 .
docker save -o pi-interactive.tar pi-interactive:1.4.0   # carry this tar over
docker load -i pi-interactive.tar                        # on the restricted machine

# in your project dir — llama.cpp / vLLM on the same host:
docker run --rm -it --init \
  --add-host=host.docker.internal:host-gateway \
  -v "$PWD":/workspace \
  -v pi-agent-home:/root/.pi/agent \
  -e PI_LLM_BASE_URL=http://host.docker.internal:8080/v1 \
  -e PI_LLM_MODEL=halogen-qwen3.8-flash-next \
  -e PI_LLM_THINKING_FORMAT=qwen-chat-template -e PI_LLM_NO_DEVELOPER_ROLE=1 \
  pi-interactive:1.4.0

# vLLM on another LAN machine: just change the URL (no --add-host needed)
#   -e PI_LLM_BASE_URL=http://192.168.1.247:8000/v1 -e PI_LLM_MODEL=Qwen3.8-Flash-Next
# one-shot: append  pi -p "summarize this repo"  after the image name
```

Docker differences from the podman setup:

- **`host.docker.internal`** is automatic on Docker Desktop. On Linux Docker Engine it needs the `--add-host=…:host-gateway` line above, and the LLM server must listen on `0.0.0.0` (or the `docker0` IP). A server bound to `127.0.0.1` is unreachable from the bridge. In that case use `--network host` with `http://127.0.0.1:<port>/v1` (Linux only).
- **File ownership:** with rootful Docker, files pi creates in `/workspace` are owned by root on the host (rootless podman/Docker maps them to you).
- **SELinux hosts** (Fedora/RHEL): append `:Z` to the workspace mount, as `pi-run.sh` does.
- All `PI_LLM_*` variables in the table below work the same with `-e`.

### Environment variables

| Variable | Default | Meaning |
|---|---|---|
| `PI_LLM_BASE_URL` | *(required)* | OpenAI-compatible endpoint incl. `/v1` |
| `PI_LLM_MODEL` | `local-model` | model id exactly as served |
| `PI_LLM_API` | `openai-completions` | pi API dialect |
| `PI_LLM_API_KEY` | `local` | dummy key for local servers |
| `PI_LLM_THINKING_FORMAT` | *(empty)* | e.g. `qwen-chat-template` for Qwen |
| `PI_LLM_NO_DEVELOPER_ROLE` | `0` | `1` for llama.cpp servers rejecting developer role |
| `PI_LLM_CONTEXT_WINDOW` / `PI_LLM_MAX_TOKENS` | `262144` / `8192` | model limits |
| `PI_NETWORK` | `bridge` | `bridge` or `host` |
| `PI_FORCE_CONFIG` | `0` | `1` regenerates config despite saved volume |

## Networking matrix (verified on Fedora + rootless podman + pasta)

| From inside container → reach | URL that works | Notes |
|---|---|---|
| LLM on **same host**, bridge network | `http://host.containers.internal:<port>/v1` | works for pasta-published ports (e.g. llama-server `-p 8080` under podman) |
| LLM on **same host**, `--network=host` | `http://127.0.0.1:<port>/v1` | always works, incl. loopback-only servers |
| LLM on **another LAN machine**, bridge | `http://192.168.1.247:8000/v1` | plain LAN address |
| ❌ `192.168.1.240:8080` (this host's own LAN IP) from bridge | refused | pasta asymmetry: host-side works, bridge-side doesn't — use `host.containers.internal` |
| ❌ `127.0.0.1` with bridge network | refused | loopback is the *container's*, not the host's |
| ❌ `/etc/hosts` names like `mini-ai.home` | no DNS | containers don't inherit host `/etc/hosts`; use the IP or `--add-host mini-ai.home:192.168.1.240` |

## Fedora specifics baked into the example

- **Rootless podman** — no daemon, no root; container-root maps to your host
  user, so files written in `/workspace` appear owned by you (verified).
- **SELinux**: workspace is mounted with `:Z` (required on Fedora; harmless
  elsewhere). The named volume `pi-agent-home` keeps settings/sessions/auth
  between runs without relabeling anything.
- `--init` reaps orphaned processes the agent's bash tool spawns.
- `PI_TELEMETRY=0` is set image-wide (no install ping on air-gapped hosts).
- The wrapper adds `-it` only when a TTY exists, so scripted/headless use works.

## What is NOT covered (on purpose)

- GPU access inside the container — inference stays on the host/LAN servers;
  the container only needs HTTP. GPU passthrough (ROCm/CUDA) would balloon the
  image and isn't needed for this pattern.
- Upstream pi also documents Docker Sandboxes (`sbx`), OpenShell and Gondolin
  (micro-VM) isolation — see pi's
  [containerization doc](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/containerization.md)
  if you need managed sandboxes or credential proxies.

## Verified (2026-10-18, Fedora host, podman 5.8.7)

1. Clean `podman build` from the Dockerfile (offline binary baked in, `--version` check at build time)
2. Clean container: `pi --version` → `1.3.0`
3. Generated `models.json` / `settings.json` → valid JSON incl. conditional `compat`
4. e2e bridge → vLLM (`192.168.1.247:8000`): model replied `CLEAN-VLLM-OK`
5. e2e bridge → llama.cpp (`host.containers.internal:8080`): model replied `CLEAN-LLAMACPP-OK`
6. Workspace write-through: file created in `/workspace` lands on host owned by the invoking user
7. Named volume: config persists across `--rm` runs (`using existing config ...`)
8. Interactive TUI renders through the container under a pty (alt-screen, mouse mode, themes)

Re-run 2026-10-22 on pi 1.4.0: steps 1, 2 (`→ 1.4.0`) and 4 (`CLEAN-VLLM-140-OK`) pass. The llama.cpp step was not re-run because no server was up.
Hand-written `models.json` for vLLM / llama.cpp (without the container): [../docs/models-json.md](../docs/models-json.md).
