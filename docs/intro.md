# Introduction

This workshop helps you explore some of the agentic capabilities of [agentgateway](https://agentgateway.dev/).
The workshop is designed to be self-contained with a minimum of external dependencies.

## Local model

[Ollama](https://ollama.com/) is installed and configured with a [qwen3](https://ollama.com/library/qwen3) model, so inference calls are local.

```shell
ollama list
```

By default, the ollama server listens on port 11434.

To make sure that the model is available and produces a response, send a test request to the local LLM:

```shell
curl -s http://localhost:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen3:8b","messages":[{"role":"user","content":"say hi"}]}' | jq
```

## The agentic scenario: Trendwatch

A git repository is cloned locally, containing an agent named "Trendwatch" (written in python), and a set of example MCP servers.

```shell
cd trendwatch
```

Trendwatch is an AI agent that tells you what is hot in agentic AI today.
It leverages a set of MCP servers to read trending discussions, build and save a digest on the topics you care about, and can "publish" these digests.

Run the following `tree` command to view the main project files:

```shell
tree . -I __pycache__ -I tests
```

Agents generally are configured with a System prompt, an LLM, and tools to accomplish a specific job.
The trendwatch agent is configured to receive some of that information from environment variables, as follows:

- LLM_BASE_URL - the endpoint for making calls to the LLM.
- LLM_MODEL - the name of the model to target.
- MCP_URL - the URL for the MCP server whose tools the agent can call.

For example, configure the three environment variables as follows:

```shell
export LLM_BASE_URL="http://localhost:11434/v1"
export LLM_MODEL="qwen3:8b"
export MCP_URL="stdio:./mcp-servers/trends_server.py"
```

Above, we configure the agent to call `ollama`, to use the preconfigured `qwen` model, and to use the `trend_server` MCP server over the stdio transport (runs as a child process).

Try it out by running:

```shell
python3 agent/trendwatch.py "what discussions are trending today?"
```

The agent outputs some logging information such as:

- its configuration,
- the tools made visible to the model, and
- information for each "turn", including token consumption, tools called

Ultimately, the agent outputs the response to the user, in this case the list of trending conversations.

The agent should have returned with a tool request in the first turn.
The tool fetches and filter trending discussions pertaining to AI from HackerNews, then responds with the top 5 trending discussions.

## Summary

So far, we explored a local setup to run an agentic loop:  an agent has access to a local model and MCP servers and can answer questions.  As the loop runs, the LLM is consulted, consults specific tools and incorporates the responses to further reason about the user's query, and ultimately produces a response.

In the next sections, we explore the agentgateway project, and how it plays a crucial role as a proxy to both LLM and MCP traffic.