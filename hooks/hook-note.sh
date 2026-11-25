# shellcheck shell=sh
# hook_note, sourced by the plugin's hooks and by wiki.sh, never run on its own. POSIX sh,
# and safe under set -euo pipefail.
#
# A hook swallows every error, so a session never breaks. That is right, and it also meant
# nobody knew when one failed (code review D6). hook_note <hook> <exit code> <what> <error>
# adds one line to hooks.log in llm-wiki's state folder, which is never synced:
#
#   <UTC time> TAB <hook> TAB <exit code> TAB <what>: <the error's first line>
#
# Of a Python traceback, wherever it starts in the error, only the exception's name: what
# follows the name can quote the input. The message loses its control characters (a tab
# becomes a space), each byte outside ASCII becomes ?, and it is cut at 200 bytes, so nothing
# it quotes can make a second line or carry much of a file. The log keeps its last 200 lines,
# and wiki status counts the week's. It is written only when it is a plain file or isn't
# there: never through a link, and never into a pipe, which would block the hook. The state
# folder is where the rest of llm-wiki keeps its state, XDG_STATE_HOME as given. It never
# fails, and starts a few processes only when there is a failure to note.
# hooks/reminders.py writes the same line: change them together.
HOOK_LOG_KEEP=200
hook_note() {
  [ -n "${XDG_STATE_HOME:-}" ] || [ -n "${HOME:-}" ] || return 0
  _hn_dir="${XDG_STATE_HOME:-${HOME:-}/.local/state}/llm-wiki"
  _hn_f="$_hn_dir/hooks.log"
  _hn_nl='
'
  _hn_e="${4:-}"
  _hn_line="${_hn_e%%"$_hn_nl"*}"
  case "$_hn_e" in
    *"Traceback (most recent call last):"* | "  File \""*)
      # The exception's line is the first after the traceback's last File line and the
      # indented code under it. A message of several lines follows it, and is passed over.
      _hn_line="$(printf '%s\n' "$_hn_e" | LC_ALL=C awk '
        { l[NR] = $0 }
        $0 == "Traceback (most recent call last):" { from = NR }
        /^  File / { from = NR }
        END {
          n = "an exception"
          for (i = from + 1; i <= NR; i++) {
            if (l[i] ~ /^[ \t]/) continue
            if (l[i] ~ /^[A-Za-z_][A-Za-z0-9_.]*(:|$)/) { n = l[i]; sub(/:.*/, "", n) }
            break
          }
          print "Traceback: " n
        }' 2>/dev/null || true)"
      ;;
  esac
  _hn_m="${3:-a call}${_hn_line:+: $_hn_line}"
  _hn_m="$(printf '%s' "$_hn_m" | LC_ALL=C tr '\011\200-\377' ' ?' 2>/dev/null | LC_ALL=C tr -d '\000-\037\177' 2>/dev/null | LC_ALL=C cut -c 1-200 2>/dev/null || true)"
  case "${1:-}" in '' | *[!a-z0-9-]*) _hn_h=hook ;; *) _hn_h="$1" ;; esac
  case "${2:-}" in '' | *[!0-9]*) _hn_c=- ;; *) _hn_c="$2" ;; esac
  _hn_t="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
  {
    mkdir -p "$_hn_dir" || return 0
    if [ -L "$_hn_f" ] || { [ -e "$_hn_f" ] && [ ! -f "$_hn_f" ]; }; then return 0; fi
    printf '%s\t%s\t%s\t%s\n' "${_hn_t:-?}" "$_hn_h" "$_hn_c" "$_hn_m" >> "$_hn_f" || return 0
    _hn_n="$(wc -l < "$_hn_f" | tr -d ' ')" || return 0
    [ "${_hn_n:-0}" -gt "$HOOK_LOG_KEEP" ] || return 0
    # Trimmed through a file mktemp makes beside it, which goes whatever happens.
    _hn_tmp="$(mktemp "$_hn_f.XXXXXX")" || return 0
    tail -n "$HOOK_LOG_KEEP" "$_hn_f" > "$_hn_tmp" && mv -f "$_hn_tmp" "$_hn_f"
    [ ! -e "$_hn_tmp" ] || rm -f "${_hn_tmp:?}"
  } 2>/dev/null || true
  return 0
}
