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
TYPE="${CMD:-$WIKI_SH}"
[ -n "$CMD" ] && [ "$(command -v wiki 2>/dev/null)" -ef "$CMD" ] && TYPE="wiki"
LINK=""
if [ -n "$CMD" ] && [ "$TYPE" != wiki ]; then
  LINK="\`wiki\` isn't a command in the user's terminal yet. If they ask to set up the wiki command, or the first time you give them a wiki.sh command to run, offer to run \`\"$CMD\" link\`. It links it into a folder on their PATH. If it says ~/.local/bin isn't on their PATH, ask before running \`\"$CMD\" link --yes\`, which adds it to their shell profile. Offer this once, not every reply."
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
    note="No wiki covers the repository $repo yet, so the shared wiki is this session's wiki. The first time there is something to file about $repo, create its wiki: $WIKI_SH new $repo
Before that, mention once that $repo's own README and docs can start its wiki, and run this if the user agrees: $WIKI_SH seed \"$top\""
  else
    note="This session isn't in a repository, so the shared wiki is its wiki."
  fi
fi
[ -f "$wiki/AGENTS.md" ] || exit 0

# What needs doing at session start, so the agent doesn't have to look.
waiting=0
for f in "$wiki"/raw/*; do
  [ -f "$f" ] || continue
  b="${f##*/}"
  [ -e "$wiki/wiki/sources/${b%.*}.md" ] || waiting=$((waiting + 1))
done
version_of() { sed -n 's/^Handbook version \([0-9][0-9]*\).*/\1/p' "$1" 2>/dev/null | head -n 1; }
wv="$(version_of "$wiki/AGENTS.md")"
tv="$(version_of "$ROOT/template/AGENTS.md")"

# Keep this short. Claude Code shows the model only a short preview of a long hook
# output and saves the rest to a file, so the handbook itself can't ride along here.
# The first lines must carry the instruction to read it.
ctx="# llm-wiki

This session's knowledge wiki is $wiki${repo:+, for the repository $repo}. Before anything else, read $wiki/AGENTS.md, its handbook, and follow it for the rest of the session. Its session-start steps say to read index.md next.
${note:+
$note
}
wiki.sh, the template repo's script that the handbook and its rules refer to, is at: $WIKI_SH
When the user runs it in a terminal, the command is: $TYPE"
if [ -n "$LINK" ]; then
  ctx="$ctx
$LINK"
fi
if [ "$compacted" = 1 ]; then
  ctx="$ctx

This session was just compacted. Before going on, capture anything in the summary that a later session would want and that the wiki doesn't hold yet, as the handbook's Capture section says. Then carry on with the user's request."
fi
if [ "$waiting" -gt 0 ]; then
  ctx="$ctx

$waiting note(s) in raw/ are waiting to be compiled. Session start says to compile them before the user's request."
fi
if [ -n "$wv" ] && [ -n "$tv" ] && [ "$wv" -lt "$tv" ]; then
  ctx="$ctx

This wiki's handbook is v$wv and the plugin's template is v$tv. Tell the user once: run $TYPE upgrade --all"
fi
emit "$ctx"
