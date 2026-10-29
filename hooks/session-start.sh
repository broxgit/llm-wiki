#!/usr/bin/env bash
# SessionStart hook for the llm-wiki Claude Code plugin. Finds the wiki that covers the
# repository this session works in, and tells the session to read its handbook. It does
# the job of the ~/.claude/CLAUDE.md line from `wiki.sh claude`, and runs on startup,
# resume, /clear and after compaction, so the instruction is always fresh.
# A hook must never block a session: every path exits 0.
set -u

ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
WIKI_SH="$ROOT/wiki.sh"
WIKIS_DIR="${WIKIS_DIR:-$HOME/wikis}"
export WIKIS_DIR
DIR="${CLAUDE_PROJECT_DIR:-$PWD}"

# Claude Code sends JSON on stdin. Its "source" says why the session started:
# startup, resume, clear, compact or fork. Read with a timeout, so a run by hand
# with nothing piped in can't hang.
input=""
line=""
while IFS= read -r -t 1 line; do input="$input$line"; done
input="$input$line"
case "$input" in *'"source":"compact"'* | *'"source": "compact"'*) compacted=1 ;; *) compacted=0 ;; esac

# emit <text>: hand text to Claude Code as additional context, JSON-escaped without jq.
emit() {
  printf '%s' "$1" | awk '
    BEGIN { printf "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"" }
    {
      gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\t/, "\\t"); gsub(/\r/, "")
      gsub(/[\001-\010\013\014\016-\037]/, "")
      printf "%s%s", (NR > 1 ? "\\n" : ""), $0
    }
    END { printf "\"}}\n" }'
  exit 0
}

[ -x "$WIKI_SH" ] || exit 0

# t <path>: the path with ~ for the home folder. Shorter, and a shell expands it in a
# command as long as it isn't quoted.
# shellcheck disable=SC2088
t() { case "$1" in "$HOME"/*) printf '~/%s' "${1#"$HOME"/}" ;; *) printf '%s' "$1" ;; esac; }

# A stable terminal command. The plugin's folder changes with every update, and old
# folders are deleted, so people can't type that path. The data folder survives
# updates, so the command lives there.
#
# `claude plugin update` installs a new version without a session starting, so the
# command can't rely on this hook to repoint it. It asks Claude Code's own record,
# installed_plugins.json, for the current install folder every time it runs, and
# falls back to this version. A plugin run from a clone (a local marketplace) has
# no versioned folder, so it isn't looked up.
CMD=""
KEY=""
case "$ROOT" in
  "$HOME"/.claude/plugins/cache/*/*/*)
    plugin_dir="${ROOT%/*}"
    KEY="${plugin_dir##*/}@$(basename "${plugin_dir%/*}")"
    ;;
esac
if [ -n "${CLAUDE_PLUGIN_DATA:-}" ]; then
  CMD="$CLAUDE_PLUGIN_DATA/bin/wiki"
  shim="$(cat <<EOF
#!/bin/sh
# The llm-wiki plugin's terminal command, written by the plugin's session hook.
# It runs the version Claude Code says is installed, so an update counts at once.
target="$WIKI_SH"
key="$KEY"
installed="\$HOME/.claude/plugins/installed_plugins.json"
if [ -n "\$key" ] && [ -f "\$installed" ] && command -v python3 >/dev/null 2>&1; then
  path="\$(python3 - "\$installed" "\$key" 2>/dev/null <<'PY'
import json, sys
entries = json.load(open(sys.argv[1])).get("plugins", {}).get(sys.argv[2], [])
entries = sorted(entries, key=lambda e: e.get("scope") != "user")
print(entries[0].get("installPath", "") if entries else "")
PY
)"
  [ -n "\$path" ] && [ -x "\$path/wiki.sh" ] && target="\$path/wiki.sh"
fi
[ -x "\$target" ] || { echo "wiki: can't find the llm-wiki plugin. Check it with: claude plugin list" >&2; exit 1; }
LLM_WIKI_CMD=wiki LLM_WIKI_SHIM="$CMD" exec "\$target" "\$@"
EOF
)"
  if [ "$(cat "$CMD" 2>/dev/null)" != "$shim" ]; then
    mkdir -p "${CMD%/*}" && printf '%s\n' "$shim" > "$CMD" && chmod +x "$CMD" || CMD=""
  fi
fi
# How the user runs it in a terminal: `wiki` once it's on their PATH, the full path until then.
# Sessions get the same stable command for wiki.sh: the plugin's own folder changes
# with every update, and a session that saved that path would break.
TYPE="${CMD:-$WIKI_SH}"
[ -n "$CMD" ] && [ "$(command -v wiki 2>/dev/null)" -ef "$CMD" ] && TYPE="wiki"
LINK=""
if [ -n "$CMD" ] && [ "$TYPE" != wiki ]; then
  LINK="\`wiki\` isn't a command in their terminal yet. When they ask, or the first time you give them a command to run, offer once to run \`$(t "$CMD") link\`, which links it onto their PATH. If it reports that ~/.local/bin isn't on their PATH, ask before running \`$(t "$CMD") link --yes\`, which edits their shell profile."
fi

if [ ! -d "$WIKIS_DIR" ]; then
  emit "llm-wiki plugin: there is no wiki collection at $WIKIS_DIR yet, so this session has no wiki. If the user asks about wikis, tell them to run this in a terminal: $TYPE setup${LINK:+
$LINK}"
fi

# The repository's name: the last part of its remote URL, or its folder name.
repo=""
if top="$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null)"; then
  url="$(git -C "$DIR" config --get remote.origin.url 2>/dev/null || true)"
  if [ -n "$url" ]; then
    url="${url%/}"; url="${url##*/}"; url="${url##*:}"; repo="${url%.git}"
  else
    repo="${top##*/}"
  fi
