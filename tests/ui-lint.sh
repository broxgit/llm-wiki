#!/usr/bin/env bash
# ui-lint.sh: commands print through ui.sh's pieces, never a colour code. docs/conventions.md.
# Fails on a colour code (\033[ \e[ \E[ \x1b[ in either case, tput setaf or setab, or an escape
# byte itself), an S_ or M_ variable, or a call to version 2's pieces (say_ok, say_warn, say_head,
# say_dim, say_next) in a shell script other than ui.sh, and names the function each is in. A
# comment line doesn't count.
#
#   tests/ui-lint.sh [--report] [--functions] [file...]
#
# --report lists what it finds and exits 0: the smoke test runs it so until every command has
# moved. --functions prints only the functions left, one a line. With no file, it reads the
# tool's scripts: each .sh at the top of the repository, and the hooks. The same file in each tool.
# Works with the bash that ships on macOS (3.2) and on Linux.
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
report=no only=no
while [ $# -gt 0 ]; do
  case "$1" in
    --report) report=yes && shift ;;
    --functions) only=yes && report=yes && shift ;;
    -h | --help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//' && exit 0 ;;
    -*) printf 'error: no option %s. Run: tests/ui-lint.sh --help\n' "$1" >&2 && exit 2 ;;
    *) break ;;
  esac
done
if [ $# -eq 0 ]; then
  for f in "$REPO"/*.sh "$REPO"/hooks/*.sh; do [ ! -f "$f" ] || set -- "$@" "$f"; done
fi
found="$(LC_ALL=C awk -v esc="$(printf '\033')" '
  FNR == 1 { fn = "(top level)"; f = FILENAME; sub(/.*\//, "", f) }
  f == "ui.sh" { next }
  match($0, /^[A-Za-z_][A-Za-z0-9_]*\(\) *\{/) { fn = substr($0, 1, index($0, "(") - 1) }
  /^[ \t]*#/ { next }
  index($0, esc) || /\\033\[|\\e\[|\\E\[|\\[xX]1[bB]\[|tput +seta[fb]|\$\{?[SM]_[A-Z]|(^|[^A-Za-z0-9_])say_(ok|warn|head|dim|next)([^A-Za-z0-9_]|$)/ {
    printf "%s:%d\t%s\n", f, FNR, fn
  }' "$@")"
if [ -z "$found" ]; then
  [ "$only" = yes ] || echo "ui-lint: no colour codes, S_ or M_ variables, or version 2 pieces outside ui.sh."
  exit 0
fi
fns="$(printf '%s\n' "$found" | cut -f 2 | LC_ALL=C sort | uniq -c | LC_ALL=C sort -k 2)"
if [ "$only" = yes ]; then
  printf '%s\n' "$fns" | sed 's/^ *[0-9]* //'
  exit 0
fi
printf 'ui-lint: %s line(s) in %s function(s) still print without the kit:\n' "$(printf '%s\n' "$found" | wc -l | tr -d ' ')" "$(printf '%s\n' "$fns" | wc -l | tr -d ' ')"
printf '%s\n' "$fns" | awk '{ printf "  %-28s %s line(s)\n", $2, $1 }'
[ "$report" = yes ] && exit 0
echo "Move each to the pieces in ui.sh: docs/conventions.md says which."
exit 1
