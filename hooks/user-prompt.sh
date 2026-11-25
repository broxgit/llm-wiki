#!/bin/sh
# UserPromptSubmit hook for the llm-wiki Claude Code plugin. When the user sends a
# message, wiki.sh searches every wiki for its words and this hands the session the pages
# and notes that fit, beside the message. An agent that isn't handed a page mostly
# doesn't go looking for one. What the search counts, what is handed over once a session
# and how it is cut are in wiki.sh (prompt_recall); this reads Claude Code's JSON, in
# which the message is `prompt`, and replies with hookSpecificOutput.additionalContext.
# Lines an extension left for this repository (a CI failure on this branch) ride along:
# wiki.sh takes them in the same call, once the JSON has named the folder, and only when
# the notices folder exists, so this hook starts nothing more with none.
# It prints nothing at all when there is nothing to hand over. With no python3 it does
# nothing. A hook must never block a session by accident: every path exits 0.

# A background compile's own session gets its instructions in its prompt.
[ -z "${LLM_WIKI_BACKGROUND:-}" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0
root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
[ -x "$root/wiki.sh" ] || exit 0
# Its reply goes out as it comes. What it writes to standard error is kept, and when it fails,
# which __prompt-hook never does when it works, the first line goes in hooks.log
# (hooks/hook-note.sh). wiki.sh notes the failures it catches itself.
{ hook_e="$("$root/wiki.sh" __prompt-hook 2>&1 >&3 3>&-)"; hook_c=$?; } 3>&1
if [ "$hook_c" != 0 ]; then
  hook_note() { return 0; }
  # shellcheck source=hooks/hook-note.sh
  [ ! -r "$root/hooks/hook-note.sh" ] || . "$root/hooks/hook-note.sh" 2>/dev/null || true
  hook_note user-prompt "$hook_c" "wiki.sh __prompt-hook" "$hook_e"
fi
exit 0
