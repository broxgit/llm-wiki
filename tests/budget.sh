#!/usr/bin/env bash
# The size budget: how many bytes of text an agent is handed, piece by piece.
#
#   tests/budget.sh [--check]   measure, and compare with tests/budget.tsv (the default)
#   tests/budget.sh --update    write what was measured into tests/budget.tsv
#   tests/budget.sh --print     print item<TAB>bytes for every item, and compare nothing
#
#   --repo <dir>     measure another checkout of this repository, such as an older commit
#                    in a worktree. An item that checkout can't produce is printed as -.
#   --record <file>  read or write this record instead of tests/budget.tsv
#
# Every change that adds text to what a session reads shows up here, because a pull
# request that changes a size has to change the recorded number, and the diff shows it.
# The items are fixed pieces of text: what the session hook and `wiki start` print for
# folders built here, the handbook and its rules, the skill's description, and the MCP
# server's instructions. The numbers are the same on any machine: the fixture is made in
# a temp folder with its own HOME and WIKIS_DIR, every path in it is rewritten to a fixed
# placeholder, and the things that vary (tips, the weekly report offer, downloads,
# background compile, the pull) are switched off or have nothing to do. A tip's text and
# a pull's message are the one kind of text this can't measure, since they come and go.
#
# Hard ceiling: a hook item may not reach 8000 bytes, whatever the record says. Claude
# Code cuts a hook's output at 10,000 characters. BUDGET_TEST_CEILING lowers it, for the
# smoke test, and can't raise it.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF_REPO="$(cd "$HERE/.." && pwd -P)"
HOOK_CEILING=8000

mode=check
R="$SELF_REPO"
RECORD="$HERE/budget.tsv"
usage() { printf 'usage: tests/budget.sh [--check | --update | --print] [--repo <dir>] [--record <file>]\n' >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --check) mode=check; shift ;;
    --update) mode=update; shift ;;
    --print) mode=print; shift ;;
    --repo | --record)
      [ $# -ge 2 ] || { printf 'tests/budget.sh: %s needs a value. Run: tests/budget.sh %s <value>\n' "$1" "$1" >&2; exit 2; }
      if [ "$1" = --repo ]; then
        R="$(cd "$2" 2>/dev/null && pwd -P)" || { printf 'tests/budget.sh: no folder %s. Run: tests/budget.sh --repo <a checkout of llm-wiki>\n' "$2" >&2; exit 2; }
      else
        RECORD="$2"
      fi
      shift 2 ;;
    *) usage ;;
  esac
done

T="$(mktemp -d)"
T="$(cd "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT
H="$T/home"
mkdir -p "$H"

# fx <command...>: run with an environment of its own, so nothing of the user's is read
# and nothing varies with it. The helper is off: the Bash is what is measured, and a test
# keeps the helper's answers the same.
fx() {
  env -i HOME="$H" PATH="$PATH" LC_ALL=C TZ=UTC WIKIS_DIR="$H/wikis" \
    LLM_WIKI_STYLE=off LLM_WIKI_NO_GO=1 GIT_CONFIG_NOSYSTEM=1 "$@"
}
W() { fx bash "$R/wiki.sh" "$@"; }

# count <text on stdin>: the bytes of it, with this run's folders written as placeholders.
# A path left over would make the number depend on where the tests ran.
count() {
  python3 -I -c '
import sys
s = sys.stdin.buffer.read()
if not s:
    sys.exit(1)
for a, b in zip(sys.argv[1::2], sys.argv[2::2]):
    s = s.replace(a.encode(), b.encode())
print(len(s))' "$T" "<tmp>" "$R" "<repo>" "$SELF_REPO" "<repo>"
}

# hook_bytes <project dir>: the bytes of the session hook's additionalContext there.
hook_bytes() {
  printf '{"source":"startup"}' \
    | fx CLAUDE_PLUGIN_ROOT="$R" CLAUDE_PLUGIN_DATA="$H/data" CLAUDE_PROJECT_DIR="$1" bash "$R/hooks/session-start.sh" 2>/dev/null \
    | python3 -I -c '
import json, sys
try:
    print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])
