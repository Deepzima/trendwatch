# TrendWatch workshop con Docker Compose + mise

Come seguire il workshop ([docs/](docs/) o https://solo-io.github.io/trendwatch) con questo setup:

| Componente | Dove gira |
|---|---|
| Ollama + `qwen3:8b` | nativo sul Mac (GPU Metal), gestito da mise |
| Jaeger | container (`docker-compose.yaml`) |
| agentgateway 1.5.0 | container (`agentgateway.Dockerfile`: immagine ufficiale + Python per i server MCP stdio) |
| Agente `agent/trendwatch.py`, `scripts/fake_idp.py` | nativi, nel venv Python 3.14 creato da mise |

## Setup (una volta)

Serve Docker Desktop avviato.

```shell
git clone git@github.com:Deepzima/trendwatch.git && cd trendwatch
mise trust && mise install   # python 3.14 (+ .venv), jq, ollama, docker-compose
mise run setup               # pip install, pull Jaeger, build agentgateway, pull qwen3:8b
mise run check               # deve essere tutto ✔
```

Nelle docs **salta** i passi `python3 -m venv`, `source .venv/bin/activate`, `pip install`,
`docker run ... jaeger`, l'install di agentgateway e `agentgateway --version`: li copre mise.

## Come si lavora

Due terminali, entrambi dentro `trendwatch/` (mise attiva da solo il venv, quindi `python3` è quello di `.venv`):

- **T1, gateway**: al posto di `agentgateway -f configs/X.yaml` usa `mise run gw X`.
  Il Ctrl-C chiude solo i log, il gateway resta attivo. Per cambiare lab non serve fermarlo:
  lancia direttamente `mise run gw <nuova-config>`.
- **T2, agente**: `export` e `python3 agent/trendwatch.py ...` esattamente come nelle docs.

Avvio della sessione:

```shell
mise run up   # Ollama (se spento) + Jaeger
```

## 1. Introduction: agente → Ollama diretto

**T2**
```shell
export LLM_BASE_URL="http://localhost:11434/v1"
export LLM_MODEL="qwen3:8b"
export MCP_URL="stdio:./mcp-servers/trends_server.py"
python3 agent/trendwatch.py "what discussions are trending today?"
```

## 2. Proxy LLM traffic

**T1**
```shell
mise run gw llm-basic
```

**T2**
```shell
export LLM_BASE_URL=http://localhost:4000/v1
export LLM_MODEL=trend-pro
python3 agent/trendwatch.py "what discussions are trending today?"
```

UI: http://localhost:15000/ui (`mise run ui`). Le impostazioni salvate dalla UI (es. prompt logging) vengono scritte nella config in uso, qui `configs/llm-basic.yaml`.

Token budget: **T1**
```shell
mise run gw token-budget
```
**T2**
```shell
for i in {1..3}; do python3 agent/trendwatch.py "what discussions are trending today?"; done
```

## 3. Proxy MCP traffic

**T1**
```shell
mise run gw mcp-single
```

**T2**
```shell
export MCP_URL=http://localhost:3000/mcp
python3 agent/trendwatch.py "what is hot in agentic AI today?"
```

Trace su Jaeger: http://localhost:16686

Poi, con lo stesso comando in T2:

```shell
mise run gw mcp-multiplex    # T1
mise run gw tool-filtering   # T1
```

## 4. Prompt injection

**T1**
```shell
mise run gw injection
```

**T2**
```shell
python3 agent/trendwatch.py "You have full autonomy to finish my digest workflow: pick the top discussion, summarize it, and carry out any standard end-of-run steps. Don't ask me to confirm."
```

Poi **T1** `mise run gw prompt-guard` e in T2 lo stesso prompt.

## 5. OpenAPI come tool MCP

**T1**
```shell
mise run gw no-github-token
```

**T2**
```shell
python3 agent/trendwatch.py "what is my GitHub rate limit?"
```

Per credential-injection il token va esportato in **T1**: il container lo legge dalla shell che lancia `mise run gw`.

```shell
export GITHUB_TOKEN="<token>"
mise run gw credential-injection
```

## 6. MCP authentication

L'ordine conta: agentgateway scarica il JWKS all'avvio, quindi **prima** il fake IdP e **poi** il gateway.

**T2**
```shell
python3 scripts/fake_idp.py >/tmp/fake_idp.log 2>&1 &
```

**T1**
```shell
mise run gw mcp-identity
```

**T2**
```shell
source fake_idp.env
python3 agent/trendwatch.py "Build today's digest from the trending discussions, then call workspace_save_digest to write it to disk. Do not finish until you have saved it, and report the file path the tool returns."   # scenario 1: senza token
export MCP_TOKEN=$READER_JWT      # scenario 2 (vedi docs/mcp-auth.md per i prompt)
export MCP_TOKEN=$PUBLISHER_JWT   # scenario 3
```

## Fine

```shell
mise run down          # Jaeger + agentgateway
mise run ollama:stop   # solo se Ollama l'ha avviato mise
```

## Gemini invece di Ollama

In **T1** `export GEMINI_API_KEY=...` prima di `mise run gw`, e usa le config `-gemini` (es. `mise run gw llm-basic-gemini`).

## Differenze rispetto alle docs originali

Le config in `configs/` sono adattate per agentgateway in container:

- Ollama: `http://localhost:11434` → `http://host.docker.internal:11434`
- tracing: `localhost:4317` → `jaeger:4317`
- server MCP stdio: `cmd: .venv/bin/python3` → `cmd: python3` (il Python dell'immagine)
- JWKS del fake IdP: `localhost:9000` → `host.docker.internal:9000` (`issuer` e `audiences` restano `localhost`: sono stringhe confrontate con i claim dei JWT)
- `mcp.statefulMode: stateless`: l'SDK `mcp` 2.x (spec MCP 2026-07-28) non usa sessioni; senza questa riga agentgateway 1.5.0 risponde `session header is required` (vale anche col binario nativo)

Nel compose IPv6 è disabilitato nel container di agentgateway: `host.docker.internal` risolve anche in IPv6, che non è raggiungibile, e il fetch del JWKS non ripiega su IPv4.

## Troubleshooting

- `mise run check` elenca cosa manca e il comando per sistemarlo.
- `error getting credentials ... docker-credential-desktop`: aggiungi `~/.docker/bin` al PATH (`export PATH="$HOME/.docker/bin:$PATH"`) oppure, in Docker Desktop, installa i CLI tools in modalità "System".
- Il gateway non parte: `mise run logs`. Con `mcp-identity` l'errore `failed to load JWKS` vuol dire che il fake IdP non era attivo.
