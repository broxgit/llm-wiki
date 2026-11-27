#!/usr/bin/env bash
# Keeps handbook-hashes.tsv, the record of what each handbook version shipped.
#
#   scripts/handbook-hashes.sh             Add the lines for the template's version.
#   scripts/handbook-hashes.sh --replace   The same, replacing the lines that version has.
#   scripts/handbook-hashes.sh --check     Fail unless the record holds the template as it is.
#   scripts/handbook-hashes.sh --history   Write the whole record again from git history.
#
# One line for each file of each version: version<TAB>path<TAB>sha256, where the path is
# AGENTS.md or rules/<name>.md, and the sha256 is of the file's bytes. `wiki upgrade` reads
# it to tell a wiki's handbook that is as its version shipped it from one somebody edited,
# and keeps the text of an edited one. A version can have more than one line for a path:
# its files changed in more than one commit without a new number, and a wiki made from any
# of them is as that version shipped it.
#
# Run it as part of every handbook change, after the version in template/AGENTS.md is
# raised. With no new number, it refuses: the lines for a number already recorded are what
# wikis in the wild were made from, and a changed file under that number is the missing
# bump the smoke test catches. --replace is for a version that hasn't been released yet,
# such as a second change in the same pull request.
#
# --history walks every commit that changed template/AGENTS.md or template/rules/ and
# records the files as each had them, under the version its AGENTS.md names. A commit whose
# AGENTS.md has no version line is left out, as is any version no commit shows.
# Works with the bash that ships on macOS (3.2) and on Linux.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REC="$REPO/handbook-hashes.tsv"
TAB="$(printf '\t')"
# The two temporary files, beside the record so that the last step is one rename. A run that
# stops partway removes them.
TMP="$REC.tmp.$$" SEEN="$REC.seen.$$"
trap 'rm -f "$TMP" "$SEEN"' EXIT

die() { echo "error: $*" >&2; exit 1; }

# sha256: of standard input, as 64 hex digits. sha256sum, then shasum, then openssl.
sha256() {
  local h
  if command -v sha256sum >/dev/null 2>&1; then h="$(sha256sum)"
  elif command -v shasum >/dev/null 2>&1; then h="$(shasum -a 256)"
  elif command -v openssl >/dev/null 2>&1; then h="$(openssl dgst -sha256)"; h="${h##* }"
  else die "no sha256sum, shasum or openssl here, so no hash can be taken"
  fi
  h="${h%% *}"
  case "$h" in *[!0-9a-f]*) die "the hash came back as \"$h\"" ;; esac
  [ "${#h}" = 64 ] || die "the hash came back as \"$h\""
  printf '%s' "$h"
}

# version_in <file>: the number on the first "Handbook version N." line, or nothing.
# version_of_text: the same, of standard input. awk reads to the end, so nothing upstream is cut off
# early; one that fails, such as git show of a commit with no AGENTS.md, gives nothing.
version_of_text() { LC_ALL=C awk '!done && /^Handbook version [0-9]/ { s = substr($0, 18); sub(/[^0-9].*/, "", s); print s; done = 1 }'; }
version_in() { version_of_text < "$1"; }

