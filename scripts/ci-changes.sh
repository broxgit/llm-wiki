#!/usr/bin/env bash
# Says whether a change needs the test suite: reads the changed files on standard input,
# one a line, and prints true or false. CI's `changes` job runs it.
#
# false only when every changed file is one that nothing reads: no test, no command and no
# hook opens it, so the suite could not come out differently. The list is short on purpose.
# NEWS.md, CHANGELOG.md, README.md, the handbook and the rest of docs/ are read by tests or
# shipped to users, so they are not on it. tests/smoke.sh checks that nothing has started
# reading a file that is.
#
# Anything it can't be sure of is true: no files at all, or a name it doesn't know.
set -euo pipefail

unread() {
  case "$1" in
    ROADMAP.md | docs/research/*) return 0 ;;
  esac
  return 1
}

any=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  any=1
  if ! unread "$f"; then echo true; exit 0; fi
done
if [ "$any" = 1 ]; then echo false; else echo true; fi
