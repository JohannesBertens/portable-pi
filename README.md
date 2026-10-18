# portable-pi

Research and tooling for distributing the [pi coding agent](https://github.com/earendil-works/pi)
as a fully offline, self-contained bundle for Linux and Windows targets
(no Node.js, npm, or JS libraries required on the target machine).

**Full research:** [docs/offline-bundling-research.md](docs/offline-bundling-research.md) (pi v1.3.0, verified against the shipped artifacts and upstream source)

## TL;DR — recommendation

pi's upstream **already publishes standalone, Bun-compiled release archives** for every relevant target. They are self-contained single executables (~41–44 MB compressed / ~103–111 MB unpacked) that need **no Node.js, npm, or JS libraries** on the target. For an offline bundle, take those archives + `SHA256SUMS` and add a small checksum-verifying installer script.

| Target | Official artifact | Runs on |
|---|---|---|
| Linux x64 | `pi-linux-x64.tar.gz` | glibc ≥ 2.17 (CentOS 7+), kernel ≥ 3.10, SSE4.2 CPU |
| Linux arm64 | `pi-linux-arm64.tar.gz` | same floor |
| Windows x64 | `pi-windows-x64.zip` | Windows 10 / Server 2016+ |
| Windows arm64 | `pi-windows-arm64.zip` | Windows 10+ |

The glibc floor was verified directly on the shipped binary (`objdump -T` → max `GLIBC_2.17`; only `libc`, `ld-linux`, `libpthread`, `libdl`, `libm` needed).

## Quick offline install (no installer script needed)

```bash
# Linux — carried in on offline media:
sha256sum -c SHA256SUMS --ignore-missing      # verify first
tar xzf pi-linux-x64.tar.gz -C "$HOME/.local/share/"
ln -sf "$HOME/.local/share/pi/pi" "$HOME/.local/bin/pi"
pi --version                                   # → 1.3.0, no node anywhere
```

```powershell
# Windows:
Expand-Archive pi-windows-x64.zip -DestinationPath "$env:LOCALAPPDATA\pi"
& "$env:LOCALAPPDATA\pi\pi\pi.exe" --version
```

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

## Runtime caveats on offline targets

- **"Offline install" ≠ "offline operation"** — pi needs LLM endpoints (or local llama.cpp / OpenAI-compatible servers) at runtime.
- **Windows needs Git Bash** for the `bash` tool (bundle [Portable Git](https://git-scm.com/download/win) and set `shellPath` for fully offline hosts); `pi.exe` is unsigned → SmartScreen may warn on first run.
- Extensions with their own npm dependencies install deps on demand — vendor their `node_modules` into the kit or avoid them air-gapped.
- Set `PI_TELEMETRY=0` on air-gapped machines (install telemetry defaults on).
- `pi update` does not self-update a binary install — the kit is the update unit (replace archive, re-run installer).
