# Offline bundling of the pi agent — research

**Goal:** distribute the pi coding agent so it can be installed on Linux and Windows machines that have **no Node.js, no npm, and no JS libraries** available, and no network access at install time.

**Date:** 2026-10-18 · **pi version investigated:** 1.3.0 (`@earendil-works/pi-coding-agent`)

**Re-verified 2026-10-22 against v1.4.0:** same release asset set and archive layout; `pi-linux-x64.tar.gz` 41 MB, checksum OK, max `GLIBC_2.17`; `pi --version` → `1.4.0` with no network and no Node. No packaging changes in the v1.4.0 release notes. Findings below still apply.

---

## 1. TL;DR — recommendation

**Use the official standalone pi release archives (Bun-compiled binaries), or build them yourself with the upstream script, and wrap them in a small offline installer.**

1. pi's upstream repo already publishes **self-contained, single-executable archives** for all 6 relevant targets — `pi-linux-x64.tar.gz`, `pi-linux-arm64.tar.gz`, `pi-windows-x64.zip`, `pi-windows-arm64.zip` (+ darwin) — built with `bun build --compile`. They contain everything pi needs at runtime: the executable (~100–111 MB), the Photon WASM, the optional native clipboard/paste helpers, themes, HTML-export templates, docs, and examples. **Verified working:** `pi --version` → `1.3.0` from a bare extract on this machine, no Node present in the process tree.
2. The pi codebase has **first-class support for running as a compiled binary** (`isBunBinary` in `packages/coding-agent/src/config.ts`): assets, WASM, and workers are resolved relative to the executable; the QuickJS WASM is embedded inside the binary; updates are handled explicitly. This is a maintained distribution mode, not a hack.
3. For an offline bundle, take those archives + `SHA256SUMS`, add a ~50-line install script (bash on Linux, PowerShell on Windows) that verifies checksums, unpacks per-user, and wires up `PATH`. That satisfies "no node, no npm, no libraries" on the target.
4. If you need **Alpine/musl** Linux or custom patches/branding, build your own binaries with the upstream `scripts/build-binaries.sh` (Bun cross-compiles all targets from one Linux host; musl targets exist). Pin Bun exactly (`1.3.14` at time of writing).
5. Avoid Node SEA, `pkg`, and friends for pi specifically: pi already ships a purpose-built Bun build; the alternatives fight pi's worker threads, WASM, native addons, and dynamic extension loading (details in §5).

---

## 2. What pi is, implementation-wise (facts verified from the installed package and upstream repo)

| Fact | Detail |
|---|---|
| Language/runtime | TypeScript on Node.js ≥ 22.19 (`engines` field); ESM-first |
| Monorepo packages | `coding-agent`, `tui`, `ai`, `codemode`, `agent-core` (`pi-agent-core`), `mcp`, `telemetry` |
| Entry point | `dist/bundle/cli.js` → `cli-runtime.js` + esbuild chunks (~9 MB total, all JS deps inlined) |
| Hard runtime deps kept external in the npm bundle | `@silvia-odwyer/photon-node` (WASM image resize), `jiti` (TS/JS extension loading, lazy) |
| Optional native modules (graceful degradation) | `bufferutil`, `utf-8-validate`, `kerberos`, `supports-color`; plus **pi-tui platform helpers**: `linux-platform-x11.node`, `win32-platform.node` (clipboard/image paste only) |
| WASM | `photon_rs_bg.wasm` (image resize), `quickjs.wasm` (codemode sandbox via `quickjs-wasi`) |
| Worker threads | image-resize worker + codemode worker (both shipped as extra compile entrypoints in binary builds; codemode worker runs from an in-memory `data:` URL in the npm bundle) |
| Self-spawning | `RpcClient` (`src/modes/rpc/rpc-client.ts`) spawns `node dist/cli.js` — **only used when embedding pi as an SDK from a Node host**; not on the binary's normal paths |
| Install method detection | `"bun-binary" \| "npm" \| "pnpm" \| "yarn" \| "bun"`; bun-binary is a fully supported mode (`pi update` for it prints: *"Download from: https://github.com/earendil-works/pi/releases/latest"*) |
| Telemetry | install telemetry defaults **on**; disable with `PI_TELEMETRY=0` (relevant for air-gapped targets) |
| Sizes (v1.3.0) | npm managed install: 149 MB `node_modules` · `dist/` 21 MB · linux binary 103 MB (41 MB tar.gz) · `pi.exe` 111 MB (44 MB zip) |