# handbook_paths: the paths of the handbook under template/, one per line, by byte. A link there
# is refused: what it points to on this machine is no file a wiki is made from.
handbook_paths() {
  local f
  for f in "$REPO/template/AGENTS.md" "$REPO/template"/rules/*.md; do
    [ ! -L "$f" ] || die "${f#"$REPO/"} is a link. Do: make it a plain file, then run this again"
  done
  (cd "$REPO/template" && printf 'AGENTS.md\n' && for f in rules/*.md; do [ -f "$f" ] && printf '%s\n' "$f"; done) | LC_ALL=C sort
}

# current_lines: the record's lines for the template as it is now.
current_lines() {
  local v p
  v="$(version_in "$REPO/template/AGENTS.md")"
  [ -n "$v" ] || die "template/AGENTS.md has no \"Handbook version N.\" line"
  local h
  handbook_paths | while IFS= read -r p; do
    # Into a variable first: inside printf's arguments, a hash that failed was an empty field.
    h="$(sha256 < "$REPO/template/$p")"
    printf '%s\t%s\t%s\n' "$v" "$p" "$h"
  done
}

# well_formed <file>: every line is version<TAB>path<TAB>sha256, with a hash of 64 hex digits, and
# there is at least one. Checked before the record is replaced, so a failure never becomes it.
well_formed() {
  [ -s "$1" ] && LC_ALL=C awk -F '\t' 'NF != 3 || $1 !~ /^[0-9]+$/ || $2 !~ /^(AGENTS\.md|rules\/[A-Za-z0-9._-]+\.md)$/ || length($3) != 64 || $3 ~ /[^0-9a-f]/ { bad = 1 } END { exit bad }' "$1"
}

# tidy: lines in order, by version as a number, then path and hash by byte, each once.
tidy() { LC_ALL=C sort -t "$TAB" -k1,1n -k2,2 -k3,3 -u; }

# check_record <record>: the lines for the template's version are the template's files, no
# more and no fewer, and every line has the form upgrade reads.
check_record() {
  local rec="$1" v want have
  [ -f "$rec" ] || { echo "handbook-hashes.tsv is missing. Run: scripts/handbook-hashes.sh --history"; return 1; }
  if ! LC_ALL=C awk -F '\t' 'NF != 3 || $1 !~ /^[0-9]+$/ || $2 !~ /^(AGENTS\.md|rules\/[A-Za-z0-9._-]+\.md)$/ || length($3) != 64 || $3 ~ /[^0-9a-f]/ { print "line " NR " is not version<TAB>path<TAB>sha256: " $0; bad = 1 } END { exit bad }' "$rec"; then
    return 1
  fi
  v="$(version_in "$REPO/template/AGENTS.md")"
  want="$(current_lines | cut -f 2,3)"
  have="$(awk -F '\t' -v v="$v" '$1 == v { print $2 "\t" $3 }' "$rec" | LC_ALL=C sort)"
  # Each file of the template has its hash under this version.
  local p h missing="" extra=""
  while IFS="$TAB" read -r p h; do
    [ -n "$p" ] || continue
    printf '%s\n' "$have" | grep -qxF "$p$TAB$h" || missing="$missing $p"
  done <<EOF
$want
EOF
  # And each path recorded under this version is still in the template.
  while IFS="$TAB" read -r p h; do
    [ -n "$p" ] || continue
    printf '%s\n' "$want" | cut -f 1 | grep -qxF "$p" || extra="$extra $p"
  done <<EOF
$have
EOF
  if [ -n "$missing$extra" ]; then
    echo "template/ isn't what handbook-hashes.tsv records for handbook v$v.${missing:+ Changed or new:$missing.}${extra:+ Gone:$extra.}"
    echo "Do: if the handbook changed, raise the version in template/AGENTS.md, add a section for it to CHANGELOG.md, then run scripts/handbook-hashes.sh. If v$v isn't released yet, run scripts/handbook-hashes.sh --replace instead."
    return 1
  fi
}

# history_lines: the record from every commit that changed the handbook, then the template
# as it is now, which may not be committed yet.
history_lines() {
  local c v p b seen="$SEEN"
  git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "$REPO is not a git checkout, so it has no history to read"
  # --full-history: a commit on a branch that was merged is a state a wiki could be made from.
  git -C "$REPO" rev-list --full-history HEAD -- template/AGENTS.md template/rules | while IFS= read -r c; do
    # A commit with no AGENTS.md, or none with a version line, is left out.
    v="$({ git -C "$REPO" show "$c:template/AGENTS.md" 2>/dev/null || true; } | version_of_text)" || v=""
    [ -n "$v" ] || continue
    # "<mode> <type> <object><TAB><path>". Only a file's own bytes: a link's entry holds where it
    # points and a submodule's a commit, neither of them text a wiki was made from.
    git -C "$REPO" ls-tree -r "$c" -- template/AGENTS.md template/rules | while IFS="$TAB" read -r b p; do
      case "$b" in "100644 blob "* | "100755 blob "*) ;; *) continue ;; esac
      p="${p#template/}"
      case "$p" in AGENTS.md | rules/*.md) ;; *) continue ;; esac
      case "${p#rules/}" in */* | *[!A-Za-z0-9._-]* | -*) [ "$p" = AGENTS.md ] || continue ;; esac
      printf '%s\t%s\t%s\n' "$v" "$p" "${b##* }"
    done
  done | LC_ALL=C sort -u > "$seen"
  # One hash for each blob, however many versions it is in.
  local last="" lh=""
  LC_ALL=C sort -t "$TAB" -k3,3 "$seen" | while IFS="$TAB" read -r v p b; do
    if [ "$b" != "$last" ]; then lh="$(git -C "$REPO" cat-file blob "$b" | sha256)"; last="$b"; fi
    printf '%s\t%s\t%s\n' "$v" "$p" "$lh"
  done
  rm -f "$seen"
  current_lines
}

mode="${1:-}"
case "$mode" in
  "" | --replace)
    [ -f "$REC" ] || : > "$REC"
    check_record "$REC" >/dev/null 2>&1 && { echo "handbook-hashes.tsv already holds handbook v$(version_in "$REPO/template/AGENTS.md")"; exit 0; }
    v="$(version_in "$REPO/template/AGENTS.md")"
    [ -n "$v" ] || die "template/AGENTS.md has no \"Handbook version N.\" line"
    if [ -z "$mode" ] && awk -F '\t' -v v="$v" '$1 == v { found = 1 } END { exit !found }' "$REC"; then
      die "handbook-hashes.tsv already has lines for v$v, and template/ is no longer what they record. Do: raise the version in template/AGENTS.md and add a section for it to CHANGELOG.md, then run this again. If v$v isn't released yet, run scripts/handbook-hashes.sh --replace"
    fi
    tmp="$TMP"
    { awk -F '\t' -v v="$v" '$1 != v' "$REC"; current_lines; } | tidy > "$tmp"
    well_formed "$tmp" || die "the new lines aren't all version<TAB>path<TAB>sha256, so handbook-hashes.tsv is left as it was"
    mv "$tmp" "$REC"
    echo "handbook-hashes.tsv: wrote the lines for handbook v$v"
    ;;
  --check) check_record "$REC" ;;
  --history)
    tmp="$TMP"
    history_lines | tidy > "$tmp"
    well_formed "$tmp" || die "the new lines aren't all version<TAB>path<TAB>sha256, so handbook-hashes.tsv is left as it was"
    mv "$tmp" "$REC"
    n="$(cut -f 1 "$REC" | LC_ALL=C sort -un | wc -l | tr -d ' ')"
    echo "handbook-hashes.tsv: $(wc -l < "$REC" | tr -d ' ') lines, for $n versions"
    ;;
  -h | --help) sed -n '2,7p' "$0" | sed 's/^# //' ;;
  *) echo "usage: scripts/handbook-hashes.sh [--replace | --check | --history]" >&2; exit 2 ;;
esac
