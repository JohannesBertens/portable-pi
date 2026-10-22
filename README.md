# portable-pi

Research and tooling for distributing the [pi coding agent](https://github.com/earendil-works/pi)
as a fully offline, self-contained bundle for Linux and Windows targets
(no Node.js, npm, or JS libraries required on the target machine).

**Full research:** [docs/offline-bundling-research.md](docs/offline-bundling-research.md) (investigated on pi v1.3.0; release artifacts re-verified on v1.4.0)

## TL;DR — recommendation

pi's upstream **already publishes standalone, Bun-compiled release archives** for every relevant target. They are self-contained single executables (~41–44 MB compressed / ~103–111 MB unpacked) that need **no Node.js, npm, or JS libraries** on the target. For an offline bundle, take those archives + `SHA256SUMS` and add a small checksum-verifying installer script.

Direct download links for **v1.4.0** (all assets also listed on the [releases page](https://github.com/earendil-works/pi/releases/latest)):

| Target | Official artifact (direct link) | Size | Runs on |
|---|---|---|---|
| Linux x64 | [`pi-linux-x64.tar.gz`](https://github.com/earendil-works/pi/releases/download/v1.4.0/pi-linux-x64.tar.gz) | 41 MB | glibc ≥ 2.17 (CentOS 7+), kernel ≥ 3.10, SSE4.2 CPU |
| Linux arm64 | [`pi-linux-arm64.tar.gz`](https://github.com/earendil-works/pi/releases/download/v1.4.0/pi-linux-arm64.tar.gz) | — | same floor |
| Windows x64 | [`pi-windows-x64.zip`](https://github.com/earendil-works/pi/releases/download/v1.4.0/pi-windows-x64.zip) | 44 MB | Windows 10 / Server 2016+ |
| Windows arm64 | [`pi-windows-arm64.zip`](https://github.com/earendil-works/pi/releases/download/v1.4.0/pi-windows-arm64.zip) | — | Windows 10+ |
| macOS x64 (bonus) | [`pi-darwin-x64.tar.gz`](https://github.com/earendil-works/pi/releases/download/v1.4.0/pi-darwin-x64.tar.gz) | — | macOS 13+ |
| macOS arm64 (bonus) | [`pi-darwin-arm64.tar.gz`](https://github.com/earendil-works/pi/releases/download/v1.4.0/pi-darwin-arm64.tar.gz) | — | macOS 13+ |
| Checksums | [`SHA256SUMS`](https://github.com/earendil-works/pi/releases/download/v1.4.0/SHA256SUMS) | — | verify before installing |

The glibc floor was verified directly on the shipped binary (`objdump -T` → max `GLIBC_2.17`; only `libc`, `ld-linux`, `libpthread`, `libdl`, `libm` needed).

## Quick offline install (no installer script needed)

```bash
# Linux — carried in on offline media:
sha256sum -c SHA256SUMS --ignore-missing      # verify first
tar xzf pi-linux-x64.tar.gz -C "$HOME/.local/share/"
ln -sf "$HOME/.local/share/pi/pi" "$HOME/.local/bin/pi"
pi --version                                   # → 1.4.0, no node anywhere
```

```powershell
# Windows:
Expand-Archive pi-windows-x64.zip -DestinationPath "$env:LOCALAPPDATA\pi"
& "$env:LOCALAPPDATA\pi\pi\pi.exe" --version
```

## Also: portable GitHub Copilot CLI

GitHub Copilot CLI ships the same kind of standalone single-executable archives
(Windows zip/msi, Linux glibc + musl, macOS). With `COPILOT_OFFLINE=true` it runs
against a local vLLM/llama.cpp/Ollama server with no GitHub login (verified v1.0.103
→ local vLLM, including tool calls). For the Windows install and local-model setup, see
**[docs/portable-copilot.md](docs/portable-copilot.md)**.

## Why the official binaries are the right answer

- The pi codebase has **first-class "bun-binary" support** (`isBunBinary` in `packages/coding-agent/src/config.ts`): themes, docs, HTML-export templates, and the Photon WASM resolve next to the executable; the QuickJS WASM is embedded inside the binary; both worker threads are explicit compile entrypoints.
- The optional native clipboard/paste helpers (`.node`) ship as sidecars in the archive — if missing, pi degrades gracefully (clipboard only).
- All six targets are cross-compiled from one Linux CI runner with Bun pinned (1.3.14) via upstream's `scripts/build-binaries.sh`.
- Verified: an extracted `pi-linux-x64` runs `pi --version` fine on a machine with no Node.

## Strategy summary (details and matrix in the research doc)

1. **✅ Official Bun-compiled archives** — recommended baseline; zero build effort.
2. **✅ Self-built `bun build --compile`** — use when you need musl/Alpine (`--target=bun-linux-*-musl`, not shipped officially), patches, branding, or version pinning.
3. **✅ Vendored Node 22 + pi's npm bundle** — acceptable fallback; worse glibc floor (≥ 2.28), ~2× footprint; enables pi-as-SDK usage.
4. **⚠️ Node SEA** — poor fit today: VFS still early-development, native addons need temp-file extraction, no worker-embedding story.
5. **⚠️ pkg / @yao-pkg** — deprecated upstream (`vercel/pkg` archived); Node 22 cross-compile regression; snapshot-FS fights pi's asset resolution.
6. **❌ deno compile / nexe / boxednode / caxa** — wrong runtime, dormant, or strictly worse than 1–3.

## Interactive container (example Dockerfile + run script)

**[Full guide + verified networking matrix → docker/README.md](docker/README.md)**

A verified example for running pi **interactively in a rootless podman container on Fedora**, wired to local vLLM / llama.cpp endpoints so all LLM traffic stays on the host/LAN. Built for restricted environments: no Node, no npm, no registry access at run time — the offline Bun-compiled pi binary is baked into the image, and the finished image transfers as a single tar via `podman save/load`.

### Files

| File | Purpose |
|---|---|
| [`docker/Dockerfile`](docker/Dockerfile) | `debian:bookworm-slim` + git/ripgrep/procps + the offline pi release bundle; no Node anywhere |
| [`docker/entrypoint.sh`](docker/entrypoint.sh) | generates a clean `models.json` + `settings.json` from `PI_LLM_*` env vars, probes the endpoint, then execs pi |
| [`docker/pi-run.sh`](docker/pi-run.sh) | host wrapper: `build \| run \| shell \| print \| save \| load`; SELinux `:Z` mounts, named volume for sessions/auth, tty-aware `-it` |
| [`docker/README.md`](docker/README.md) | env-var table, networking matrix, Fedora notes, verification log |

### Usage

```bash
# once, on a connected machine:
cd docker
curl -sLO https://github.com/earendil-works/pi/releases/download/v1.4.0/pi-linux-x64.tar.gz
./pi-run.sh build && ./pi-run.sh save pi-interactive.tar    # carry this tar into the restricted env
./pi-run.sh load pi-interactive.tar                        # there

# then, in your project dir on the restricted machine:
PI_LLM_BASE_URL=http://host.containers.internal:8080/v1 \   # llama.cpp on the same host
PI_LLM_MODEL=halogen-qwen3.8-flash-next \
PI_LLM_THINKING_FORMAT=qwen-chat-template PI_LLM_NO_DEVELOPER_ROLE=1 ./pi-run.sh

PI_LLM_BASE_URL=http://192.168.1.247:8000/v1 ./pi-run.sh    # vLLM on another LAN machine
PI_NETWORK=host PI_LLM_BASE_URL=http://127.0.0.1:8080/v1 ./pi-run.sh   # host networking
```

**Using Docker instead of podman** (`pi-run.sh` is podman-only; [details](docker/README.md#plain-docker-no-wrapper)):

```bash
cd docker && docker build -t pi-interactive:1.4.0 .
docker save -o pi-interactive.tar pi-interactive:1.4.0      # carry over, then: docker load -i pi-interactive.tar

cd /path/to/project
docker run --rm -it --init --add-host=host.docker.internal:host-gateway \
  -v "$PWD":/workspace -v pi-agent-home:/root/.pi/agent \
  -e PI_LLM_BASE_URL=http://host.docker.internal:8080/v1 -e PI_LLM_MODEL=<model-id> \
  pi-interactive:1.4.0
```

### Reaching the LLM server from inside the container (verified)

| Server location | URL that works |
|---|---|
| Same host (bridge network) | `http://host.containers.internal:<port>/v1` |
| Same host (`PI_NETWORK=host`) | `http://127.0.0.1:<port>/v1` |
| Another LAN machine | `http://<lan-ip>:<port>/v1` (e.g. `192.168.1.247:8000`) |
| ❌ loopback/LAN-IP of the host itself via bridge | refused — use `host.containers.internal` or host networking |

### Verified end-to-end (Fedora, rootless podman 5.8.7, pi 1.3.0; 1, 2, 4 re-run on 1.4.0)

1. ✅ Clean `podman build` (offline binary baked in) · 2. ✅ `pi --version` in clean container · 3. ✅ generated config = valid JSON · 4. ✅ e2e → vLLM over bridge · 5. ✅ e2e → llama.cpp via `host.containers.internal` · 6. ✅ workspace write-through with correct host ownership · 7. ✅ config/sessions persist across `--rm` runs · 8. ✅ interactive TUI renders through the container (alt-screen, mouse, themes)

## Runtime caveats on offline targets

- **"Offline install" ≠ "offline operation"** — pi needs LLM endpoints (or local llama.cpp / OpenAI-compatible servers) at runtime. **`models.json` examples for vLLM and llama.cpp: [docs/models-json.md](docs/models-json.md).**
- **Windows needs Git Bash** for the `bash` tool (bundle [Portable Git](https://git-scm.com/download/win) and set `shellPath` for fully offline hosts); `pi.exe` is unsigned → SmartScreen may warn on first run.
- Extensions with their own npm dependencies install deps on demand — vendor their `node_modules` into the kit or avoid them air-gapped.
- Set `PI_TELEMETRY=0` on air-gapped machines (install telemetry defaults on).
- `pi update` does not self-update a binary install — the kit is the update unit (replace archive, re-run installer).
