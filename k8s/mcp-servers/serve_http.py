# Serve uno script MCP del workshop (invariato) in Streamable HTTP su /mcp.
# Gli script chiamano mcp.run() solo sotto __main__: qui li importiamo e scegliamo il trasporto.
import importlib
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
module = importlib.import_module(os.environ["MCP_MODULE"])  # trends_server | workspace_server | publish_server
module.mcp.run(
    transport="streamable-http",
    host="0.0.0.0",  # col default 127.0.0.1 il Service non lo raggiunge
    port=int(os.environ.get("MCP_PORT", "8000")),
    stateless_http=True,  # spec MCP 2026-07-28: niente sessioni
)
