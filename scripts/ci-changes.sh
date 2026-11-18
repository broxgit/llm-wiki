#!/usr/bin/env bash
# Says whether a change needs the test suite: reads the changed files on standard input,
# one a line, and prints true or false. CI's `changes` job runs it.
#
# false only when every changed file is one that nothing reads: no test, no command and no
# hook opens it, so the suite could not come out differently. That is the roadmap, the
# research folder, the licence, the README, and the guides in docs/: words for people.
#
# Two guides are not on it, because tests read them: docs/conventions.md, which holds the
# kit's version and checksum, and docs/extensions.md, which the extension tests check
# against the code. NEWS.md, CHANGELOG.md and the handbook are read by tests too.
# tests/smoke.sh checks that nothing has started reading a file that is skipped: a test
# that opens another guide has to take it off this list.
#
# Anything it can't be sure of is true: no files at all, or a name it doesn't know.
set -euo pipefail

unread() {
  case "$1" in
    *..*) return 1 ;;
    docs/conventions.md | docs/extensions.md) return 1 ;;
    ROADMAP.md | LICENSE | README.md | docs/research/*) return 0 ;;
    # Only the guides at the top of docs/: a * here would take in any folder under it.
    docs/*/*) return 1 ;;
    docs/*.md) return 0 ;;
  esac
  return 1
}

any=0
while IFS= read -r f || [ -n "$f" ]; do
  [ -n "$f" ] || continue
  any=1
  if ! unread "$f"; then echo true; exit 0; fi
done
if [ "$any" = 1 ]; then echo false; else echo true; fi
