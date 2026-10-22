# Portable GitHub Copilot CLI (offline, local models)

[GitHub Copilot CLI](https://github.com/github/copilot-cli) can be carried onto an
offline machine the same way as pi: upstream ships standalone single-executable
archives (no Node.js/npm on the target), and since 2026-04-07 it can run against
your own OpenAI-compatible server with **no GitHub login** ("BYOK" + offline mode).

Checked against Copilot CLI **v1.0.103** (2026-10-22). Env-var reference below is
from `copilot help environment` in that binary.

## Release artifacts

All on the [releases page](https://github.com/github/copilot-cli/releases/latest),
with `SHA256SUMS.txt`:

| Target | Artifact | Size | Notes |
|---|---|---|---|
| Windows x64 | `copilot-win32-x64.zip` | 113 MB | one file: `copilot.exe` |
| Windows x64 | `copilot-x64.msi` | 106 MB | per-user install, adds itself to user `PATH` |
| Windows arm64 | `copilot-win32-arm64.zip` / `copilot-arm64.msi` | — | |
| Linux x64 / arm64 | `copilot-linux-{x64,arm64}.tar.gz` | 129 MB | one file: `copilot`, glibc ≥ 2.28 (RHEL 8+) |
| Linux musl x64 / arm64 | `copilot-linuxmusl-{x64,arm64}.tar.gz` | — | Alpine / old-glibc hosts |
| macOS x64 / arm64 | `copilot-darwin-{x64,arm64}.tar.gz` | — | |

Ignore the `github-copilot-*.tgz` files: those are the npm packages, which need Node 22+.

Verified on Linux x64: checksum OK; `objdump -T` → max `GLIBC_2.28`; `copilot --version`
runs with `env -i` and no Node on `PATH`.

## Install on Windows (offline)

On a connected machine, download the zip (or msi) and `SHA256SUMS.txt`, carry both over.

### Option A: zip (no installer, no admin)

```powershell
# verify: compare against the copilot-win32-x64.zip line in SHA256SUMS.txt
(Get-FileHash .\copilot-win32-x64.zip -Algorithm SHA256).Hash.ToLower()
Select-String copilot-win32-x64.zip .\SHA256SUMS.txt

$dir = "$env:LOCALAPPDATA\copilot"
Expand-Archive .\copilot-win32-x64.zip -DestinationPath $dir -Force

# add to the user PATH (permanent; open a new terminal afterwards)
$p = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($p -notlike "*$dir*") { [Environment]::SetEnvironmentVariable('Path', "$p;$dir", 'User') }

& "$dir\copilot.exe" --version      # → GitHub Copilot CLI 1.0.103.
```

### Option B: msi (silent, per-user)

```powershell
msiexec /i .\copilot-x64.msi /qn /l*v copilot-install.log
# installs to %LOCALAPPDATA%\GitHubCopilotCLI and appends it to the user PATH
```

The install folder and PATH entry come from the MSI's own `Directory`/`Environment`
tables; the silent install itself has not been run on a Windows box yet.

### Windows notes

- Copilot CLI uses PowerShell for its shell tool. Third-party guides and
  [issue #411](https://github.com/github/copilot-cli/issues/411) say it wants
  **PowerShell 7 (`pwsh`, ≥ 6)** rather than the built-in Windows PowerShell 5.1. On
  offline hosts, bring the PowerShell MSI along. Not verified on v1.0.103.
- The online route is `winget install GitHub.Copilot`. It needs network access, so
  it doesn't work on an offline host.

## Use with local models (vLLM, llama.cpp, Ollama)

Configuration is environment variables only:

| Variable | Value |
|---|---|
| `COPILOT_OFFLINE` | `true`: no GitHub auth, telemetry, web tools, GitHub MCP or auto-update. Requires `COPILOT_PROVIDER_BASE_URL`. |
| `COPILOT_PROVIDER_BASE_URL` | OpenAI-compatible endpoint, including `/v1` |
| `COPILOT_MODEL` | model id exactly as `GET /v1/models` lists it |
| `COPILOT_PROVIDER_TYPE` | `openai` (default) for vLLM/llama.cpp/Ollama; also `azure`, `anthropic` |
| `COPILOT_PROVIDER_API_KEY` | only if your server enforces `--api-key`; optional otherwise |
| `COPILOT_PROVIDER_MAX_PROMPT_TOKENS` / `_MAX_OUTPUT_TOKENS` | set these if the CLI misjudges your model's context (it doesn't know local model ids) |
| `COPILOT_HOME` | config/session dir, default `~/.copilot` (`%USERPROFILE%\.copilot`) |

The model must support **tool calling and streaming**. GitHub recommends a context of at
least **128k**. On vLLM, start the server with `--enable-auto-tool-choice --tool-call-parser …`
for your model; see [models-json.md](models-json.md) for the server side.

### Windows (PowerShell)

```powershell
# this session only
$env:COPILOT_OFFLINE = 'true'
$env:COPILOT_PROVIDER_BASE_URL = 'http://192.168.1.247:8000/v1'
$env:COPILOT_MODEL = 'Qwen3.8-Flash-Next'
copilot                                   # interactive
copilot -p "Summarise README.md" --allow-all-tools   # one-shot

# or permanent for the user (new terminals pick it up)
setx COPILOT_OFFLINE true
setx COPILOT_PROVIDER_BASE_URL http://192.168.1.247:8000/v1
setx COPILOT_MODEL Qwen3.8-Flash-Next
```

### Linux

```bash
export COPILOT_OFFLINE=true
export COPILOT_PROVIDER_BASE_URL=http://192.168.1.247:8000/v1   # vLLM
export COPILOT_MODEL=Qwen3.8-Flash-Next
copilot
```

### Other servers

| Server | `COPILOT_PROVIDER_BASE_URL` | `COPILOT_MODEL` |
|---|---|---|
| vLLM | `http://<host>:8000/v1` | `--served-model-name` value |
| llama.cpp `llama-server` (run with `--jinja` for tool calls) | `http://<host>:8080/v1` | `--alias` value (or any string with a single model) |
| Ollama | `http://localhost:11434/v1` | e.g. `qwen3-coder:30b` |

### Verified (Fedora, v1.0.103 linux-x64 → vLLM `Qwen3.8-Flash-Next` on the LAN)

1. ✅ `copilot -p "Reply with exactly: PONG"` in an `env -i` shell with no GitHub
   login, only `COPILOT_OFFLINE`/`_PROVIDER_BASE_URL`/`_MODEL` set → `PONG`.
2. ✅ Tool calls: asked it to write `hello.txt` and `cat` it → file created, shell
   tool ran, output returned (no API key, provider type left at default).

Not yet verified: the Windows zip/msi on real Windows, llama.cpp and Ollama, and
whether anything gets out with the network fully blocked. All verified runs had a
normal network around them.

## Caveats

- **License:** Copilot CLI is GitHub's proprietary software (see its `LICENSE.md`),
  not MIT like pi. Check the terms before you redistribute the binary inside an
  organisation.
- **Offline mode is only air-gapped if the endpoint is.** `COPILOT_OFFLINE` stops
  calls to GitHub. The CLI still sends your code to whatever `COPILOT_PROVIDER_BASE_URL`
  points at.
- **Updates:** offline mode disables auto-update. Without it, set `COPILOT_AUTO_UPDATE=false`
  (or `--no-auto-update`) so a binary install doesn't fetch newer versions. As with pi,
  the archive is the update unit.
- Unsigned-binary warnings (SmartScreen) were not checked.

## Sources

- [Copilot CLI now supports BYOK and local models — GitHub Changelog (2026-04-07)](https://github.blog/changelog/2026-04-07-copilot-cli-now-supports-byok-and-local-models/)
- [Install Copilot CLI — GitHub Docs](https://docs.github.com/en/copilot/how-tos/copilot-cli/install-copilot-cli)
- [github/copilot-cli releases](https://github.com/github/copilot-cli/releases)
- [github/copilot-cli issue #411 — PowerShell 6+ requirement](https://github.com/github/copilot-cli/issues/411)
- [How to install Copilot CLI on Windows 11 — Pureinfotech](https://pureinfotech.com/install-copilot-cli-windows-11/)
- [Copilot CLI BYOK and Local Model Support — AgentPatterns.ai](https://www.agentpatterns.ai/tools/copilot/copilot-cli-byok-local-models/)
- `copilot help environment` from the v1.0.103 binary (env-var reference)
