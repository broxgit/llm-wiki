#!/bin/sh
# UserPromptSubmit hook for the llm-wiki Claude Code plugin. When the user sends a
# message, wiki.sh searches every wiki for its words and this hands the session the pages
# and notes that fit, beside the message. An agent that isn't handed a page mostly
# doesn't go looking for one. What the search counts, what is handed over once a session
# and how it is cut are in wiki.sh (prompt_recall); this reads Claude Code's JSON, in
# which the message is `prompt`, and replies with hookSpecificOutput.additionalContext.
# It prints nothing at all when there is nothing to hand over. With no python3 it does
# nothing. A hook must never block a session by accident: every path exits 0.

# A background compile's own session gets its instructions in its prompt.
[ -z "${LLM_WIKI_BACKGROUND:-}" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0
root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
[ -x "$root/wiki.sh" ] || exit 0
"$root/wiki.sh" __prompt-hook 2>/dev/null
exit 0
