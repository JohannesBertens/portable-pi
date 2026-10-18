#!/usr/bin/env bash
# Generates pi's config from PI_LLM_* environment variables, then execs pi.
# Runs entirely offline; nothing here reaches the internet.
set -euo pipefail

AGENT_DIR="${PI_AGENT_DIR:-/root/.pi/agent}"
PROVIDER_ID="${PI_LLM_PROVIDER_ID:-local-llm}"
BASE_URL="${PI_LLM_BASE_URL:-}"
MODEL_ID="${PI_LLM_MODEL:-local-model}"
API="${PI_LLM_API:-openai-completions}"
API_KEY="${PI_LLM_API_KEY:-local}"
CTX="${PI_LLM_CONTEXT_WINDOW:-262144}"
MAXTOK="${PI_LLM_MAX_TOKENS:-8192}"
THINKING="${PI_LLM_THINKING_FORMAT:-}"        # e.g. qwen-chat-template; empty = omit
NO_DEV_ROLE="${PI_LLM_NO_DEVELOPER_ROLE:-0}"  # 1 => supportsDeveloperRole:false (some llama.cpp servers)

mkdir -p "$AGENT_DIR"

if [ -z "$BASE_URL" ]; then
    cat >&2 <<'EOF'
ERROR: PI_LLM_BASE_URL is not set.

Point it at a local OpenAI-compatible endpoint, for example:
  llama.cpp on the same host (bridge network):  http://host.containers.internal:8080/v1
  llama.cpp on the same host (--network=host):  http://127.0.0.1:8080/v1
  vLLM on another machine:                      http://192.168.1.247:8000/v1
EOF
    exit 1
fi

# Soft reachability check — warn loudly but still start (useful when you
# bring the LLM server up after the container).
PROBE_URL="${BASE_URL%/}/models"
if PROBE="$(curl -s -m 3 -o /dev/null -w '%{http_code}' "$PROBE_URL" || true)"; then
    [ "$PROBE" = "200" ] || echo "note: $PROBE_URL answered HTTP $PROBE (expected 200)" >&2
else
    echo "note: could not reach $PROBE_URL yet — start pi anyway, check the server" >&2
fi

# Build the optional compat object.
COMPAT=""
[ -n "$THINKING" ] && COMPAT="\"thinkingFormat\": \"$THINKING\""
[ "$NO_DEV_ROLE" = "1" ] && COMPAT="${COMPAT:+$COMPAT, }\"supportsDeveloperRole\": false"

if [ ! -f "$AGENT_DIR/models.json" ] || [ "${PI_FORCE_CONFIG:-0}" = "1" ]; then
    cat > "$AGENT_DIR/models.json" <<EOF
{
  "providers": {
    "$PROVIDER_ID": {
      "name": "Local LLM ($BASE_URL)",
      "baseUrl": "$BASE_URL",
      "api": "$API",
      "apiKey": "$API_KEY",
      "models": [
        {
          "id": "$MODEL_ID",
          "name": "$MODEL_ID",
          "reasoning": true,
          "input": ["text"],
          "contextWindow": $CTX,
          "maxTokens": $MAXTOK,
          "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
          "compat": {${COMPAT}}
        }
      ]
    }
  }
}
EOF
    cat > "$AGENT_DIR/settings.json" <<EOF
{
  "defaultProvider": "$PROVIDER_ID",
  "defaultModel": "$MODEL_ID",
  "enableInstallTelemetry": false
}
EOF
    echo "pi config generated in $AGENT_DIR (provider '$PROVIDER_ID' -> $BASE_URL)" >&2
else
    echo "using existing config in $AGENT_DIR (set PI_FORCE_CONFIG=1 to regenerate)" >&2
fi

exec "$@"
