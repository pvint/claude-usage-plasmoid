#!/usr/bin/env python3
"""Fetch Claude usage via the OAuth usage endpoint and print compact JSON for the widget."""
import json
import os
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime

CREDS = os.path.expanduser("~/.claude/.credentials.json")
URL = "https://api.anthropic.com/api/oauth/usage"
LOG = os.path.expanduser("~/.cache/claude-usage-plasmoid.log")
LOG_MAX = 100_000
CACHE = os.path.expanduser("~/.cache/claude-usage-plasmoid.json")
MAX_STALE = 3600  # show an error once cached data is older than this


def log(msg):
    try:
        os.makedirs(os.path.dirname(LOG), exist_ok=True)
        if os.path.exists(LOG) and os.path.getsize(LOG) > LOG_MAX:
            os.replace(LOG, LOG + ".1")
        with open(LOG, "a") as f:
            f.write("%s %s\n" % (datetime.now().isoformat(timespec="seconds"), msg))
    except OSError:
        pass


def out(obj):
    print(json.dumps(obj))
    sys.exit(0)


def load_cache():
    try:
        with open(CACHE) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def save_cache(cache):
    try:
        os.makedirs(os.path.dirname(CACHE), exist_ok=True)
        tmp = CACHE + ".tmp"
        with open(tmp, "w") as f:
            json.dump(cache, f)
        os.replace(tmp, CACHE)
    except OSError:
        pass


def fail(msg):
    """Log the error and fall back to cached data, only surfacing it once the data is old."""
    log(msg)
    cache = load_cache()
    data = cache.get("data")
    if data and time.time() - cache.get("fetched", 0) < MAX_STALE:
        out(data)
    out(dict(data or {}, error=msg))


def window(w):
    if not w:
        return None
    resets = None
    if w.get("resets_at"):
        resets = datetime.fromisoformat(w["resets_at"]).timestamp()
    return {"pct": w.get("utilization") or 0, "resets": resets}


try:
    with open(CREDS) as f:
        token = json.load(f)["claudeAiOauth"]["accessToken"]
except (OSError, KeyError, ValueError):
    fail("No Claude Code credentials found")

req = urllib.request.Request(URL, headers={
    "Authorization": "Bearer " + token,
    "anthropic-beta": "oauth-2025-04-20",
    "Content-Type": "application/json",
})
try:
    with urllib.request.urlopen(req, timeout=15) as f:
        data = json.load(f)
except urllib.error.HTTPError as e:
    if e.code == 401:
        fail("Token expired - run Claude Code to refresh it")
    fail("HTTP %d" % e.code)
except (urllib.error.URLError, OSError, ValueError) as e:
    fail("Network error: %s" % e)

result = {"five": window(data.get("five_hour")), "week": window(data.get("seven_day"))}
log("ok")
save_cache({"fetched": time.time(), "data": result})
out(result)
