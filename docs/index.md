# Introduction

This workshop helps you explore some of the agentic capabilities of [agentgateway](https://agentgateway.dev/).

The workshop is designed to be self-contained with a minimum of external dependencies.

## Prerequisites

To work through this workshop, please ensure that you have the following installed on your machine:

- python3 (version 3.11 or above)
- [jq](https://jqlang.org/)
- docker
- ollama (instructions for installation are below)

## Local model

This workshop assumes a local inference model using the [Ollama](https://ollama.com/) project.

If you don't already have Ollama running, on a mac you can install it with [homebrew](https://brew.sh/):

```shell
brew install ollama
```

For other platforms, consult the [Ollama docs](https://docs.ollama.com/linux) for the install instructions.

Pull the [qwen3](https://ollama.com/library/qwen3) model.

```shell
ollama pull qwen3:8b
```

Make sure that `qwen3:8b` is now showing in the local models list:

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

## The agentic scenario: TrendWatch

TrendWatch is an AI agent that tells you what is hot in agentic AI today.
It leverages a set of MCP servers to read trending discussions, build and save a digest on the topics you care about, and can "publish" these digests.

Clone the GitHub repository for the project:

```shell
git clone https://github.com/solo-io/trendwatch.git
```

Navigate into the directory:

```shell
cd trendwatch
```

The code consists of an agent named "TrendWatch", and a set of example MCP servers, written in python.

Inspect the contents of the `agent/` and `mcp-servers/` subdirectories, to take account of the main project files:

```shell
ls -lF agent/ mcp-servers/
```

### Setup

Create a python virtual environment for the project:

```shell
python3 -m venv .venv
```

Activate the environment:

```shell
source .venv/bin/activate
```

!!! note  "Activating the virtual environment for different shells"

    The python3 virtual environment provides different `activate` scripts for different types of shells.

    If you happen to be running the [fish shell](https://fishshell.com/), substitute the above command with this instead:

    ```shell
    source .venv/bin/activate.fish
    ```

Install the project's dependencies:

```shell
pip install -r requirements.txt
```

Run the distributed tracing project [Jaeger](https://www.jaegertracing.io/) in a docker container:

```shell
docker run -d --name jaeger \
  -p 16686:16686 -p 4317:4317 \
  jaegertracing/all-in-one:latest
```

You will use Jaeger to inspect distributed traces illustrating the call flows between the agent, the LLM, and MCP servers.

### Configure and run the agent

Agents generally are configured with a System prompt, an LLM, and tools to accomplish a specific job.
The TrendWatch agent is configured to receive some of that information from environment variables, as follows:

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

- Its configuration.
- The tools made visible to the model.
- Information for each "turn", including token consumption, tools called.

Ultimately, the agent outputs the response to the user, in this case the list of trending conversations.

In the first turn, the agent should respond with a tool request for `trending_discussions`.
The tool fetches and filters trending discussions pertaining to AI from HackerNews, then responds with the top 5 trending discussions.
In the second turn, the agent takes that information and presents it to the user.

## Summary

So far, we explored a local setup to run an agentic loop:  an agent has access to a local model and MCP servers, and can answer questions.  As the loop runs, the LLM is consulted, requests for specific tools to be called, and incorporates the responses to further reason about the user's query, and ultimately produces a response.

In the next sections, we explore the agentgateway project, and how it plays a crucial role as a proxy to both LLM and MCP traffic.