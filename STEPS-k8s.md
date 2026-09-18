# TrendWatch workshop su Kubernetes (kind + SIGHUP Distribution)

Variante Kubernetes di [STEPS.md](STEPS.md): stessi lab, stesse porte e stessi `export` dell'agente,
ma agentgateway e i server MCP girano in un cluster kind con la SIGHUP Distribution.

| Componente | Dove gira |
|---|---|
| Ollama + `qwen3:8b` | nativo sul Mac (GPU Metal); i pod lo raggiungono su `host.docker.internal:11434` |
| CNI | Cilium, dal modulo networking della SIGHUP Distribution (`k8s/furyctl.yaml`) |
| Trace | modulo tracing SIGHUP (Grafana Tempo + MinIO), visibili in Grafana del modulo monitoring |
| agentgateway 1.5.0 | chart ufficiale `agentgateway-standalone`, immagine pubblica; config del lab generata da `configs/` |
| Server MCP | 4 Deployment (`trends`, `trends-fixtures`, `workspace`, `publish`) con l'immagine pubblica di uv; gli script di `mcp-servers/` (invariati) arrivano da ConfigMap e sono serviti in HTTP |
| Identity provider | Zitadel + Postgres al posto di `scripts/fake_idp.py` |
| Agente `agent/trendwatch.py` | nativo, nel venv Python 3.14 creato da mise |

## Setup (una volta)

Serve Docker Desktop avviato: il nodo kind usa circa 5 GB di RAM, 8 GB assegnati a Docker bastano.
Lo stack compose usa le stesse porte: fermalo prima con `mise run down`.

```shell
cd trendwatch
mise install && mise run deps   # tool (kind, furyctl, kubectl, helm, yq...) e venv dell'agente
mise run ollama:pull            # avvia Ollama nativo e scarica qwen3:8b
mise run k8s:up                 # cluster kind + SIGHUP Distribution + server MCP + Zitadel (~15 min la prima volta)
mise run k8s:status
```

`k8s:up` esegue in ordine `k8s:cluster`, `k8s:distribution` (furyctl), `k8s:mcp` e `k8s:zitadel`;
ognuno si può rilanciare da solo, sono idempotenti.

## Come si lavora

Come nel compose, due terminali in `trendwatch/`:

- **T1, gateway**: al posto di `agentgateway -f configs/X.yaml` usa `mise run k8s:gw X`.
  Il task genera la config per Kubernetes da `configs/X.yaml`, fa `helm upgrade` e segue i log.
  Il Ctrl-C chiude solo i log.
- **T2, agente**: `export` e `python3 agent/trendwatch.py ...` esattamente come nelle docs.

| Cosa | URL |
|---|---|
| LLM API | `http://localhost:4000/v1` |
| MCP | `http://localhost:3000/mcp` |
| UI agentgateway | http://localhost:15000/ui |
| Grafana (trace: Explore → Tempo) | http://localhost:3001 |
| OTLP per l'agente | `localhost:4317` (default dell'agente: nessun export da cambiare) |
| Zitadel | http://zitadel.localtest.me:8080 |

`mise run k8s:ui` apre UI e Grafana.

## Lab

1. **Introduction** (agente → Ollama diretto): identico a [STEPS.md](STEPS.md), non usa il cluster.
2. **Proxy LLM traffic**: `mise run k8s:gw llm-basic`, poi `mise run k8s:gw token-budget`.
3. **Proxy MCP traffic**: `mise run k8s:gw mcp-single`, `mcp-multiplex`, `tool-filtering`.
   Le trace (agente + gateway nella stessa trace) sono in Grafana → Explore → Tempo → Search,
   service `trendwatch-agent` o `agentgateway`, al posto della UI di Jaeger.
4. **Prompt injection**: `mise run k8s:gw injection`, poi `prompt-guard`
   (il target `trends` punta a `trends-fixtures`, il server con `TRENDS_FIXTURES=1`).
5. **OpenAPI**: `mise run k8s:gw no-github-token`; per credential-injection esporta il token in **T1**:
   ```shell
   export GITHUB_TOKEN="<token>"
   mise run k8s:gw credential-injection
   ```
6. **MCP authentication**: niente `fake_idp.py`. I token li emette Zitadel:
   ```shell
   mise run k8s:tokens        # T2: rigenera zitadel.env (i token scadono dopo 12h)
   source zitadel.env         # al posto di: source fake_idp.env
   mise run k8s:gw mcp-identity   # T1
   ```
   Poi gli scenari come nelle docs: senza `MCP_TOKEN`, `export MCP_TOKEN=$READER_JWT`, `export MCP_TOKEN=$PUBLISHER_JWT`.
   Il digest salvato non finisce in `out/` del repo ma nel pod:
   `kubectl -n trendwatch exec deploy/workspace -- ls /work/out`

Per Gemini: `export GEMINI_API_KEY=...` in **T1** e le config `-gemini` (es. `mise run k8s:gw llm-basic-gemini`).

## Fine

```shell
mise run k8s:down      # elimina il cluster kind
mise run ollama:stop   # solo se Ollama l'ha avviato mise
```

## Cosa cambia rispetto al compose

- **Config dei lab**: restano quelle di `configs/`. `k8s/agentgateway/lab-to-k8s.yq` le adatta al volo:
  target `stdio` → `mcp.host` dei Service MCP, tracing verso `tempo-distributed-distributor.tracing.svc:4317`
  (`protocol: grpc`), sqlite su un PVC (`/data`), e per `mcp-identity` issuer/audience/JWKS di Zitadel.
  La regola `"publisher" in jwt.roles` diventa la mappa dei ruoli Zitadel
  `urn:zitadel:iam:org:project:<projectId>:roles`.
- **UI**: la config arriva da una ConfigMap, quindi le impostazioni salvate dalla UI non vengono scritte
  (con le config del repo il prompt logging è già attivo).
- **Server MCP**: sempre attivi e condivisi tra i lab (nel compose venivano riavviati a ogni `gw`);
  il feed pubblicato e i digest restano nei pod finché non vengono ricreati.
- **Zitadel**: stesso URL dal Mac e dai pod. `*.localtest.me` risolve a 127.0.0.1 (porta 8080 → NodePort),
  nel cluster un rewrite di CoreDNS lo manda al Service `zitadel`.

## Risorse della SIGHUP Distribution su kind

`k8s/furyctl.yaml` installa solo networking (Cilium), monitoring e tracing, e con `customPatches`
adatta la distribuzione a un nodo singolo con 8 GB:

- `prometheus-adapter`: richiesta da 3 GiB a 256 MiB (usa ~150 MiB) via `monitoring.prometheusAdapter.resources`
- richieste di memoria di kube-state-metrics, node-exporter, kube-proxy-metrics, prometheus-operator,
  Alertmanager, componenti Tempo e MinIO portate vicino all'uso reale
- `cilium-operator` a 1 replica (usa porte dell'host), HPA di Tempo con `maxReplicas: 1` e rollout del
  gateway Tempo senza surge (anti-affinity obbligatoria su un solo nodo)

Risultato: richieste di memoria del nodo dal 99% al ~37%.

## Troubleshooting

- `mise run k8s:status` mostra i pod; i log del gateway con `kubectl -n trendwatch logs deploy/agentgateway`.
- I pod di Tempo in CrashLoopBackOff subito dopo l'installazione ("bucket does not exist") ripartono da soli
  quando il job `minio-tracing-buckets-setup` ha creato i bucket.
- `mise run k8s:gw mcp-identity` senza `zitadel.env`: esegui prima `mise run k8s:tokens`
  (serve il project ID di Zitadel per l'audience).
