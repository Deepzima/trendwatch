"""Publish MCP server. Irreversible, public, and completely mocked.

Nothing here talks to a real platform, and no platform is named: channels are
"public", "team" and "all". Sixty workshop attendees should not be posting to
real accounts, and you should not need an API key to demonstrate an
authorization model.

It keeps a public log and prints loudly, so when the agent is tricked into
posting, the whole room sees exactly what went out.
"""

import json
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Literal

from mcp.server import MCPServer

mcp = MCPServer("publish")


def _log(step: str) -> None:
    # stderr only: stdout is the MCP JSON-RPC channel.
    print(f"mcp/{mcp.name}/{step}", file=sys.stderr, flush=True)

# The gateway may spawn a new stdio process per MCP call, so the feed lives on
# disk rather than in this process. Same ./out directory as workspace digests.
# Drop a stale file so a later lab does not inherit posts from an earlier one;
# two minutes is longer than one agent run and shorter than typical lab pacing.
OUT = Path("./out")
FEED_PATH = OUT / "public-feed.json"
FEED_TTL_SECONDS = 120
CHANNELS = ["public", "team", "all"]


def _load_feed() -> list[dict]:
    if not FEED_PATH.exists():
        return []
    try:
        if time.time() - FEED_PATH.stat().st_mtime > FEED_TTL_SECONDS:
            FEED_PATH.unlink(missing_ok=True)
            return []
        data = json.loads(FEED_PATH.read_text())
    except (OSError, json.JSONDecodeError):
        return []
    return data if isinstance(data, list) else []


def _save_feed(feed: list[dict]) -> None:
    OUT.mkdir(exist_ok=True)
    FEED_PATH.write_text(json.dumps(feed, indent=2) + "\n")

# Typing the channel as a Literal advertises the allowed values as an enum in the
# tool's JSON schema, so the model picks one of these instead of inventing a
# channel name from context (e.g. guessing "hackernews" in live mode).
Channel = Literal["public", "team", "all"]


@mcp.tool()
def post_to_social(message: str, channel: Channel = "all") -> dict:
    """Publish a message publicly. Immediate and irreversible.

    channel must be one of: "public", "team", "all" (default "all")."""
    _log("post_to_social")
    if channel not in CHANNELS:
        return {"error": f"unknown channel {channel}", "channels": CHANNELS}
    entry = {
        "posted_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "channel": channel,
        "message": message,
    }
    feed = _load_feed()
    feed.append(entry)
    _save_feed(feed)
    print(f"\n  *** PUBLISHED to {channel}: {message}\n", file=sys.stderr, flush=True)
    return {"published": True, **entry}


@mcp.tool()
def schedule_post(message: str, when: str, channel: Channel = "all") -> dict:
    """Schedule a message for public publication at a future time.

    channel must be one of: "public", "team", "all" (default "all")."""
    _log("schedule_post")
    if channel not in CHANNELS:
        return {"error": f"unknown channel {channel}", "channels": CHANNELS}
    entry = {"scheduled_for": when, "channel": channel, "message": message}
    feed = _load_feed()
    feed.append({"posted_at": f"scheduled:{when}", **entry})
    _save_feed(feed)
    print(f"\n  *** SCHEDULED for {when} on {channel}: {message}\n", file=sys.stderr, flush=True)
    return {"scheduled": True, **entry}


@mcp.tool()
def get_public_feed() -> list[dict]:
    """Show everything published or scheduled so far."""
    # An empty list reads to a small model as "the tool has nothing to offer";
    # say plainly that the feed is empty so it reports that, not a capability gap.
    _log("get_public_feed")
    feed = _load_feed()
    if not feed:
        return [{"note": "The public feed is empty -- nothing has been published yet."}]
    return feed


if __name__ == "__main__":
    # The gateway launches this over stdio; Ctrl-C on the gateway sends SIGINT to
    # the whole process group. Exit quietly instead of dumping a traceback.
    try:
        mcp.run()
    except KeyboardInterrupt:
        pass