### How the binary-mode asset resolution works (why a plain directory layout works offline)

- `getPackageDir()` returns `dirname(process.execPath)` when running as a Bun binary — everything resolves **next to the executable**.
- Photon WASM: `dist/utils/photon.js` patches `fs.readFileSync` and falls back to `<execdir>/photon_rs_bg.wasm` (exactly where the release archive puts it).
- QuickJS WASM: embedded *inside* the binary (`dist/bun/runtime-setup.js` imports `quickjs-wasi/quickjs.wasm`; Bun embeds it and exposes a readable path).
- Native pi-tui helpers: `getNativeModuleCandidates()` searches the installed package first, then **`dirname(process.execPath)/native/<platform>/prebuilds/<platform>-<arch>/…node`** — again exactly the release-archive layout. If absent → clipboard/image paste quietly disabled, agent fully functional.
- Workers: Bun embeds worker entrypoints passed to `bun build --compile`; pi passes both workers explicitly (comment in `scripts/build-binaries.sh` documents this).

---

## 3. Existing distribution channels (as of 1.3.0)

1. **npm**: `npm install -g --ignore-scripts @earendil-works/pi-coding-agent` — requires Node 22.19+ on the target. ❌ offline-unfriendly.
2. **Managed installer** (`curl -fsSL https://pi.dev/install.sh | sh`): installs to `~/.pi/agent/install/releases/<ver>/node_modules` + launcher shim `~/.pi/agent/bin/pi`; installs/downloads Node.js itself if missing. ❌ needs network (but see §5.C — its layout can be replicated offline).
3. **GitHub release binaries** ✅ — `https://github.com/earendil-works/pi/releases/download/v1.4.0/…`:
   - `pi-linux-x64.tar.gz` (41 MB), `pi-linux-arm64.tar.gz`
   - `pi-windows-x64.zip` (44 MB), `pi-windows-arm64.zip`
   - `pi-darwin-x64/arm64.tar.gz`
   - `SHA256SUMS`, source tarball, and the pinned install `package.json`/`package-lock.json`
   - Archive layout (verified): `pi/pi` (the binary) + `package.json`, `README.md`, `CHANGELOG.md`, `photon_rs_bg.wasm`, `theme/*.json`, `assets/`, `export-html/` (+vendored `marked`/`highlight.js`), `docs/`, `examples/`, `native/<plat>/prebuilds/<arch>/*.node`
   - Built by `scripts/build-binaries.sh` in CI (`.github/workflows/build-binaries.yml`), Bun pinned to **1.3.14**, all six targets **cross-compiled from a single ubuntu runner**; x64 targets use the baseline (SSE4.2) profile.

**Implication:** the artifact you need for offline install already exists and is checksummed. Your work reduces to packaging/installer glue — plus musl builds if you need Alpine (§5.B).

---

## 4. Target-machine requirements (verified)

### Linux (official Bun-compiled binary)
- **glibc ≥ 2.17** — verified directly on the shipped binary: `objdump -T` shows max `GLIBC_2.17`; `NEEDED` libs are only `libc`, `ld-linux`, `libpthread`, `libdl`, `libm`. Covers RHEL/CentOS 7+, Ubuntu 16.04+, Debian 9+.
- Kernel: Bun runs on kernels as old as **3.10 (RHEL 7)** with graceful degradation; Bun recommends ≥ 5.6.
- CPU (x64): SSE4.2 (Nehalem 2008+/Bulldozer+). ARM64 unaffected.
- **musl/Alpine: NOT covered by the official glibc archives** — build `--target=bun-linux-x64-musl` / `bun-linux-arm64-musl` yourself (§5.B).
- Optional: X11 (`DISPLAY` set) only for the native clipboard helper — without it pi still runs fine.

### Windows
- Windows 10 / Server 2016+ (x64 and arm64 both shipped).
- Unsigned `pi.exe` + Mark-of-the-Web (files downloaded from the internet) ⇒ **SmartScreen "unknown publisher" warning** on first run (general Windows behavior; not pi-specific). Mitigations: ship inside a zip (common practice, users right-click → Properties → Unblock, or `Unblock-File`), or Authenticode-sign if you own a cert.
- **Runtime shell dependency:** pi's `bash` tool needs Git Bash by default (resolved from `shellPath` setting, `Program Files`, or `PATH`); PowerShell tool uses `pwsh.exe`/`powershell.exe`. For fully-offline Windows targets, bundle [Portable Git](https://git-scm.com/download/win) (`PortableGit-*.exe` is a self-extracting 7-Zip, installs without admin) next to pi and point `shellPath` at it. Without any shell, pi still runs interactively but its `bash`/`powershell` tools are unusable.

