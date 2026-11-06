#!/usr/bin/env bash
# Checks that the smoke test's parts add up to the whole suite: every check the full
# run makes is made in exactly one part, as many times, and nothing else is.
# CI runs the parts as separate jobs, so a check that falls between them would
# never run anywhere.
#
#   tests/smoke-parts.sh                run the full suite, then every part at once
#   tests/smoke-parts.sh --logs <dir>   compare logs already saved there, as
#                                       full.log and part-<n>.log
#
# Takes as long as the full suite plus its slowest part.
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SMOKE="$REPO/tests/smoke.sh"
D=""
if [ "${1:-}" = "--logs" ]; then
  D="${2:?--logs needs a folder}"
else
  D="$(mktemp -d)"
  trap 'rm -rf "$D"' EXIT
fi
parts="$("$SMOKE" --list | cut -f 1 | sort -un | tail -n 1)"
[ -n "$parts" ] || { echo "tests/smoke.sh --list printed no parts" >&2; exit 1; }

if [ "${1:-}" != "--logs" ]; then
  echo "Running the full suite..."
  "$SMOKE" > "$D/full.log" 2>&1
  echo "full: exit $?"
  # Each run has its own sandbox, so the parts can run side by side.
  pids=""
  for p in $(seq 1 "$parts"); do
    "$SMOKE" --part "$p" > "$D/part-$p.log" 2>&1 &
    pids="$pids $!"
  done
  p=0
  for pid in $pids; do
    p=$((p + 1))
    wait "$pid"
    echo "part $p: exit $?"
  done
fi

# results <log>: one line per check, "<section> | <result line>".
results() { awk '/^# /{ s = substr($0, 3) } /^(ok|FAIL|skip)  /{ print s " | " $0 }' "$1"; }

fail=0
results "$D/full.log" | sort > "$D/full.checks"
: > "$D/parts.checks"
for p in $(seq 1 "$parts"); do
  results "$D/part-$p.log" | sort > "$D/part-$p.checks"
  cat "$D/part-$p.checks" >> "$D/parts.checks"
  printf 'part %s: %s check(s), %s\n' "$p" "$(grep -c . "$D/part-$p.checks")" "$(tail -n 1 "$D/part-$p.log")"
done
sort -o "$D/parts.checks" "$D/parts.checks"
printf 'full:   %s check(s), %s\n' "$(grep -c . "$D/full.checks")" "$(tail -n 1 "$D/full.log")"

if ! cmp -s "$D/full.checks" "$D/parts.checks"; then
  fail=1
  echo
  echo "The parts don't make the same checks as the full run (< full only, > parts only):"
  diff "$D/full.checks" "$D/parts.checks" | grep '^[<>]'
fi
# The same check in two parts would be counted twice, or run with the wrong state in one.
sort -u "$D/full.checks" | while IFS= read -r line; do
  n=0
  for p in $(seq 1 "$parts"); do grep -qxF -- "$line" "$D/part-$p.checks" && n=$((n + 1)); done
  [ "$n" -le 1 ] || { echo "in $n parts: $line"; exit 1; }
done || fail=1
if grep -q ' | FAIL  ' "$D/full.checks" "$D/parts.checks"; then
  echo
  echo "Failed checks:"
  grep -h ' | FAIL  ' "$D/full.checks" "$D/parts.checks" | sort -u
  fail=1
fi
[ "$fail" -eq 0 ] && echo "The parts add up to the full run." || echo "The parts don't add up to the full run."
exit "$fail"
