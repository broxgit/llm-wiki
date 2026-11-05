#!/bin/sh
# PreToolUse hook for the llm-wiki Claude Code plugin. Hands the session the wiki
# reminders that apply to the tool call it is about to make: the lines under
# "## Reminders" in a wiki's wiki/conventions.md. A rule read at session start is
# often gone from mind two hours later, when it applies.
# The session-start hook writes each session's reminders, and reminders.py matches
# them. This wrapper only makes the common case cheap: no reminders, no Python.
# A hook must never block a session by accident: every path here exits 0.

# A background compile's own session gets its instructions in its prompt.
[ -z "${LLM_WIKI_BACKGROUND:-}" ] || exit 0
dir="${XDG_STATE_HOME:-$HOME/.local/state}/llm-wiki/reminders"
[ -d "$dir" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0
python3 -S "$(dirname "$0")/reminders.py" "$dir" 2>/dev/null
exit 0
