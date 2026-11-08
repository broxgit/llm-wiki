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

With --antigravity <tool|invoke> it is the adapter for Google's Antigravity, which has
no context reply on a tool call. The conversation's rows are in agy-<conversation id>.tsv,
written by wiki.sh's __agy-start. Gemini's tool names are read as Claude's, the shape of
the reply is Antigravity's, and every path ends with a reply, since a hook's exit code
is not documented:

  tool    PreToolUse: before is {"decision": "deny", "reason": ...}, once. An on reminder
          is queued in agy-<id>.pending and the call is allowed.
  invoke  PreInvocation: hands over what is queued, once, as a system message, just
          before the model's next step.

Each run adds a line to agy-hooks.log beside the reminders folder.
"""

import json
import os
import re
import sys
import tempfile
import time
from urllib.parse import unquote

EDIT_TOOLS = ("Edit", "Write", "NotebookEdit", "MultiEdit")
AGY_TOOLS = {"run_command": "Bash", "write_to_file": "Edit", "replace_file_content": "Edit",
             "multi_replace_file_content": "Edit", "invoke_subagent": "Agent"}
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


def hits_for(call, base):
    """The unseen reminders that apply to the call, marked seen. [] when there are none."""
    try:
        rows = open(base + ".tsv", encoding="utf-8").read().splitlines()
    except OSError:
        return None
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
    if hits:
        with open(base + ".seen", "a", encoding="utf-8") as f:
            f.write("".join("%d\n" % number for number, _, _, _ in hits))
    return hits


def rules_of(hits):
    return "\n".join("- %s (from the wiki %s, wiki/conventions.md)" % (rule, wiki) for _, _, rule, wiki in hits)


HEADING = "A reminder from the user's wiki that applies to the call you just made:\n"


def deny_reason(hits):
    return ("Stopped once, so you read this before the call. It won't stop this call again.\n"
            + rules_of(hits)
            + "\nIf the call already follows this, make the same call again. If it doesn't, change it first.")


def main():
    call = json.load(sys.stdin)
    session = call.get("session_id") or ""
    if not session or not set(session) <= SAFE:
        return
    hits = hits_for(call, os.path.join(sys.argv[1], session))
    if not hits:
        return
    if any(when == "before" for _, when, _, _ in hits):
        reply = {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": deny_reason(hits)}
    else:
        reply = {"hookEventName": "PreToolUse", "additionalContext": HEADING + rules_of(hits)}
    print(json.dumps({"hookSpecificOutput": reply}))


def workspace_of(call, path):
    """The workspace folder the file is in, else the first. Antigravity may give file:// URLs."""
    folders = []
    for w in call.get("workspacePaths") or []:
        if isinstance(w, str) and w:
            folders.append(unquote(w[7:]) if w.startswith("file://") else w)
    for w in folders:
        if path and path.startswith(w.rstrip("/") + "/"):
            return w
    return folders[0] if folders else ""


def log(state, *fields):
    """One line per run. Best effort: the sandbox may refuse the state folder, so the
    temp folder is the second place."""
    line = "\t".join([time.strftime("%Y-%m-%dT%H:%M:%S")] + [str(f).replace("\t", " ").replace("\n", " ") for f in fields]) + "\n"
    for path in (os.path.join(state, "agy-hooks.log"), os.path.join(tempfile.gettempdir(), "llm-wiki-agy-hooks.log")):
        try:
            if os.path.exists(path) and os.path.getsize(path) > 100000:
                keep = open(path, encoding="utf-8").read().splitlines(True)[-200:]
                open(path, "w", encoding="utf-8").write("".join(keep))
            with open(path, "a", encoding="utf-8") as f:
                f.write(line)
            return
        except OSError:
            continue


def antigravity(event, rdir):
    """The reply for Antigravity, and what to log. Returns (reply, conversation, tool, outcome)."""
    allow = {"decision": "allow"} if event == "tool" else {}
    call = json.load(sys.stdin)
    conv = call.get("conversationId") or ""
    if not conv or not set(conv) <= SAFE:
        return allow, conv, "", "no-conversation"
    base = os.path.join(rdir, "agy-" + conv)
    if event == "invoke":
        pending = base + ".pending"
        try:
            age = time.time() - os.path.getmtime(pending)
            text = open(pending, encoding="utf-8").read()
        except OSError:
            return allow, conv, "", "nothing-queued" if os.path.isdir(rdir) else "no-state"
        os.remove(pending)
        if age > 86400 or not text.strip():
            return allow, conv, "", "dropped-stale"
        return {"injectSteps": [{"systemMessage": {"systemMessage": HEADING + text.rstrip("\n")}}]}, conv, "", "delivered"
    name = (call.get("toolCall") or {}).get("name") or ""
    args = (call.get("toolCall") or {}).get("args") or {}
    tool = AGY_TOOLS.get(name, name)
    path = args.get("TargetFile") or ""
    tool_input = {"command": args.get("CommandLine"), "file_path": path}
    translated = {"tool_name": tool, "tool_input": tool_input, "cwd": workspace_of(call, path)}
    hits = hits_for(translated, base)
    if hits is None:
        return allow, conv, name, "no-rows" if os.path.isdir(rdir) else "no-state"
    if not hits:
        return allow, conv, name, "no-match"
    if any(when == "before" for _, when, _, _ in hits):
        return {"decision": "deny", "reason": deny_reason(hits)}, conv, name, "deny"
    with open(base + ".pending", "a", encoding="utf-8") as f:
        f.write(rules_of(hits) + "\n")
    return allow, conv, name, "queued"


def run_antigravity(event):
    rdir = sys.argv[1]
    allow = {"decision": "allow"} if event == "tool" else {}
    try:
        reply, conv, tool, outcome = antigravity(event, rdir)
    except Exception as e:
        reply, conv, tool, outcome = allow, "", "", "error: %s" % type(e).__name__
    print(json.dumps(reply))
    log(os.path.dirname(rdir.rstrip("/")), event, conv, tool, outcome)


try:
    if len(sys.argv) > 3 and sys.argv[2] == "--antigravity":
        run_antigravity("invoke" if sys.argv[3] == "invoke" else "tool")
    else:
        main()
except Exception:
    pass