except Exception:
    sys.exit(1)' 2>/dev/null \
    | count 2>/dev/null || true
}
# The decoded text ends in the newline print adds; the record counts the text itself.
hook_item() {
  local n=""
  [ -f "$R/hooks/session-start.sh" ] && n="$(hook_bytes "$1")"
  case "$n" in '' | *[!0-9]*) printf -- '-' ;; *) printf '%s' $((n - 1)) ;; esac
}

# start_item <dir>: the bytes of `wiki.sh start` there, or - when it fails or isn't there.
start_item() {
  local n=""
  if [ -f "$R/wiki.sh" ] && (cd "$1" 2>/dev/null && fx LLM_WIKI_CMD=wiki bash "$R/wiki.sh" start > "$T/start.out" 2>&1); then
    n="$(count < "$T/start.out" 2>/dev/null)"
  fi
  case "$n" in '' | *[!0-9]*) printf -- '-' ;; *) printf '%s' "$n" ;; esac
}

# cmd_item <dir> <wiki.sh args...>: the bytes a wiki.sh command prints, run in a folder, or
# - when it fails or doesn't exist in this checkout.
cmd_item() {
  local dir="$1" n=""
  shift
  if [ -f "$R/wiki.sh" ] && (cd "$dir" 2>/dev/null && fx LLM_WIKI_CMD=wiki bash "$R/wiki.sh" "$@" > "$T/cmd.out" 2>&1); then
    n="$(count < "$T/cmd.out" 2>/dev/null)"
  fi
  case "$n" in '' | *[!0-9]*) printf -- '-' ;; *) printf '%s' "$n" ;; esac
}

file_item() { if [ -f "$1" ]; then wc -c < "$1" | tr -d ' '; else printf -- '-'; fi; }

# The fixture: wikis of two or three index lines, so the numbers are the tool's own text.
fixture() {
  local d
  mkdir -p "$H/wikis" "$H/ws" "$H/jobs"
  W init >/dev/null 2>&1
  for d in plain-repo alpha beta gamma delta; do W new "$d" >/dev/null 2>&1; done
  for d in global plain-repo alpha beta gamma delta; do
    if [ -d "$H/wikis/$d" ]; then
      printf '# Index\n\n## Concepts\n- [Fixture page](wiki/concepts/fixture.md): a page made for the size budget.\n' > "$H/wikis/$d/index.md"
    fi
  done
  # Wikis for the text that appears only when content triggers it: pages that mention a
  # ticket, a word to find, and notes waiting in raw/. All of it is tiny and fixed.
  for d in payments lookup notes-repo; do W new "$d" >/dev/null 2>&1; done
  if [ -d "$H/wikis/payments" ] && [ -d "$H/wikis/lookup" ] && [ -d "$H/wikis/notes-repo" ]; then
    mkdir -p "$H/wikis/payments/wiki/concepts" "$H/wikis/lookup/wiki/concepts" "$H/wikis/lookup/raw" "$H/wikis/notes-repo/raw"
    printf '# Index\n\n## Concepts\n- [Refund flow](wiki/concepts/refund.md): how PAY-7 refunds are decided.\n- [Ledger notes](wiki/concepts/ledger.md): the ledger tables.\n' > "$H/wikis/payments/index.md"
    printf '# Refund flow\n\nRefunds wait for review.\n' > "$H/wikis/payments/wiki/concepts/refund.md"
    printf '# Ledger notes\n\nChanged by PAY-7: one new column.\n' > "$H/wikis/payments/wiki/concepts/ledger.md"
    printf '# Index\n\n## Concepts\n- [Quokka care](wiki/concepts/quokka.md): what quokkas eat.\n' > "$H/wikis/lookup/index.md"
    printf '# Quokka care\n\nA quokka eats leaves.\n' > "$H/wikis/lookup/wiki/concepts/quokka.md"
    printf '# Animals\n\nA quokka is small.\n' > "$H/wikis/lookup/wiki/concepts/animals.md"
    printf 'A quokka was seen today.\n' > "$H/wikis/lookup/raw/2026-01-01-quokka.md"
    printf '# Index\n\n## Concepts\n- [Fixture page](wiki/concepts/fixture.md): a page made for the size budget.\n' > "$H/wikis/notes-repo/index.md"
    printf 'First note.\n' > "$H/wikis/notes-repo/raw/2026-01-01-first.md"
    printf 'Second note.\n' > "$H/wikis/notes-repo/raw/2026-01-02-second.md"
  fi
  mkdir -p "$H/tickets/PAY-7"
  git init -q "$H/ws/notes-repo"
  git init -q "$H/ws/pay-web"
  git -C "$H/ws/pay-web" symbolic-ref HEAD refs/heads/feature/PAY-7-x
  # A plain clone, and ticket folders with clones in them.
  git init -q "$H/ws/plain-repo"
  mkdir -p "$H/ws/INFRA-100" "$H/ws/INFRA-200" "$H/ws/EMPTY" "$H/ws/many" "$H/ws/scratch" "$H/jobs/INFRA-300"
  for d in alpha beta; do
    git init -q "$H/ws/INFRA-100/$d"
    git init -q "$H/jobs/INFRA-300/$d"
  done
  git init -q "$H/ws/INFRA-200/nowiki-one"
  git init -q "$H/ws/INFRA-200/nowiki-two"
  for d in 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35; do
    mkdir -p "$H/ws/many/dir$d"
  done
  # Nothing may offer a tip: a tip comes and goes with the machine's state.
  for d in harvest seed share-skill standup backfill stats stale find delegation; do
    W tips --mute "$d" >/dev/null 2>&1
  done
  # A pattern that says this folder has no wiki. The pattern that covers a ticket folder
  # is recorded after its first measurement, as the item says.
  # shellcheck disable=SC2088
  W workflows add '~/ws/scratch' none >/dev/null 2>&1
}

