#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Launch-time provisioner for opencode in a Renku 2.0 session.
#
# Sourced by the CNB launcher (Cloud Native Buildpacks mounts all files under
# <layer>/profile.d/ as shell profiles, sourcing them for every process type).
# That means env vars exported here propagate into the jupyterlab / vscodium /
# ttyd terminal where the user will actually run `opencode`.
#
# Contract with Renku 2.0:
#   Renku decrypts user secrets into a tmpfs volume mounted read-only into the
#   session container. The mount path defaults to /secrets and is configurable
#   per project (see DEFAULT_SESSION_SECRETS_MOUNT_DIR_STR in renku-data-services).
#   Each secret is written to a file whose name is chosen by the user when they
#   add the secret. We look for specific, documented filenames.
#
# What this hook does:
#   1. Export API-key env vars from files matching known provider names, but
#      only if the user hasn't already set them via Renku's env-var secret
#      injection path.
#   2. Stage a user-supplied opencode.json into ~/.config/opencode/ if present.
#   3. Stage a user-supplied auth.json into $XDG_DATA_HOME/opencode/ if present.
#
# This is deliberately idempotent and silent on "secret not mounted" so that
# sessions without opencode secrets still launch cleanly.
# -----------------------------------------------------------------------------

_renku_opencode_init() {
  local secrets_dir="${RENKU_OPENCODE_SECRETS_DIR:-/secrets}"
  local config_dir="${XDG_CONFIG_HOME:-${HOME}/.config}/opencode"
  local data_dir="${XDG_DATA_HOME:-${HOME}/.local/share}/opencode"

  mkdir -p "${config_dir}" "${data_dir}" 2>/dev/null || return 0
  chmod 0700 "${config_dir}" "${data_dir}" 2>/dev/null || true

  # 1. Map mounted secret files to env vars that opencode's provider SDKs
  #    read natively. Only set if not already set (env-var injection wins).
  if [ -d "${secrets_dir}" ]; then
    local pair file var val
    for pair in \
      "ANTHROPIC_API_KEY:ANTHROPIC_API_KEY" \
      "anthropic-api-key:ANTHROPIC_API_KEY" \
      "OPENAI_API_KEY:OPENAI_API_KEY" \
      "openai-api-key:OPENAI_API_KEY" \
      "OPENROUTER_API_KEY:OPENROUTER_API_KEY" \
      "openrouter-api-key:OPENROUTER_API_KEY" \
      "GROQ_API_KEY:GROQ_API_KEY" \
      "groq-api-key:GROQ_API_KEY" \
      "GOOGLE_GENERATIVE_AI_API_KEY:GOOGLE_GENERATIVE_AI_API_KEY" \
      "google-generative-ai-api-key:GOOGLE_GENERATIVE_AI_API_KEY" \
      "GEMINI_API_KEY:GEMINI_API_KEY" \
      "gemini-api-key:GEMINI_API_KEY" \
      "DEEPSEEK_API_KEY:DEEPSEEK_API_KEY" \
      "deepseek-api-key:DEEPSEEK_API_KEY" \
      "AWS_ACCESS_KEY_ID:AWS_ACCESS_KEY_ID" \
      "AWS_SECRET_ACCESS_KEY:AWS_SECRET_ACCESS_KEY" \
      "AWS_SESSION_TOKEN:AWS_SESSION_TOKEN"
    do
      file="${pair%%:*}"
      var="${pair##*:}"
      if [ -z "${!var-}" ] && [ -s "${secrets_dir}/${file}" ]; then
        val="$(tr -d '\r\n' < "${secrets_dir}/${file}")"
        export "${var}=${val}"
      fi
    done

    # 2. Stage config.json / opencode.json from the secrets mount (user may
    #    keep a whole config with custom providers there). User's shell config
    #    file wins if it already exists.
    local src
    for src in "opencode.json" "opencode.jsonc" "config.json"; do
      if [ -s "${secrets_dir}/${src}" ] && [ ! -e "${config_dir}/opencode.json" ] && [ ! -e "${config_dir}/opencode.jsonc" ]; then
        local dest="${config_dir}/opencode.json"
        [ "${src##*.}" = "jsonc" ] && dest="${config_dir}/opencode.jsonc"
        cp "${secrets_dir}/${src}" "${dest}"
        chmod 0600 "${dest}"
        break
      fi
    done

    # 3. Stage auth.json (OAuth refresh tokens, enterprise URLs, etc.) if
    #    provided. opencode rewrites this on token refresh, so we copy (not
    #    symlink) and never overwrite an existing one the user has created
    #    via `opencode auth login`.
    if [ -s "${secrets_dir}/auth.json" ] && [ ! -e "${data_dir}/auth.json" ]; then
      cp "${secrets_dir}/auth.json" "${data_dir}/auth.json"
      chmod 0600 "${data_dir}/auth.json"
    fi
  fi
}

_renku_opencode_init
unset -f _renku_opencode_init
