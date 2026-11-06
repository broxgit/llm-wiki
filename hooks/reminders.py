"""PreToolUse hook body for the llm-wiki plugin: hand the session the wiki reminders
that apply to the tool call it is about to make.

The session-start hook writes each session's reminders to <dir>/<session id>.tsv, one
per line: when, kind, pattern, rule, wiki. This reads the tool call on stdin and prints
a hook reply when a reminder matches. Each reminder is given once per session; the
session-start hook clears that record, so they come back after a compaction.

  before  the call is refused once, with the rule as the reason, so the agent reads
          the rule before acting. The same call made again goes through.
  on      the rule is added as context, and arrives with the call's result.

  bash    the pattern is text the command contains
  edit    the pattern is a file path, relative to the project folder
  tool    the pattern is a tool's name
In every pattern, * matches anything.

A hook must never break a session, so anything unexpected ends quietly with no reply.
"""

import json
import os
import re
import sys

EDIT_TOOLS = ("Edit", "Write", "NotebookEdit", "MultiEdit")
SAFE = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")


def glob(text, pattern):
    """Whether the whole text fits the pattern. Only * is special: [ and ? are
    themselves, since a shell command is full of them."""
    return re.fullmatch("(?s)" + ".*".join(re.escape(p) for p in pattern.split("*")), text) is not None


def matches(kind, pattern, tool, tool_input, cwd):
    if kind == "tool":
        return glob(tool, pattern)
    if kind == "bash":
        command = tool_input.get("command") if tool == "Bash" else None
        return isinstance(command, str) and glob(command, "*" + pattern + "*")
    if kind == "edit":
        if tool not in EDIT_TOOLS:
            return False
        path = tool_input.get("file_path") or tool_input.get("notebook_path")
        if not isinstance(path, str) or not path:
            return False
        root = cwd.rstrip("/") + "/" if cwd else ""
        if root and path.startswith(root):
            # Inside the project, only what is under it counts: against the whole
            # path, "payments/*" would match a folder of that name above the project.
            name = path[len(root):]
            return glob(name, pattern) or glob(name, "*/" + pattern)
        # Outside it, or with no project folder given, the pattern has to fit the path.
        return glob(path, pattern) or (not root and glob(path, "*/" + pattern))
    return False


def main():
    call = json.load(sys.stdin)
    session = call.get("session_id") or ""
    if not session or not set(session) <= SAFE:
        return
    base = os.path.join(sys.argv[1], session)
    try:
        rows = open(base + ".tsv", encoding="utf-8").read().splitlines()
    except OSError:
        return
    try:
        seen = set(open(base + ".seen", encoding="utf-8").read().split())
    except OSError:
        seen = set()
    tool = call.get("tool_name") or ""
    tool_input = call.get("tool_input") or {}
    cwd = call.get("cwd") or ""
    hits = []
    for number, row in enumerate(rows):
        parts = row.split("\t")
        if len(parts) != 5 or str(number) in seen:
            continue
        when, kind, pattern, rule, wiki = parts
        if matches(kind, pattern, tool, tool_input, cwd):
            hits.append((number, when, rule, wiki))
    if not hits:
        return
    with open(base + ".seen", "a", encoding="utf-8") as f:
        f.write("".join("%d\n" % number for number, _, _, _ in hits))
    rules = "\n".join("- %s (from the wiki %s, wiki/conventions.md)" % (rule, wiki) for _, _, rule, wiki in hits)
    if any(when == "before" for _, when, _, _ in hits):
        reply = {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": "Stopped once, so you read this before the call. It won't stop this call again.\n"
            + rules
            + "\nIf the call already follows this, make the same call again. If it doesn't, change it first.",
        }
    else:
        reply = {
            "hookEventName": "PreToolUse",
            "additionalContext": "A reminder from the user's wiki that applies to the call you just made:\n" + rules,
        }
    print(json.dumps({"hookSpecificOutput": reply}))


try:
    main()
except Exception:
    pass
