# MCP Authentication

In this lab we explore how to configure MCP authentication and authorization in agentgateway, decoupling that concern from the business logic in the backend MCP server.

You will explore exposing a different set of tools to the user based on whether they're authenticated, and if authenticated, based on their role, obtained from the user's JWT token.

For this lab, instead of configuring a full-fledge identity provider such as KeyCloak for the authentication, we provide pre-minted JWT tokens in the form of environment variables READER_JWT and PUBLISHER_JWT.
A simple stub server that serves the JWKS keyset is already running in the background.

## A proxy configured with MCP Authentication & Authorization

Configure a two-panel layout for the terminal:

```shell
zellij --layout ~/two-pane-layout.kdl
```

Review the following agentgateway configuration:

```shell
bat 09-mcp-identity.yaml
```

The configuration has both authentication and authorization sections.
The authentication mode is set to `optional`.
Whether a user is authenticated has a bearing on the interpretation of the authorization rules, some of which reference claims in the user's JWT token.
When the user is unauthenticated, those rules return "false" and certain tools are not available.

From the top panel, launch agentgateway:

```shell
agentgateway -f 09-mcp-identity.yaml
```

## Scenario 1: Unauthenticated user

In the bottom panel, start the agent with a request that demands access to certain tools that are not available to unauthenticated users:

```shell
python3 agent/trendwatch.py \
  "Build today's digest from the trending discussions, then call workspace_save_digest to write it to disk. Do not finish until you have saved it, and report the file path the tool returns."
```

The trending discussions will be obtained, but the agent will not be able to go any further:  it cannot call "save_digest".

## Scenario 2: User with read-only access

The MCP_TOKEN environment variable is used as the identity of the user making the request:

```shell
export MCP_TOKEN=$READER_JWT
```

Now we have a user that has access to more tools, the workspace tools are accessible, and so the agent should be able to fulfill the request:

```shell
python3 agent/trendwatch.py \
  "Build today's digest from the trending discussions, then call workspace_save_digest to write it to disk. Do not finish until you have saved it, and report the file path the tool returns."
```

However, if we ask the agent to "post the digest" which is a "publish" type of action:

```shell
python3 agent/trendwatch.py "post that digest to social"
```

The agent is unable to fulfill that request.

## Scenario 3: User with read-write access

Finally, set the identity of the caller to someone with "publisher" role or capability:

```shell
export MCP_TOKEN=$PUBLISHER_JWT
```

Now the agent will have access to all the tools, and should be able to perform a publish:

```shell
python3 agent/trendwatch.py \
  "Build today's digest from the trending discussions, get the single top trending AI related item from the trending discussions, then publish it by calling publish_post_to_social. Report only the exact JSON the tool returns, then call publish_get_public_feed and show me the feed to confirm the post landed."
```

## Summary

In this lab, authentication and authorization for a backend MCP server was configured at the proxy.
The benefit of employing a proxy is the ability to decouple the implementation of cross-cutting concerns such as security from the logic of the backend workload, be it an MCP server or some other type of backend.
No changes to the backend service were required to implement the security layer.