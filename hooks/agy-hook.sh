#!/bin/sh
# Antigravity's tool-call hooks for the llm-wiki plugin, the counterpart of
# pre-tool-use.sh. `agy-hook.sh tool` is the PreToolUse hook and `agy-hook.sh invoke`
# the PreInvocation hook: reminders.py does the work, and this only makes the common
# case cheap (no reminders, no Python) and sees that every path ends with a reply.
# Antigravity doesn't document its hooks' exit codes, so a reply is always printed,
# the one that lets the call go, and the exit is 0.
# wiki setup antigravity and __agy-start copy this and reminders.py into the plugin's
# hooks folder, so they stay where Antigravity runs them after a plugin update.
event="${1:-tool}"
case "$event" in invoke) none='{}' ;; *) none='{"decision": "allow"}' ;; esac
state="${XDG_STATE_HOME:-$HOME/.local/state}/llm-wiki"
dir="$state/reminders"
note() {
  printf '%s\t%s\t\t\t%s\n' "$(date +%Y-%m-%dT%H:%M:%S 2>/dev/null)" "$event" "$1" 2>/dev/null >> "$state/agy-hooks.log" \
    || printf '%s\t%s\t\t\t%s\n' "$(date +%Y-%m-%dT%H:%M:%S 2>/dev/null)" "$event" "$1" 2>/dev/null >> "${TMPDIR:-/tmp}/llm-wiki-agy-hooks.log" \
    || true
}
if [ -n "${LLM_WIKI_BACKGROUND:-}" ]; then printf '%s\n' "$none"; exit 0; fi
if [ ! -d "$dir" ]; then note no-state; printf '%s\n' "$none"; exit 0; fi
if ! command -v python3 >/dev/null 2>&1; then note no-python; printf '%s\n' "$none"; exit 0; fi
out="$(python3 -S "$(dirname "$0")/reminders.py" "$dir" --antigravity "$event" 2>/dev/null)" || out=""
printf '%s\n' "${out:-$none}"
exit 0
