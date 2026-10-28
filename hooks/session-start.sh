#!/usr/bin/env bash
# SessionStart hook for the llm-wiki Claude Code plugin. Finds the wiki that covers the
# repository this session works in, and puts its handbook and index in the session's
# context. It does the job of the ~/.claude/CLAUDE.md line from `wiki.sh claude`, so the
# agent can't skip it. Runs on startup, resume, /clear and after compaction.
# A hook must never block a session: every path exits 0.
set -u

ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
WIKI_SH="$ROOT/wiki.sh"
WIKIS_DIR="${WIKIS_DIR:-$HOME/wikis}"
export WIKIS_DIR
DIR="${CLAUDE_PROJECT_DIR:-$PWD}"

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
# updates. Point the command at this version, rewriting it only when it changes.
CMD=""
if [ -n "${CLAUDE_PLUGIN_DATA:-}" ]; then
  CMD="$CLAUDE_PLUGIN_DATA/bin/wiki"
  shim="#!/bin/sh
# The llm-wiki plugin's terminal command. Its session hook rewrites this file when the plugin updates.
[ -x \"$WIKI_SH\" ] || { echo \"wiki: the llm-wiki plugin has updated. Start a Claude Code session once to refresh this command.\" >&2; exit 1; }
LLM_WIKI_CMD=wiki exec \"$WIKI_SH\" \"\$@\""
  if [ "$(cat "$CMD" 2>/dev/null)" != "$shim" ]; then
    mkdir -p "${CMD%/*}" && printf '%s\n' "$shim" > "$CMD" && chmod +x "$CMD" || CMD=""
  fi
fi
# How the user runs it in a terminal: `wiki` once it's on their PATH, the full path until then.
TYPE="${CMD:-$WIKI_SH}"
[ -n "$CMD" ] && [ "$(command -v wiki 2>/dev/null)" -ef "$CMD" ] && TYPE="wiki"
LINK=""
if [ -n "$CMD" ] && [ "$TYPE" != wiki ]; then
  LINK="\`wiki\` isn't on the user's PATH yet. If they ask to set up the wiki command, or the first time you give them a wiki.sh command to run, link it: \`mkdir -p ~/.local/bin && ln -sf \"$CMD\" ~/.local/bin/wiki\`. If ~/.local/bin isn't on their PATH, say which line to add to their shell profile. Offer this once, not every reply."
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
    note="No wiki covers the repository $repo yet, so the shared wiki below is this session's wiki. The first time there is something to file about $repo, create its wiki: $WIKI_SH new $repo"
  else
    note="This session isn't in a repository, so the shared wiki below is its wiki."
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

ctx="# llm-wiki

This session's knowledge wiki is $wiki${repo:+, for the repository $repo}. Its handbook (AGENTS.md) and index.md are below, already loaded. Follow the handbook from now on. Don't read either file again unless a pull changes it.
${note:+
$note
}
wiki.sh, the template repo's script that the handbook and its rules refer to, is at: $WIKI_SH
When the user runs it in a terminal, the command is: $TYPE"
if [ -n "$LINK" ]; then
  ctx="$ctx
$LINK"
fi
if [ "$waiting" -gt 0 ]; then
  ctx="$ctx

$waiting note(s) in raw/ are waiting to be compiled. Session start says to compile them before the user's request."
fi
if [ -n "$wv" ] && [ -n "$tv" ] && [ "$wv" -lt "$tv" ]; then
  ctx="$ctx

This wiki's handbook is v$wv and the plugin's template is v$tv. Tell the user once: run $TYPE upgrade --all"
fi
ctx="$ctx

## $wiki/AGENTS.md

$(cat "$wiki/AGENTS.md")

## $wiki/index.md

$(head -n 300 "$wiki/index.md" 2>/dev/null)"
if [ "$(wc -l < "$wiki/index.md" 2>/dev/null || echo 0)" -gt 300 ]; then
  ctx="$ctx
(index.md continues past 300 lines. Search it by keyword.)"
fi
emit "$ctx"
