# Proxy LLM traffic

Building on the agent example from the previous section, we wish to put a proxy between the agent and the LLM.
Doing so has a number of benefits, including:

- It allows us to observe requests made to the LLM.
- The proxy can act as a control point to authorize certain requests but not others.
- The proxy can be made to limit or cap usage to a certain number of tokens.

## Install agentgateway

Install the agentgateway binary, version 1.5.0:

```shell
curl -sL https://agentgateway.dev/install | bash -s -- --version 1.5.0
```

Verify that the `agentgateway` binary is in the PATH:

```shell
agentgateway --version
```

## Configure the proxy

Agentgateway can be configured to call a variety of models and providers.

By default agentgateway listens for LLM requests on port 4000.

Run the command below and review the configuration for agentgateway:

```shell
cat configs/llm-basic.yaml
```

The configuration cites a single model, named "trend-pro", hiding the fact that "trend-pro" is backed by the qwen3 model.  Since this model runs locally with ollama, it does not require an apiKey.  In general, configuring the apiKey at the proxy has an advantage: the key is never exposed to end users, it is maintained by the platform team.

Configure a two-panel layout so that you have two terminals running.

Select the top panel, and start the proxy:

```shell
agentgateway -f configs/llm-basic.yaml
```

Switch to the bottom panel (second terminal).

Configure the `trendwatch` agent to point at the proxy when calling the LLM:

```shell
export LLM_BASE_URL=http://localhost:4000/v1
export LLM_MODEL=trend-pro
export MCP_URL=stdio:./mcp-servers/trends_server.py
```

Finally, try running the agent once more:

```shell
python3 agent/trendwatch.py "what discussions are trending today?"
```

In agentgateway's logs, you can see that it captures the requests to the LLM along with metadata such as the model that was called, token consumption, and more.  What agentgateway captures is configurable, and can even include the user prompt and the response.

## Configure token budgets

In the top panel, press `Ctrl+C` to terminate agentgateway.

Review the following proxy configuration:

```shell
cat configs/token-budget.yaml
```

The above configuration adds a policy to rate-limit requests.
The rate limiting is specified in terms of number of tokens used, tokens being the native "metric" of utilization for LLMs.

`maxTokens` is set artificially low at 5000 tokens over a 5-minute (300 second) interval, to make it easy to test:

Restart agentgateway with the updated configuration file:

```shell
agentgateway -f configs/token-budget.yaml
```

Select the bottom panel, and try to run the agent a few times to trigger the rate limit:

```shell
for i in {1..3}; do
  python3 agent/trendwatch.py "what discussions are trending today?"
done
```

The first session should succeed, but as the token utilization exceeds the limit, we start receiving HTTP 429 (Rate Limited) responses.
The agentgateway logs also shows entries with `http.status=429`, indicating that the request was rate-limited.

Agentgateway has many more features and capabilities pertaining to management of utilization, and cost control.

With agentgateway we can:

- Monitor and control usage in terms of money rather than tokens, by configuring a cost catalog for a variety of models.
- Attribute utilization by team and user, giving some teams higher budgets than others.
- Configure budgets per team and user, and in monetary terms instead of tokens.

## Summary

In this exercise, you have placed agentgateway in between the agent and the LLM, obtained visibility over calls to LLMs, and configured token budgets.

In the next section, we build on this foundation and demonstrate the value of also placing agentgateway in front of the MCP tool servers.