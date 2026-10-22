# `models.json` for offline inference servers (llama.cpp, vLLM)

How to point an offline pi install at a local OpenAI-compatible server. Checked
against pi **v1.4.0** (`docs/models.md`, `docs/models-configuration.md` in the
release archive).

## Where the files go

| OS | Path |
|---|---|
| Linux / macOS | `~/.pi/agent/models.json` + `~/.pi/agent/settings.json` |
| Windows | `%USERPROFILE%\.pi\agent\models.json` + `settings.json` |
| Anywhere | override the directory with `PI_CODING_AGENT_DIR=/path/to/agent-dir` |

The container in [`docker/`](../docker/README.md) writes the same files for you
from `PI_LLM_*` env vars (see `docker/entrypoint.sh`).

## vLLM

Start the server with an explicit model name, so the `id` in `models.json` stays
stable:

```bash
vllm serve nvidia/Qwen3.8-Flash-Next-FP4-Local \
  --served-model-name Qwen3.8-Flash-Next \
  --host 0.0.0.0 --port 8000 --max-model-len 262144
curl -s http://192.168.1.247:8000/v1/models     # "id" here == "id" in models.json
```

`~/.pi/agent/models.json`:

```json
{
  "$schema": "https://pi.dev/schemas/models.schema.json",
  "providers": {
    "vllm": {
      "name": "vLLM (LAN)",
      "baseUrl": "http://192.168.1.247:8000/v1",
      "api": "openai-completions",
      "apiKey": "local",
      "compat": { "thinkingFormat": "qwen-chat-template" },
      "models": [
        {
          "id": "Qwen3.8-Flash-Next",
          "reasoning": true,
          "contextWindow": 262144,
          "maxTokens": 16384,
          "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
        }
      ]
    }
  }
}
```

## llama.cpp (`llama-server`, single model)

Use `--jinja` so the model's chat template handles tools and thinking. `--alias`
sets the model id the server reports:

```bash
llama-server -m ~/models/<your-model>.gguf \
  --alias halogen-qwen3.8-flash-next \
  --jinja -c 131072 -ngl 999 --host 127.0.0.1 --port 8080
curl -s http://127.0.0.1:8080/v1/models
```

`~/.pi/agent/models.json`:

```json
{
  "$schema": "https://pi.dev/schemas/models.schema.json",
  "providers": {
    "llamacpp": {
      "name": "llama.cpp (local)",
      "baseUrl": "http://127.0.0.1:8080/v1",
      "api": "openai-completions",
      "apiKey": "local",
      "compat": { "thinkingFormat": "qwen-chat-template", "supportsDeveloperRole": false },
      "models": [
        {
          "id": "halogen-qwen3.8-flash-next",
          "reasoning": true,
          "contextWindow": 131072,
          "maxTokens": 8192,
          "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
        }
      ]
    }
  }
}
```

**Alternative:** pi also has a built-in `llama.cpp` provider for the llama.cpp
*router* (`llama-server --models-dir ~/models` without `-m`). Connect it with
`/login llama.cpp` or `LLAMA_BASE_URL=http://127.0.0.1:8080`, then load models
with `/llama`. That route needs no `models.json`. See pi's `docs/llama-cpp.md`.

## Make it the default

Both providers can live in one `models.json` (merge the `providers` objects).
Pick the startup model in `~/.pi/agent/settings.json`:

```json
{
  "defaultProvider": "vllm",
  "defaultModel": "Qwen3.8-Flash-Next",
  "enableInstallTelemetry": false
}
```

Or per run: `pi --model vllm/Qwen3.8-Flash-Next` / `pi --model llamacpp/halogen-qwen3.8-flash-next:off`.

## Field notes

| Field | Why |
|---|---|
| `api: "openai-completions"` | both servers speak `/v1/chat/completions` |
| `apiKey` | must be set (any string) or pi treats the model as unauthenticated and hides it; use `"$VLLM_API_KEY"` if the server was started with `--api-key` |
| `baseUrl` | include `/v1`; from inside a container use `host.containers.internal` (see [docker networking matrix](../docker/README.md#networking-matrix-verified-on-fedora--rootless-podman--pasta)) |
| `reasoning` + `compat.thinkingFormat` | `qwen-chat-template` sends `chat_template_kwargs.enable_thinking` (Qwen-family); drop both for non-thinking models |
| `compat.supportsDeveloperRole: false` | some llama.cpp chat templates reject the `developer` role; send `system` instead |
| `contextWindow` / `maxTokens` | keep ≤ the server's `--max-model-len` / `-c`; pi uses them for compaction |
| `cost` all zero | local inference; keeps usage display at $0 |

All fields: pi's `docs/models-configuration.md` (shipped in the release archive).

## Check it

```bash
pi --list-models                                  # both providers listed?
pi --model vllm/Qwen3.8-Flash-Next -p "Reply with exactly: OK" </dev/null
```

`pi -p` also reads piped stdin; in scripts close it (`</dev/null`) or the call waits.

Verified 2026-10-22 with pi 1.4.0 (bare binary, no network except the LAN
server, no Node): both entries parse (`--list-models`); vLLM answered with thinking `off`
and `medium`. The llama.cpp entry is the same shape the container verified
against llama-server on pi 1.3.0. It was not re-run on 1.4.0 (no server was up).