### Runtime (not install-time) needs — be explicit with users
- **"Offline install" ≠ "offline operation."** pi talks to LLM provider APIs; on air-gapped networks point it at local endpoints (pi supports llama.cpp / local OpenAI-compatible endpoints) or pre-provisioned proxies.
- Extensions/skills with their own npm dependencies (`examples/extensions/with-deps/` pattern) install those deps on demand ⇒ needs npm + network. Vendor such extensions' `node_modules` into the bundle, or avoid them on offline targets.
- `PI_TELEMETRY=0` (or settings) to silence the install ping on air-gapped machines.

---

## 5. Candidate strategies — analysis

### A. ✅ Official prebuilt Bun-compiled archives (recommended baseline)

- **What:** download the six release archives + `SHA256SUMS` once; ship them on your offline medium with an installer script.
- **Pros:** zero build effort; produced and tested by upstream CI; all asset/WASM/native handling already solved; smallest viable artifacts (41–44 MB compressed); updates = swap archive.
- **Cons:** no musl build; you inherit whatever Bun version upstream pinned; no custom branding/icon; `pi update` won't self-update a binary install (it prints "download from releases") — your installer/updater owns versioning.
- **Fit for pi:** perfect — it *is* pi's own binary distribution.

### B. ✅ Build your own Bun `--compile` binaries (when you need musl, patches, pinning)

- **How (from upstream, verified):**
  ```bash
  git clone https://github.com/earendil-works/pi && cd pi
  # pin bun 1.3.14 (the version CI uses)
  npm ci --ignore-scripts
  npm run build:offline            # builds all packages with bundled model data
  ./scripts/build-binaries.sh --offline-model-data --out out   # all 6 targets
  # musl extras (upstream doesn't build these):
  bun build --compile --no-compile-autoload-bunfig --no-compile-dotenv \
    --target=bun-linux-x64-musl \
    ./packages/coding-agent/dist/bun/cli.js \
    ./packages/coding-agent/src/utils/image-resize-worker.ts \
    ./packages/coding-agent/src/extensions/codemode/worker.ts \
    --outfile out/pi-linux-x64-musl/pi
  # then copy the same sidecar assets as build-binaries.sh does
  ```
- **Bun capabilities verified from docs (bun.com/docs/bundler/executables):**
  - Cross-compile from any host to: `bun-linux-x64`, `bun-linux-arm64` (glibc), `bun-linux-x64-musl`, `bun-linux-arm64-musl`, `bun-windows-x64`, `bun-windows-arm64`, `bun-darwin-x64/arm64`. One Linux CI runner builds everything (upstream does exactly this).
  - Embeds `.wasm` and `.node` files (entrypoints or `with { type: "file" }` imports; `--asset` for directories). Workers must be explicit entrypoints — pi already passes both.
  - `--bytecode` (2× faster cold start), `--bytecode-order` PGO, `--minify`, embedded sourcemaps. Windows exe metadata (icon/version/publisher) only when building **on** Windows.
  - Bun runtime floor: glibc ≥ 2.17, kernel ≥ 3.10 w/ degradation, SSE4.2, Windows 10+.
- **Caveats:** reproducibility depends on pinned Bun version — pin it in your build image; `bun` the tool is itself a ~100 MB runtime baked into each output (hence ~100 MB binaries).

### C. ✅ (acceptable fallback) Vendored Node runtime + pi's esbuild bundle — "portable directory"

- **What:** replicate the managed-install layout offline: `node-v22.19-<platform>.tar.gz` + `pi-coding-agent` package tree (the npm package already ships a complete esbuild bundle in `dist/bundle/` with everything except `photon-node`, `jiti`, and optional natives) + the launcher shim pattern from `~/.pi/agent/bin/pi`.
- **Pros:** no compiler toolchain; debugging is easy (plain JS on disk); `pi update` machinery works if you ever gain network; can also drive pi's RPC SDK mode (`spawn("node", cliPath)`) which binaries can't.
- **Cons:** **needs Node's own glibc floor: official Node 22 binaries require glibc ≥ 2.28** (Node 18+ raised it from 2.17; current Node lines require ≥ 2.34 per Node BUILDING.md) — worse than the Bun binary's 2.17; musl needs the unofficial `linux-x64-musl` Node builds; much bigger footprint (149 MB `node_modules` + ~100 MB node runtime unpacked); you own the glue (PATH, shim, version pinning); "no node on target" is satisfied only in the sense that you *bring your own* private copy — some security teams dislike that more than a sealed binary.
- **Fit for pi:** good second option; this is literally what pi's own installer does when it "installs standalone Node" for you.