measure() {
  local f sd pi
  fixture
  printf 'hook: a clone with a wiki\t%s\n' "$(hook_item "$H/ws/plain-repo")"
  printf 'hook: a ticket folder, two wikis, no pattern\t%s\n' "$(hook_item "$H/ws/INFRA-100")"
  printf 'hook: a ticket folder with no wikis\t%s\n' "$(hook_item "$H/ws/INFRA-200")"
  printf 'hook: a folder holding nothing\t%s\n' "$(hook_item "$H/ws/EMPTY")"
  printf 'hook: a folder holding more than 30 folders\t%s\n' "$(hook_item "$H/ws/many")"
  printf 'hook: a folder a pattern sets to none\t%s\n' "$(hook_item "$H/ws/scratch")"
  printf 'start: a clone with a wiki\t%s\n' "$(start_item "$H/ws/plain-repo")"
  printf 'start: a ticket folder, two wikis, no pattern\t%s\n' "$(start_item "$H/ws/INFRA-100")"
  printf 'hook: a ticket folder with pages that mention it\t%s\n' "$(hook_item "$H/tickets/PAY-7")"
  printf 'start: a ticket folder with pages that mention it\t%s\n' "$(start_item "$H/tickets/PAY-7")"
  printf 'hook: a branch named for a ticket, no wiki\t%s\n' "$(hook_item "$H/ws/pay-web")"
  printf 'start: a branch named for a ticket, no wiki\t%s\n' "$(start_item "$H/ws/pay-web")"
  printf 'hook: a clone with two notes waiting\t%s\n' "$(hook_item "$H/ws/notes-repo")"
  printf 'start: a clone with two notes waiting\t%s\n' "$(start_item "$H/ws/notes-repo")"
  printf 'find: a word in an index line, a page and a note\t%s\n' "$(cmd_item "$H" find quokka)"
  printf 'workflows: one pattern recorded\t%s\n' "$(cmd_item "$H" workflows)"
  printf 'list: the fixture wikis\t%s\n' "$(cmd_item "$H" list)"
  # shellcheck disable=SC2088
  W workflows add '~/jobs/*-[0-9]*' inside >/dev/null 2>&1
  printf 'hook: a ticket folder, two wikis, pattern recorded\t%s\n' "$(hook_item "$H/jobs/INFRA-300")"
  printf 'template/AGENTS.md\t%s\n' "$(file_item "$R/template/AGENTS.md")"
  # The rules of this checkout and of the one the script lives in, so a rule added or
  # removed between them shows as a line with a - in one column.
  for f in "$R/template/rules/"*.md "$SELF_REPO/template/rules/"*.md; do
    [ -f "$f" ] && printf '%s\n' "${f##*/}"
  done | LC_ALL=C sort -u | while IFS= read -r f; do
    printf 'template/rules/%s\t%s\n' "$f" "$(file_item "$R/template/rules/$f")"
  done
  sd="$(sed -n '/^---$/,/^---$/{s/^description: *//p;}' "$R/skills/llm-wiki/SKILL.md" 2>/dev/null | head -n 1)"
  if [ -n "$sd" ]; then
    # What the file holds, a line's text, without the newline.
    printf 'skill: the description\t%s\n' "$(printf '%s' "$sd" | wc -c | tr -d ' ')"
  else
    printf 'skill: the description\t-\n'
  fi
  pi="$(python3 -I -c '
import ast, sys
try:
    tree = ast.parse(open(sys.argv[1], encoding="utf-8").read())
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(getattr(t, "id", "") == "INSTRUCTIONS" for t in node.targets):
            print(len(ast.literal_eval(node.value).encode("utf-8")))
            break
except Exception:
    pass' "$R/mcp/server.py" 2>/dev/null)"
  printf 'mcp: INSTRUCTIONS\t%s\n' "${pi:--}"
}

