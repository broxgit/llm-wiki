#!/bin/sh
# PreToolUse hook for the llm-wiki Claude Code plugin. reminders.py does the work; this
# wrapper makes the common case cheap.
# It hands the session the wiki reminders that apply to the tool call it is about to
# make: the lines under "## Reminders" in a wiki's wiki/conventions.md. A rule read at
# session start is often gone from mind two hours later, when it applies. The
# session-start hook writes each session's reminders, and reminders.py matches them.
# It also logs two things an agent doing them from memory mostly doesn't: a read of a
# wiki page (a lookup, in stats.csv) and the start of a handoff to a subagent
# (delegation-log.csv).
# A call that is neither of those, in a session with no reminders, never starts Python.
# A read that doesn't name a .md file under a wiki/ folder doesn't either. The tool's
# name and the path are looked for in the call's text here; reminders.py checks them.
# A hook must never block a session by accident: every path here exits 0.

# A background compile's own session gets its instructions in its prompt.
[ -z "${LLM_WIKI_BACKGROUND:-}" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0
dir="${XDG_STATE_HOME:-$HOME/.local/state}/llm-wiki/reminders"
input="$(cat 2>/dev/null)" || input=""
case "$input" in
  # A read matters only when it names a markdown page under a wiki/ folder.
  *'"tool_name":"Read"'* | *'"tool_name": "Read"'*)
    case "$input" in *'/wiki/'*'.md"'*) ;; *) exit 0 ;; esac ;;
  # A handoff is logged whether or not the session has reminders.
  *'"tool_name":"Agent"'* | *'"tool_name": "Agent"'* | *'"tool_name":"Task"'* | *'"tool_name": "Task"'* | *'start_session"'*) ;;
  *) [ -d "$dir" ] || exit 0 ;;
esac
printf '%s' "$input" | python3 -S "$(dirname "$0")/reminders.py" "$dir" 2>/dev/null
exit 0