### D. ⚠️ Node.js Single Executable Applications (SEA)

State (nodejs.org docs, Oct 2026): `node --build-sea` exists (v25.5+; config-only workflow since 20.x + postject); CJS **and** ESM main supported; assets via `sea.getAsset*`; experimental **VFS** (`useVfs`, v26.9, stability 1.0 "Early development") finally allows `fs`-style reads and relative `require` from the mount.

Why it's a poor fit for pi **today**:
- **Native addons cannot load from the VFS** — must be extracted to a temp file and `process.dlopen()`-ed; pi-tui's helper would need code changes.
- pi relies on **worker entrypoints** (image-resize, codemode); SEA has no worker-embedding story comparable to Bun's explicit entrypoints.
- **jiti dynamic loading** of user extensions assumes a real filesystem relative to the install — the VFS is read-only and its module resolution is still maturing.
- Cross-platform SEA requires `useCodeCache:false`/`useSnapshot:false`; known postject bug produces broken ELF hash tables for arm64 builds made in arm64 containers.
- Still flagged experimental-ish (VFS stability 1.0); Node's own binary floor (glibc ≥ 2.28 for 22) applies anyway.
- You'd be rebuilding, from scratch, what pi's Bun build already solved (asset fallbacks, wasm embedding, worker embedding) — with an upstream that doesn't test this path.

**Verdict:** revisit if the Node SEA VFS stabilizes and pi ever adopts it upstream; not now.

### E. ⚠️ pkg / @yao-pkg/pkg

- `vercel/pkg` is **deprecated/archived** ("last release 5.8.1"; README points to forks and Node SEA).
- The maintained fork `@yao-pkg/pkg` supports `node22`/`node24` base binaries, platforms `linux`, `alpine` (musl), `linuxstatic`, `win`, `macos`, arch `x64`/`arm64`.
- Blockers for pi: targets max Node 24 but pi needs ≥ 22.19 features — OK version-wise, **but** (a) known Node 22 standard-mode **cross-compile regression** (broken `linux-arm64`/`win-x64` outputs; use `--sea` or `--no-bytecode` workarounds); (b) bytecode generation needs to *execute* target-arch code (QEMU/binfmt) unless bytecode is disabled; (c) `linuxstatic` **cannot load native addons** at all; (d) pkg's snapshot-filesystem path mapping (`/snapshot/...`) fights pi's `__dirname`/`execPath`-relative asset and WASM resolution — pi has no pkg-aware patches; (e) you'd be bolting a generic packager onto an app that ships its own purpose-built one.
- **Verdict:** no advantage over A/B for pi; only consider if organizational policy mandates "a pkg-built artifact."

### F. ❌ Other single-exe tools

- **nexe**: effectively dormant; same snapshot-FS issues as pkg; native addons painful.
- **boxednode** (Node + optional snapshot embedding): solid mechanism, but same per-platform Node floor and no answer for pi's workers/WASM/native trio that Bun's build doesn't already answer better.
- **deno compile**: Deno's `--compile` supports npm packages, but pi is a Node-targeted app (undici specifics, `node:` internals, native addons via `require`, jiti transforms). Runtime-compat risk is high and unsupported by pi upstream.
- **caxa / self-extracting archives**: still need a real Node on disk at extract time or ship one — that's strategy C with extra steps.

### G. Optional OS-native wrappers (around A/B/C artifacts — orthogonal)

- **Linux:** `dpkg -i` .deb / `rpm -i` .rpm install fine offline; **AppImage** gives mount-and-run portability (AppImage runtime needs FUSE, or `--appimage-extract`); plain `tar.gz → /opt/pi + symlink` is the most frictionless for offline hosts. Snap/Flatpak require stores/daemons — poor fit offline.
- **Windows:** the zip + PowerShell installer is simplest; **MSI** (WiX) gives GPO/SCCM-style silent offline deployment (`msiexec /i pi.msi /qn`); MSIX adds signing requirements; Chocolatey/Scoop offline installs need their tooling preinstalled.

