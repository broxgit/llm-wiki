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
written by wiki.sh's __agy-start. Gemini's tool names are read as Claude's (the docs name
write_to_file, replace_file_content and multi_replace_file_content, with the path in
TargetFile; the app itself was seen to call write_file, with the path in Path), the shape of
the reply is Antigravity's, and every path ends with a reply, since a hook's exit code
is not documented:

  tool    PreToolUse: before is {"decision": "deny", "reason": ...}, once. An on reminder
          is queued in agy-<id>.pending and the call is allowed.
  invoke  PreInvocation: hands over what is queued, once, as a system message, just
          before the model's next step.

Each run adds a line to agy-hooks.log beside the reminders folder.

Two things are logged here too, because they are events the hook sees and an agent
doing them from memory mostly doesn't:

  a read of a wiki page    one line, date,wiki,hit, in the collection's stats.csv, as
                           the MCP server's wiki_read writes it. Once per wiki per
                           session, kept in <session id>.reads beside the reminders.
                           Only a .md file under <collection>/<wiki>/wiki/ counts.
  a handoff (Claude Code)  the Agent or Task tool, or a start_session tool: one row in
                           delegation-log.csv with the result "started". The outcome is
                           added by hand, once the work is checked.
Neither can break the session: every failure is ignored.
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
             "multi_replace_file_content": "Edit", "invoke_subagent": "Agent",
             "write_file": "Edit"}  # the docs' names, plus the app's own
READ_TOOLS = ("read_file", "view_file")  # Gemini's, in Antigravity
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


def collections():
    """The folders holding wikis, as wiki.sh lists them: WIKIS_DIR when set, the default
    collection, then those in the collections file (name, folder, rules per line)."""
    home = os.path.expanduser("~")
    folders = []
    if os.environ.get("WIKIS_DIR"):
        folders.append(os.environ["WIKIS_DIR"])
    folders.append(os.environ.get("LLM_WIKI_DEFAULT_DIR") or os.path.join(home, "wikis"))
    cfg = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.join(home, ".config"), "llm-wiki", "collections")
    try:
        for line in open(cfg, encoding="utf-8").read().splitlines():
            fields = line.split()
            if len(fields) >= 2 and not fields[0].startswith("#"):
                f = fields[1]
                folders.append(os.path.join(home, f[2:]) if f.startswith("~/") else f)
    except OSError:
        pass
    out = []
    for f in folders:
        f = os.path.normpath(f)
        if f not in out:
            out.append(f)
    return out


def wiki_of_page(path):
    """(collection folder, wiki name) when the path is a .md file under
    <collection>/<wiki>/wiki/ of a wiki (a folder with AGENTS.md and index.md), else None.
    A page that isn't there, such as one the agent guessed at, isn't a lookup."""
    if not isinstance(path, str) or not path.endswith(".md") or not os.path.isfile(path):
        return None
    for candidate in dict.fromkeys((os.path.normpath(path), os.path.realpath(path))):
        for folder in collections():
            for root in dict.fromkeys((folder, os.path.realpath(folder))):
                prefix = root.rstrip("/") + "/"
                if not candidate.startswith(prefix):
                    continue
                parts = candidate[len(prefix):].split("/")
                if len(parts) >= 3 and parts[1] == "wiki":
                    wiki = os.path.join(root, parts[0])
                    if os.path.isfile(os.path.join(wiki, "AGENTS.md")) and os.path.isfile(os.path.join(wiki, "index.md")):
                        return root, parts[0]
    return None


def log_lookup(path, record):
    """A read of a wiki page is a lookup: one hit line in the collection's stats.csv,
    once per wiki per session. record is the file that remembers which were logged.
    Without a record we couldn't tell, so nothing is logged rather than a line a read."""
    found = wiki_of_page(path)
    if not found:
        return
    folder, wiki = found
    key = "%s\t%s\n" % (folder, wiki)
    try:
        done = set(open(record, encoding="utf-8").read().splitlines(True))
    except OSError:
        done = set()
    if key in done:
        return
    try:
        os.makedirs(os.path.dirname(record), exist_ok=True)
        with open(record, "a", encoding="utf-8") as f:
            f.write(key)
    except OSError:
        return
    csv = os.path.join(folder, "stats.csv")
    try:
        new = not os.path.exists(csv)
        with open(csv, "a", encoding="utf-8") as f:
            if new:
                f.write("date,wiki,result\n")
            f.write("%s,%s,hit\n" % (time.strftime("%Y-%m-%d", time.gmtime()), wiki))
    except OSError:
        pass


def clean(text, limit=0):
    """A field of the delegation log: no commas or line breaks, cut at limit characters."""
    text = " ".join(str(text or "").replace(",", " ").split())
    return text[:limit].rstrip() if limit else text


def project_of(cwd):
    """The repository's name as the session-start hook finds it: the last part of its
    remote URL, else its folder's name. Outside a repository, the working folder's."""
    import subprocess

    def git(*args):
        try:
            r = subprocess.run(("git", "-C", cwd) + args, capture_output=True, text=True, timeout=2)
            return r.stdout.strip() if r.returncode == 0 else ""
        except Exception:
            return ""

    top = git("rev-parse", "--show-toplevel") if cwd else ""
    if top:
        url = git("config", "--get", "remote.origin.url").rstrip("/")
        if url:
            url = url.rsplit("/", 1)[-1].rsplit(":", 1)[-1]
            return url[:-4] if url.endswith(".git") else url
        return os.path.basename(top)
    return os.path.basename(cwd.rstrip("/")) if cwd else ""


def log_handoff(call):
    """A handoff starts: one row in the default collection's delegation-log.csv, with
    the result "started". Whether the work was any good is judged later, by hand."""
    tool_input = call.get("tool_input") or {}
    kind = clean(tool_input.get("description") or tool_input.get("title"), 60) or "handoff"
    cwd = call.get("cwd") or os.environ.get("CLAUDE_PROJECT_DIR") or ""
    project = clean(project_of(cwd)) or "-"
    path = os.path.join(collections()[0], "delegation-log.csv")
    new = not os.path.exists(path) or os.path.getsize(path) == 0
    with open(path, "a", encoding="utf-8") as f:
        if new:
            f.write("date,project,kind,model,effort,result\n")
        f.write("%s,%s,%s,%s,%s,started\n" % (time.strftime("%Y-%m-%d", time.gmtime()), project, kind,
                                              clean(tool_input.get("model")), clean(tool_input.get("effort"))))


def is_handoff(tool):
    return tool in ("Agent", "Task") or tool.endswith("start_session")


def main():
    call = json.load(sys.stdin)
    session = call.get("session_id") or ""
    if not session or not set(session) <= SAFE:
        return
    tool = call.get("tool_name") or ""
    if tool == "Read":
        # Not a tool the reminders cover; a read of a wiki page is a lookup.
        log_lookup(((call.get("tool_input") or {}).get("file_path")), os.path.join(sys.argv[1], session + ".reads"))
        return
    if is_handoff(tool):
        try:
            log_handoff(call)
        except Exception:
            pass
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
    path = args.get("TargetFile") or args.get("Path") or ""
    if name in READ_TOOLS:
        try:
            log_lookup(args.get("AbsolutePath") or path, base + ".reads")
        except Exception:
            pass
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
