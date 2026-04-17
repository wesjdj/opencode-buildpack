# renku-opencode-buildpack

A Cloud Native Buildpack that installs [opencode](https://github.com/sst/opencode)
into a [Renku 2.0](https://renkulab.io) session image and wires your API keys
(and optional config) in from Renku User Secrets at session launch.

Designed to compose with SDSC's
[`renku-frontend-buildpacks`](https://github.com/SwissDataScienceCenter/renku-frontend-buildpacks)
`selector` builder, alongside any frontend (JupyterLab, VSCodium, RStudio, ttyd,
…). opencode itself is a terminal CLI, so it is installed as an **adjunct** — it
does not register a session process. You launch opencode from the integrated
terminal of whatever frontend you chose.

## How it fits into Renku

Renku 2.0 consumes plain OCI images. The SDSC selector builder produces those
images via CNB, selecting which frontends to install via the `BP_RENKU_FRONTENDS`
build-time env var. This buildpack follows the same pattern:

| Concern | Mechanism |
|---|---|
| Gating | `bin/detect` passes iff `BP_RENKU_FRONTENDS` contains `opencode`. |
| Install | `bin/build` downloads the matching `opencode-linux-<arch>[-variant].tar.gz` from `sst/opencode` releases and places the binary in `<layer>/bin`. |
| `PATH` | The layer's `env.launch/PATH.prepend` puts opencode on `$PATH` for every process type. |
| Secrets | A `<layer>/profile.d/opencode-init.sh` hook is sourced for every launch process; it reads Renku User Secrets from `$RENKU_OPENCODE_SECRETS_DIR` (default `/secrets`, matching Renku's `DEFAULT_SESSION_SECRETS_MOUNT_DIR`). |

## Building the image

You need [`pack`](https://buildpacks.io/docs/for-platform-operators/how-to/integrate-ci/pack/)
with experimental features enabled (`pack config experimental true`).

```bash
# 1. Package this buildpack into an OCI artifact:
make package                  # produces local image renku-opencode-buildpack:0.1.0

# 2. Build a Renku session image that bundles JupyterLab + opencode:
pack build my-registry/my-session:latest \
  --builder ghcr.io/swissdatasciencecenter/renku-frontend-buildpacks/selector:0.4.0 \
  --buildpack renku-opencode-buildpack:0.1.0 \
  --env BP_RENKU_FRONTENDS=jupyterlab,opencode \
  --path samples/jupyterlab-opencode
```

Or drive it from a `project.toml` in your Renku project — see
[`samples/jupyterlab-opencode/project.toml`](samples/jupyterlab-opencode/project.toml).

### Build-time env vars

| Var | Default | Purpose |
|---|---|---|
| `BP_RENKU_FRONTENDS` | — | Must include `opencode` for this buildpack to fire. |
| `BP_OPENCODE_VERSION` | `latest` | Release tag to install (e.g. `v1.4.6`). |
| `BP_OPENCODE_VARIANT` | `auto` | `standard`, `baseline`, `musl`, `baseline-musl`. `auto` picks baseline when the build host lacks AVX2 and musl on Alpine. |
| `BP_OPENCODE_SECRETS_DIR` | `/secrets` | Default value baked into the image for the launch-time secrets mount. Runtime override still possible via the session env. |

## Configuring secrets in Renku

In the Renku 2.0 UI, open your project → **Secrets** → add a secret. The
**filename** you pick is the file that will appear under `/secrets/<filename>`
inside the session container (read-only, on a memory-backed tmpfs volume,
decrypted at session start by an init container).

The launch hook looks for the following filenames (case-sensitive). You can
choose the filename freely when you create the secret in Renku; pick whichever
form you prefer for each provider.

### API keys (mapped to env vars)

Any of these filenames get exported as the matching env var, which opencode's
provider SDKs read natively:

| Filename (either form) | Exported env var |
|---|---|
| `ANTHROPIC_API_KEY` or `anthropic-api-key` | `ANTHROPIC_API_KEY` |
| `OPENAI_API_KEY` or `openai-api-key` | `OPENAI_API_KEY` |
| `OPENROUTER_API_KEY` or `openrouter-api-key` | `OPENROUTER_API_KEY` |
| `GROQ_API_KEY` or `groq-api-key` | `GROQ_API_KEY` |
| `GOOGLE_GENERATIVE_AI_API_KEY` or `google-generative-ai-api-key` | `GOOGLE_GENERATIVE_AI_API_KEY` |
| `GEMINI_API_KEY` or `gemini-api-key` | `GEMINI_API_KEY` |
| `DEEPSEEK_API_KEY` or `deepseek-api-key` | `DEEPSEEK_API_KEY` |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` | same names |

If the env var is already set at launch (e.g. via Renku's env-var secret
injection), the hook leaves it alone.

### Whole config files

| Filename | Staged to | Purpose |
|---|---|---|
| `opencode.json` / `opencode.jsonc` / `config.json` | `~/.config/opencode/opencode.json` | User-level opencode config — custom providers, default model, keybinds, etc. |
| `auth.json` | `~/.local/share/opencode/auth.json` | OAuth refresh tokens / enterprise URLs produced by `opencode auth login`. |

Existing files in those locations are never overwritten — run
`opencode auth login` inside the session and the hook becomes a no-op for that
file.

### Choosing a different mount path

If your Renku project has changed `secrets_mount_directory` away from
`/secrets`, set `RENKU_OPENCODE_SECRETS_DIR` on the Session Launcher and the
hook will read from there instead.

## Using it in a Renku Session Launcher

1. Push the built session image to a registry Renku can pull from.
2. In Renku, **Project → Sessions → New Session Launcher** → point at your
   image tag.
3. Add secrets under the project's Secrets tab with filenames from the tables
   above. Attach the relevant secrets to the Session Launcher.
4. Start a session, open a terminal in JupyterLab / VSCodium / ttyd, run
   `opencode`.

## Repository layout

```
.
├── buildpack.toml          # CNB metadata (api 0.11, id renku/opencode, targets)
├── package.toml            # pack buildpack package manifest
├── project.toml            # local smoke-test harness
├── bin/
│   ├── detect              # BP_RENKU_FRONTENDS gate + build plan
│   ├── build               # download + install opencode into the launch layer
│   └── opencode-init.sh    # profile.d hook: secrets → env vars / config files
├── samples/
│   ├── jupyterlab-opencode/project.toml
│   └── vscodium-opencode/project.toml
├── Makefile                # package / sample / run / shellcheck
└── .github/workflows/publish.yml
```

## Development

```bash
make shellcheck     # lint bash
make package        # build the buildpack OCI artifact
make sample         # build a jupyterlab+opencode session image end-to-end
make run            # run the sample locally, mounting ./samples/_secrets at /secrets
```

To smoke-test secret provisioning locally:

```bash
mkdir -p samples/_secrets
echo "sk-ant-..." > samples/_secrets/ANTHROPIC_API_KEY
make run
# inside the container:
# env | grep ANTHROPIC_API_KEY
# opencode
```

## Design notes

- **Why gate on `BP_RENKU_FRONTENDS`?** To compose cleanly with the SDSC
  `selector` builder. Without the gate the buildpack would unconditionally
  attach itself to every build, including ones that never asked for opencode.
- **Why adjunct (no process), not frontend?** opencode is a TUI/CLI. It should
  run *inside* a terminal that a frontend provides (JupyterLab terminal,
  VSCodium integrated terminal, ttyd). Making it a default process would
  conflict with JupyterLab/etc. on `$RENKU_SESSION_PORT`.
- **Why `profile.d` for secrets, not an entrypoint wrapper?** The CNB launcher
  sources `<layer>/profile.d/*.sh` for every process type automatically. That
  means env vars propagate into terminal shells without us having to replace
  the frontend entrypoint.
- **Why never overwrite existing config/auth?** If the user runs
  `opencode auth login` inside a session, the resulting `auth.json` is their
  source of truth. The secret mount is a *seed*, not a master copy.