---

## 6. Comparison matrix

| Strategy | Target needs node/npm? | Linux floor | musl | Win x64/arm64 | Size (compressed) | pi-upstream-tested | Build effort | Update story |
|---|---|---|---|---|---|---|---|---|
| **A. Official Bun archives** | No | glibc 2.17+ | ❌ build yourself | ✅ / ✅ | 41–44 MB | ✅ CI-built | none | replace archive |
| **B. Own Bun --compile** | No | glibc 2.17+ | ✅ musl target | ✅ / ✅ | ~40–50 MB | same mechanism | low (script exists) | replace archive |
| **C. Vendored Node + npm bundle** | No (private node) | glibc 2.28+ (Node 22) | unofficial node builds | ✅ / ✅ | ~90–120 MB | ✅ (it's the npm pkg) | medium (glue) | swap release dir |
| **D. Node SEA** | No | glibc 2.28+ | unofficial | ✅ / ⚠️ | ~90 MB | ❌ | high (patches) | rebuild |
| **E. yao-pkg** | No | glibc 2.28+ | ✅ `alpine` | ✅ / ⚠️ node22 regression | ~90 MB | ❌ | high (patches) | rebuild |
| **F. deno/nexe/caxa** | varies | varies | varies | varies | varies | ❌ | high + risky | — |
| **G. OS packages (deb/rpm/MSI/AppImage)** | wraps A/B/C | — | — | — | +small | n/a | low–medium | package manager |

---

## 7. Recommended offline bundle design (concrete)

**Artifact set ("offline kit") per pi version:**

```
portable-pi-kit/
├── pi-linux-x64.tar.gz        # from GitHub release (or your musl build in addition)
├── pi-linux-arm64.tar.gz
├── pi-linux-x64-musl.tar.gz   # optional, self-built (Alpine)
├── pi-windows-x64.zip
├── pi-windows-arm64.zip
├── SHA256SUMS                 # upstream file (or regenerate for the kit)
├── install.sh                 # Linux offline installer (below)
└── install.ps1                # Windows offline installer (below)
```

**Linux `install.sh` (sketch — verify → unpack per-user → PATH):**

```bash
#!/usr/bin/env sh
set -eu
KIT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ARCH=$(uname -m); case "$ARCH" in x86_64) A=x64;; aarch64) A=arm64;; *) echo "unsupported arch"; exit 1;; esac
ART="pi-linux-$A.tar.gz"
grep -F "$ART" "$KIT/SHA256SUMS" | sha256sum -c -   # integrity before anything else
DEST="${PI_INSTALL_DIR:-$HOME/.local/share/pi}"
mkdir -p "$DEST" && tar xzf "$KIT/$ART" -C "$DEST"
BIN="$DEST/pi/pi"; test -x "$BIN" && "$BIN" --version
mkdir -p "$HOME/.local/bin" && ln -sf "$BIN" "$HOME/.local/bin/pi"
echo 'export PATH="$HOME/.local/bin:$PATH"' # tell user to ensure PATH
```

**Windows `install.ps1` (sketch):**

```powershell
param([string]$InstallDir = "$env:LOCALAPPDATA\pi")
$kit = Split-Path -Parent $MyInvocation.MyCommand.Path
$arch = if ([Environment]::Is64BitOperatingSystem -and $env:PROCESSOR_ARCHITECTURE -eq 'ARM64') {'arm64'} else {'x64'}
$zip = Join-Path $kit "pi-windows-$arch.zip"
$hash = (Get-FileHash $zip -Algorithm SHA256).Hash
# compare against SHA256SUMS line for pi-windows-$arch.zip
Expand-Archive $zip -DestinationPath $InstallDir -Force
& "$InstallDir\pi\pi.exe" --version
# optionally: [Environment]::SetEnvironmentVariable('Path', ...+;$InstallDir\pi, 'User')
```

**Hardening & operational notes:**

- **Integrity/authenticity:** SHA-256 at minimum; for hostile media add detached signatures (minisign/cosign) of `SHA256SUMS`. Upstream releases are GitHub-attached artifacts (same trust domain as the npm package).
- **Updates offline:** the kit *is* the update unit — new version, new kit, re-run installer (idempotent; installs side-by-side under a version dir if you want rollback). `pi update` inside a binary install intentionally does not self-replace.
- **Extensions:** ship any needed extensions (and their `node_modules`) inside the kit and install to `~/.pi/agent/extensions/` in the installer; document that `pi package`/dep-installing features won't work air-gapped.
- **Windows shell:** optionally bundle PortableGit and write `"shellPath": "<kit>\\PortableGit\\bin\\bash.exe"` into `~/.pi/agent/settings.json` in the installer.
- **Air-gap flag:** `PI_TELEMETRY=0` in the launcher/env by default for air-gapped installs.
- **Determinism (if self-building, strategy B):** build in a pinned container (node 22 + bun 1.3.14), record `bun --version` + git SHA of pi into a `BUILD_INFO` file in the kit; keep the kit per git SHA.

---

## 8. Gaps / open questions

1. **Alpine/musl** official builds don't exist — if you need them, validate a self-built musl binary (upstream has never shipped one; QuickJS/photon WASM is runtime-agnostic so risk is mainly Bun's own musl maturity).
2. **Windows code signing** — unsigned exe ⇒ SmartScreen prompt on MotW-tagged copies. Decide: accept (zip + "Unblock" guidance), or buy an Authenticode cert and re-sign `pi.exe` in your kit pipeline (`signtool sign /fd SHA256 …`).
3. **Reproducible builds** of Bun-compiled binaries across Bun versions are not guaranteed byte-for-byte; if that matters, pin Bun and re-emit the kit from the same container image, and rely on your own SHA256SUMS rather than upstream's.
4. **SDK/RPC usage on the target** (spawning `node dist/cli.js` as a child) is impossible against a pure binary install — if some consumer needs pi-as-a-library offline, ship strategy C for that host instead.
5. pi's `pi package` (npm-backed package manager) and dep-installing extensions remain online-only; inventory any extensions you intend to preload.

