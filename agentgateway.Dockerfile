# agentgateway ufficiale + Python: i lab lanciano i server MCP (mcp-servers/*.py) via stdio
# da dentro agentgateway, e l'immagine ufficiale (distroless) non ha Python.
ARG AGW_VERSION=v1.5.0
FROM ghcr.io/agentgateway/agentgateway:${AGW_VERSION} AS agentgateway

# Il binario richiede glibc >= 2.39: serve una base trixie (bookworm ha 2.36)
FROM python:3.14-slim-trixie
COPY --from=agentgateway /app/agentgateway /usr/local/bin/agentgateway
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt
ENV AGENTGATEWAY_ENV=container
WORKDIR /workshop
ENTRYPOINT ["agentgateway"]
