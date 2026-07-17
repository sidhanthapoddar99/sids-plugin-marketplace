# Agent / LLM integration — the provider boundary inside an app

Conventions for LLM and agent-integration code living inside an app. The governing idea: an LLM provider is an **external provider boundary**, shaped exactly like every other N-provider integration — so the structural pattern is already owned at L4, and this file cites it rather than restating it. What this file owns is the AI-specific placement calls: where prompts live, where streaming/tool-call plumbing sits, where evals go, and which SDKs are the typed defaults.

## It is a provider boundary — reuse the adapter-modules pattern

One adapter module per provider, behind one internal interface. This is the **same adapter-modules pattern** the modularity doctrine prescribes for N interchangeable providers — the `base.py` contract, the self-contained per-provider folder, the generic engine that reads adapters only through the contract. That pattern is owned by `references/4-feature/01_feature-folders.md` § adapter-modules; do not restate its rules here, apply them:

- The provider-agnostic engine (your agent loop, your orchestration) talks to an internal `LLMClient`/`base` interface.
- Each provider (Anthropic, others) is a self-contained adapter mapping its API to that interface.
- Adding or swapping a provider is adding/replacing one adapter — engine code never learns a provider's name.

Provider-specific branches (`if provider == "x"`) leaking into engine code is the drift symptom audits flag.

## Where prompts live

Prompts are **versioned artifacts, not inline strings** scattered through feature code. Keep them as files/templates in one place the feature owns (e.g. `prompts/` beside the feature, or a `prompts.py` with named constants) so they are diff-reviewable and swappable. A prompt buried in an f-string three call-levels deep cannot be reviewed, evaluated, or rolled back.

## Streaming and tool-call plumbing

Isolate streaming, tool-call dispatch, and ret/backoff inside the adapter — the feature's `service.py` asks for a result (or an async stream of tokens) and never touches SDK-specific event shapes. Tool definitions the model can call are declared once and routed through the same typed dispatch; a tool handler calls the app's existing service layer, it does not embed business logic (mirror of the MCP rule, `references/3-app/08-ai/00_mcp-servers.md`).

## Evals and fixtures

Model-dependent behaviour needs regression coverage. Place evals/fixtures beside the feature's tests (`tests/evals/`, recorded prompt→expected-shape cases), co-located per L4 (`references/4-feature/05_caps-and-extraction.md`). Keep a small set of golden cases that must pass before a prompt or model change ships.

## SDK choices — typed defaults

| Surface | Default | Note |
|---|---|---|
| Backend LLM calls | **Anthropic SDK direct** (model ids/params: the `claude-api` skill) | one adapter wraps it behind the internal interface |
| Frontend streaming UI | **Vercel AI SDK** | only for the streaming/UX layer in the web app; keys never reach it — see below |

Model IDs and generation params (temperature, max tokens, model name) live in **config** (`config.yaml` / env), never hard-coded in feature code — swapping a model is a config edit, not a code change. Check the latest model ids/pricing via the `claude-api` skill; do not pin from memory.

## Anti-patterns

- **Provider name in engine code** — route through the adapter interface.
- **Prompts inline in features** — version them as files; scattered strings can't be reviewed or evaluated.
- **Hard-coded model IDs / params** — config-driven, so a model swap is one edit.
- **Tool handlers with business logic** — call the service layer.
- **SDK event shapes leaking out of the adapter** — the feature sees a result or a token stream, not raw provider events.
- **No evals** on model-dependent behaviour — silent regressions on every prompt/model change.

## See also

- `references/4-feature/01_feature-folders.md` — the adapter-modules pattern this reuses (owner)
- `references/3-app/08-ai/00_mcp-servers.md` — MCP servers (a related tool-surface boundary)
- `references/3-app/08-ai/02_ai-keys-and-safety.md` — key usage, proxy route, prompt-injection posture
- `references/2-repo/03-env-config/01_per-service-config.md` — model IDs/params in config
- the `claude-api` skill — Anthropic model ids, params, streaming, tool use