# problems <measured file> <record file>: one line for each item whose numbers differ,
# and one for each hook item at or over the ceiling.
problems() {
  awk -F '\t' -v ceil="$HOOK_CEILING" -v lower="${BUDGET_TEST_CEILING:-}" '
    BEGIN { if (lower ~ /^[0-9]+$/ && lower + 0 < ceil) ceil = lower + 0 }
    FNR == NR { m[$1] = $2; if (!($1 in seen)) { seen[$1] = 1; order[++n] = $1 } next }
    /^#/ || NF < 2 { next }
    { r[$1] = $2; if (!($1 in seen)) { seen[$1] = 1; order[++n] = $1 } }
    END {
      for (i = 1; i <= n; i++) {
        k = order[i]; a = (k in r) ? r[k] : "-"; b = (k in m) ? m[k] : "-"
        if (a == b) continue
        if (a ~ /^[0-9]+$/ && b ~ /^[0-9]+$/) printf "%s: recorded %s, measured %s (%+d)\n", k, a, b, b - a
        else printf "%s: recorded %s, measured %s\n", k, a, b
      }
      for (i = 1; i <= n; i++) {
        k = order[i]
        if (k ~ /^hook: / && (k in m) && m[k] ~ /^[0-9]+$/ && m[k] + 0 >= ceil)
          printf "CEILING %s: %s bytes, and a hook item has to stay under %d. Claude Code cuts a hook'"'"'s output at 10,000 characters.\n", k, m[k], ceil
      }
    }' "$1" "$2"
}

out="$T/measured"
measure | LC_ALL=C sort > "$out"

case "$mode" in
  print) cat "$out"; exit 0 ;;
  update)
    # A ceiling can't be recorded away.
    : > "$T/empty"
    if problems "$out" "$T/empty" | grep -q '^CEILING '; then
      problems "$out" "$T/empty" | grep '^CEILING ' >&2
      printf 'Do: shorten that text. The ceiling is in tests/budget.sh, and the record can'"'"'t change it.\n' >&2
      exit 1
    fi
    {
      printf '# Size budget: bytes of text an agent is handed, one fixed piece per line. Made by tests/budget.sh.\n'
      printf '# Run: tests/budget.sh --update when a change moves one, and say in the pull request why it did.\n'
      cat "$out"
    } > "$RECORD"
    printf 'recorded %s items in %s\n' "$(wc -l < "$out" | tr -d ' ')" "${RECORD#"$SELF_REPO"/}"
    exit 0 ;;
esac

# check
[ -f "$RECORD" ] || { printf 'tests/budget.sh: there is no record at %s. Run: tests/budget.sh --update\n' "$RECORD" >&2; exit 1; }
diffs="$(problems "$out" "$RECORD")"
if [ -z "$diffs" ]; then
  printf 'size budget: %s items, all as recorded\n' "$(wc -l < "$out" | tr -d ' ')"
  exit 0
fi
printf '%s\n' "$diffs"
if printf '%s\n' "$diffs" | grep -q '^CEILING '; then
  printf 'Do: shorten that text. The ceiling is in tests/budget.sh, and editing the record can'"'"'t raise it.\n'
fi
if printf '%s\n' "$diffs" | grep -qv '^CEILING '; then
  printf 'Run: tests/budget.sh --update, and say in the pull request why it changed\n'
fi
exit 1