---

## 9. Evidence / reproduction

```bash
# official binary works standalone, no node required:
curl -sLO https://github.com/earendil-works/pi/releases/download/v1.4.0/pi-linux-x64.tar.gz
tar xzf pi-linux-x64.tar.gz && ./pi/pi --version        # → 1.3.0

# glibc floor of the shipped binary:
objdump -T pi/pi | grep -oE 'GLIBC_[0-9.]+' | sort -uV | tail -1   # → GLIBC_2.17

# native helper + wasm are sidecars, resolution by exec-dir:
tar tzf pi-linux-x64.tar.gz | grep -E '\.node|\.wasm'
# pi/native/linux/prebuilds/linux-x64/linux-platform-x11.node
# pi/photon_rs_bg.wasm

# how upstream builds all six targets from one Linux host:
#   pi repo → scripts/build-binaries.sh + .github/workflows/build-binaries.yml (Bun 1.3.14)

# installed npm layout this replaces:
du -sh ~/.pi/agent/install/releases/1.3.0/node_modules    # → 149M
```

## 10. Sources

- pi upstream repo (cloned at research time, tag v1.3.0 source): `packages/coding-agent/package.json`, `src/config.ts` (`isBunBinary`, `getPackageDir`, `getCodemodeWorkerSpecifier`, self-update), `src/utils/photon.ts`, `src/modes/rpc/rpc-client.ts`, `scripts/build-coding-agent-bundle.mjs`, `scripts/build-binaries.sh`, `.github/workflows/build-binaries.yml`, `docs/windows.md`, `docs/termux.md`
- pi GitHub release v1.3.0 assets + `SHA256SUMS` (verified by download & extraction)
- Bun docs — *Bundler › Executables* (targets incl. musl, asset/worker/native embedding, bytecode, cross-compile, Windows flags, macOS codesign) and *Installation* (glibc ≥ 2.17, kernel ≥ 3.10, SSE4.2, musl binaries)
- Node.js docs — *Single Executable Applications* (`--build-sea`, ESM main, VFS v26.9 early-development, native-addon temp-file workaround, cross-platform caveats, postject arm64 bug) and *BUILDING.md* (official binary glibc floors: ≥ 2.28 for the 22 era, ≥ 2.34 for current lines)
- `vercel/pkg` README (deprecation notice, 5.8.1 final) and `@yao-pkg/pkg` docs (node22/node24 targets, alpine/linuxstatic, Node 22 cross-compile regression, linuxstatic-no-native-addons caveat)
- Local verification on this machine (Fedora-class Linux, x64): binary execution, `objdump`/`readelf` glibc analysis, archive listings, `ldd` output