fi

wiki=""
note=""
if [ -n "$repo" ]; then
  w="$("$WIKI_SH" which "$repo" 2>/dev/null || true)"
  # wiki.sh prints ~ for the home folder. The tilde is meant literally.
  # shellcheck disable=SC2088
  case "$w" in "~/"*) w="$HOME/${w:2}" ;; esac
  [ -n "$w" ] && wiki="$w"
fi
if [ -z "$wiki" ]; then
  [ -f "$WIKIS_DIR/global/AGENTS.md" ] || exit 0
  wiki="$WIKIS_DIR/global"
  if [ -n "$repo" ]; then
    note="No wiki covers $repo yet, so the shared wiki is this session's. Create $repo's wiki with \`wiki.sh new $repo\` when there's something to file. Before that, offer once to start it from the repository's own docs with \`wiki.sh seed\`, run in the repository."
  else
    note="This session isn't in a repository, so the shared wiki is its wiki."
  fi
fi
[ -f "$wiki/AGENTS.md" ] || exit 0

# What needs doing at session start, so the agent doesn't have to look.
# wiki.sh decides what counts as compiled, so the two never disagree.
waiting="$("$WIKI_SH" pending "$wiki" 2>/dev/null | grep -c '^raw/' || true)"
version_of() { sed -n 's/^Handbook version \([0-9][0-9]*\).*/\1/p' "$1" 2>/dev/null | head -n 1; }
wv="$(version_of "$wiki/AGENTS.md")"
tv="$(version_of "$ROOT/template/AGENTS.md")"

# Keep this short. Claude Code shows the model only a short preview of a long hook
# output and saves the rest to a file, so the handbook itself can't ride along here.
# The first lines must carry the instruction to read it.
# A plugin update brings a newer handbook, and the wikis should follow without anyone
# running upgrade by hand. The session does it, after pulling: upgrading first would
# leave local changes that make the pull fail if a teammate already pushed the same
# upgrade. upgrade never moves a wiki backwards.
read_first="Before anything else, read $(t "$wiki")/AGENTS.md"
upgrading=""
if [ -n "$wv" ] && [ -n "$tv" ] && [ "$wv" -lt "$tv" ]; then
  upgrading=1
  read_first="Its handbook is v$wv, older than the plugin's v$tv. First pull the collection if it has a remote, then run \`wiki.sh upgrade --all\`. It commits the upgrade itself. Push it, and tell the user briefly what changed. Then read the new $(t "$wiki")/AGENTS.md"
fi
ctx="# llm-wiki

\`wiki.sh\` here means $(t "${CMD:-$WIKI_SH}"), the script the handbook refers to. In a terminal the user runs it as: $(t "$TYPE")

This session's knowledge wiki is $(t "$wiki")${repo:+, for the repository $repo}. $read_first, its handbook, and follow it for the rest of the session. Its session-start steps say what to read next, including the shared wiki.
Save knowledge in the wiki, not in your own memory: memory stays in this folder, and the wiki reaches every repository and teammate.
${note:+

$note}"
if [ -n "$LINK" ]; then
  ctx="$ctx
$LINK"
fi
# Team skills added to the wikis since last time, linked so Claude Code finds them.
if [ -d "$HOME/.claude" ]; then
  linked="$("$WIKI_SH" skills link 2>/dev/null | sed -n 's/^linked:  \([^ ]*\).*/\1/p' | tr '\n' ' ' | sed 's/ $//')"
  if [ -n "$linked" ]; then
    ctx="$ctx

New team skills from the wikis are linked and available: $linked"
  fi
fi
# One tip a session about a feature this person's own wikis suggest they'd use. Not
# right after compaction, which usually means mid-task, nor when the session starts
# with an upgrade. wiki.sh keeps the cooldown and mutes.
# Once a week, the report: tokens, what the wikis gained, and what waits on a person.
# A week with a report offer gets no tip, so there's only ever one nudge.
report_due=""
if [ "$compacted" = 0 ] && [ -z "$upgrading" ]; then
  report_due="$("$WIKI_SH" report --due 2>/dev/null)"
  if [ -n "$report_due" ]; then
    ctx="$ctx

The weekly wiki report is due. At a stopping point, offer it once, in a line. If the user wants it, run \`wiki.sh report\` and write it up as its first lines say."
  fi
fi
if [ "$compacted" = 0 ] && [ -z "$upgrading" ] && [ -z "$report_due" ]; then
  tab="$(printf '\t')"
  tip="$("$WIKI_SH" tips --next --repo "$DIR" 2>/dev/null | head -n 1)"
  if [ -n "$tip" ]; then
    ctx="$ctx

One tip for the user, from their own wikis. Mention it once, in a line or two, at a stopping point, never mid-task: ${tip#*"$tab"} If they don't want it suggested again, run \`wiki.sh tips --mute ${tip%%"$tab"*}\`."
  fi
fi
if [ "$compacted" = 1 ]; then
  ctx="$ctx

This session was just compacted. Before you answer anything, even the user's message, capture whatever in the summary the wiki doesn't hold yet, as the handbook's Capture section says. It can't wait for a stopping point: the summary is all that's left."
fi
if [ "$waiting" -gt 0 ]; then
  ctx="$ctx

$waiting note(s) in raw/ are waiting to be compiled$([ "$waiting" -gt 10 ] && echo ". That's more than ten, so do the user's request first and compile at the next pause" || echo ", before the user's request"), as one batch if there are five or more: see the handbook's session start and rules/compile.md."
fi
emit "$ctx"
