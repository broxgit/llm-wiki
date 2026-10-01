#!/usr/bin/env bash
# wiki.sh: set up and look after LLM wikis built from this template.
# Works with the bash that ships on macOS (3.2) and on Linux.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$REPO/template"
WIKIS_DIR="${WIKIS_DIR:-$HOME/wikis}"
SHARED="global"

usage() {
  cat <<EOF
Usage: ./wiki.sh <command> [options]

  init                 Create the wiki collection at $(tilde "$WIKIS_DIR") and its shared wiki, $SHARED.
  new <name|path>      Create a wiki from the template. A bare name goes under $(tilde "$WIKIS_DIR").
  status               List wikis: handbook version, notes waiting, lock state.
  find <word>          Search every wiki's index for a word.
  stale [days]         List pages not verified in that many days (default 90).
  upgrade <name|path>  Bring a wiki's handbook and scaffold files up to the template's.
  upgrade --all        Do that for every wiki in the collection.
  unlock <name|path>   Free a stuck compile lock.
  claude               Add the wiki line to ~/.claude/CLAUDE.md so every session finds its wiki.

  --git   With init: make the whole collection one git repo.
          With new:  make that wiki its own repo, unless it is already inside one.

Name each wiki after the code repository it covers.
Set WIKIS_DIR to keep wikis somewhere other than ~/wikis.
EOF
}

die() { echo "error: $*" >&2; exit 1; }

# Show a path with ~ in place of the home folder. The tilde is meant literally.
# shellcheck disable=SC2088
tilde() {
  case "$1" in
    "$HOME"/*) printf '~/%s' "${1:$((${#HOME} + 1))}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# Turn a bare name or a path into an absolute path.
# shellcheck disable=SC2088
resolve() {
  case "$1" in
    /*) printf '%s' "$1" ;;
    "~/"*) printf '%s' "$HOME/${1:2}" ;;
    */*) printf '%s' "$PWD/$1" ;;
    *) printf '%s' "$WIKIS_DIR/$1" ;;
  esac
}

version_of() {
  sed -n 's/^Handbook version \([0-9][0-9]*\).*/\1/p' "$1" 2>/dev/null | head -n 1
}

is_wiki() { [ -f "$1/AGENTS.md" ] && [ -f "$1/index.md" ]; }

in_git_repo() { git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1; }

# Copy template files into a wiki. Never overwrites a file that is already there.
copy_missing() {
  local root="$1" f
  (cd "$TEMPLATE" && find . -type f -print) | while IFS= read -r f; do
    f="${f#./}"
    if [ ! -e "$root/$f" ]; then
      mkdir -p "$root/$(dirname "$f")"
      cp "$TEMPLATE/$f" "$root/$f"
    fi
  done
}

scaffold() {
  local root="$1" want_git="$2" tmp
  [ -d "$TEMPLATE" ] || die "template/ not found next to this script"
  case "$root/" in
    "$REPO"/*) die "refusing to create a wiki inside the template repo" ;;
  esac
  if is_wiki "$root"; then
    echo "exists:  $(tilde "$root") (left alone)"
    return 0
  fi
  mkdir -p "$root"
  copy_missing "$root"
  [ -f "$root/index.md" ] || printf '# Index\n' > "$root/index.md"
  [ -f "$root/log.md" ] || printf '# Log\n' > "$root/log.md"
  # The template's links.md assumes ~/wikis. Rewrite it when WIKIS_DIR is elsewhere.
  if [ "$WIKIS_DIR" != "$HOME/wikis" ] && [ -f "$root/links.md" ]; then
    tmp="$root/links.md.tmp"
    sed "s#~/wikis/$SHARED#$(tilde "$WIKIS_DIR/$SHARED")#" "$root/links.md" > "$tmp"
    mv "$tmp" "$root/links.md"
  fi
  echo "created: $(tilde "$root")"
  if [ "$want_git" = 1 ]; then
    if in_git_repo "$root"; then
      echo "git:     already inside a repo, skipped"
    else
      git -C "$root" init -q
      git -C "$root" add -A
      git -C "$root" commit -q -m "wiki: scaffold"
      echo "git:     initialized with a first commit"
    fi
  fi
}

# WIKIS.md marks the folder as a collection. Agents sync a collection's git repo.
write_collection_marker() {
  [ -f "$WIKIS_DIR/WIKIS.md" ] && return 0
  cat > "$WIKIS_DIR/WIKIS.md" <<'EOF'
# Wikis

This folder is a collection of LLM-maintained wikis. Each subfolder is one wiki, named after the code repository it covers. `global` holds knowledge that applies everywhere.

Each wiki's `AGENTS.md` is its handbook. Agents follow it. People can read any page directly.

- Knowledge about a repository's code lives in that repository's wiki, whichever session learned it.
- Wikis are created on demand. A missing folder means nothing has been recorded for that repository yet.
- This file marks the folder as a collection. If the folder is a git repo, agents commit and push their wiki changes to it.
EOF
  echo "created: $(tilde "$WIKIS_DIR/WIKIS.md")"
}

cmd_init() {
  local want_git="$1"
  mkdir -p "$WIKIS_DIR"
  write_collection_marker
  scaffold "$WIKIS_DIR/$SHARED" 0
  if [ "$want_git" = 1 ]; then
    if in_git_repo "$WIKIS_DIR"; then
      echo "git:     $(tilde "$WIKIS_DIR") is already in a repo, skipped"
    else
      [ -f "$WIKIS_DIR/.gitignore" ] || printf '.DS_Store\n.compile-lock\n' > "$WIKIS_DIR/.gitignore"
      git -C "$WIKIS_DIR" init -q
      git -C "$WIKIS_DIR" add -A
      git -C "$WIKIS_DIR" commit -q -m "wikis: start collection"
      echo "git:     $(tilde "$WIKIS_DIR") is now one repo for every wiki"
    fi
  fi
  cat <<EOF

Next:
  1. Give your agent access to $(tilde "$WIKIS_DIR") and $(tilde "$REPO").
  2. Let every session find its wiki:   ./wiki.sh claude
     Or create one yourself:            ./wiki.sh new <repository-name>
EOF
}

cmd_new() {
  local root="$1" want_git="$2"
  scaffold "$root" "$want_git"
  # The hints below are for a person at a terminal. An agent running this gets only the result.
  [ -t 1 ] || return 0
  cat <<EOF

Paste into a session to start using it:
  Read AGENTS.md in $(tilde "$REPO") and follow it. My wiki root is $(tilde "$root").

Add to the project's agent instruction file so new sessions find it on their own:
  This project's knowledge wiki is at $(tilde "$root"). Read its AGENTS.md at session start and follow it.
EOF
}

cmd_status() {
  local d v tv waiting f b lock line note found=0
  [ -d "$WIKIS_DIR" ] || { echo "no wikis at $(tilde "$WIKIS_DIR"). Run: ./wiki.sh init"; return 0; }
  tv="$(version_of "$TEMPLATE/AGENTS.md")"
  printf '%-26s %-9s %-8s %s\n' "WIKI" "HANDBOOK" "WAITING" "LOCK"
  for d in "$WIKIS_DIR"/*/; do
    d="${d%/}"
    is_wiki "$d" || continue
    found=1
    v="$(version_of "$d/AGENTS.md")"
    waiting=0
    for f in "$d"/raw/*; do
      [ -f "$f" ] || continue
      b="${f##*/}"
      b="${b%.*}"
      [ -e "$d/wiki/sources/$b.md" ] || waiting=$((waiting + 1))
    done
    lock="free"
    if [ -f "$d/.compile-lock" ]; then
      line="$(head -n 1 "$d/.compile-lock")"
      case "$line" in held*) lock="$line" ;; esac
    fi
    note=""
    if [ -n "$tv" ] && [ "${v:-0}" -lt "$tv" ]; then note="  <- behind template v$tv, run: ./wiki.sh upgrade ${d##*/}"; fi
    printf '%-26s %-9s %-8s %s%s\n' "${d##*/}" "v${v:-?}" "$waiting" "$lock" "$note"
  done
  [ "$found" = 1 ] || echo "(none yet. Run: ./wiki.sh init)"
}

cmd_find() {
  local word="$1" d hits found=0
  [ -d "$WIKIS_DIR" ] || die "no wikis at $(tilde "$WIKIS_DIR")"
  for d in "$WIKIS_DIR"/*/; do
    d="${d%/}"
    [ -f "$d/index.md" ] || continue
    hits="$(grep -i -F -- "$word" "$d/index.md" || true)"
    [ -n "$hits" ] || continue
    found=1
    echo "${d##*/}:"
    printf '%s\n' "$hits" | sed 's/^/  /'
  done
  [ "$found" = 1 ] || echo "no index mentions: $word"
}

# The date N days ago, as YYYY-MM-DD. GNU date first, then the BSD date on macOS.
days_ago() {
  date -u -d "$1 days ago" +%Y-%m-%d 2>/dev/null || date -u -v-"$1"d +%Y-%m-%d
}

cmd_stale() {
  local days="$1" cutoff d f v rel found=0
  case "$days" in
    '' | *[!0-9]*) die "stale takes a number of days" ;;
  esac
  [ -d "$WIKIS_DIR" ] || die "no wikis at $(tilde "$WIKIS_DIR")"
  cutoff="$(days_ago "$days")"
  for d in "$WIKIS_DIR"/*/; do
    d="${d%/}"
    is_wiki "$d" || continue
    [ -d "$d/wiki" ] || continue
    while IFS= read -r f; do
      v="$(sed -n 's/^verified: *\([0-9-]*\).*/\1/p' "$f" | head -n 1)"
      rel="${f:$((${#d} + 1))}"
      if [ -z "$v" ]; then
        echo "${d##*/}: $rel  (never verified)"
        found=1
      elif [[ "$v" < "$cutoff" ]]; then
        echo "${d##*/}: $rel  (verified $v)"
        found=1
      fi
    done < <(find "$d/wiki" -type f -name '*.md' ! -path '*/sources/*' | sort)
  done
  [ "$found" = 1 ] || echo "nothing older than $days days (cutoff $cutoff)"
}

upgrade_one() {
  local root="$1" tv wv
  is_wiki "$root" || die "$(tilde "$root") is not a wiki (needs AGENTS.md and index.md)"
  tv="$(version_of "$TEMPLATE/AGENTS.md")"
  wv="$(version_of "$root/AGENTS.md")"
  if [ "${wv:-0}" -ge "${tv:-0}" ]; then
    echo "handbook: already v${wv:-?}, nothing to replace"
  else
    # Outside git there is no history, so keep the old handbook beside the new one.
    in_git_repo "$root" || cp "$root/AGENTS.md" "$root/AGENTS.md.bak"
    cp "$TEMPLATE/AGENTS.md" "$root/AGENTS.md"
    # The rules files are part of the handbook and move with its version.
    if [ -d "$TEMPLATE/rules" ]; then
      mkdir -p "$root/rules"
      cp "$TEMPLATE"/rules/*.md "$root/rules/"
    fi
    echo "handbook: v${wv:-?} -> v$tv"
  fi
  # Older scaffolds pointed CLAUDE.md at the handbook in words. An import is reliable.
  if [ -f "$root/CLAUDE.md" ] && ! grep -q '^@AGENTS\.md' "$root/CLAUDE.md" \
    && [ "$(wc -l < "$root/CLAUDE.md" | tr -d ' ')" -le 1 ]; then
    cp "$TEMPLATE/CLAUDE.md" "$root/CLAUDE.md"
    echo "CLAUDE.md: switched to an import of AGENTS.md"
  fi
  copy_missing "$root"
  if [ -f "$root/.gitignore" ] && ! grep -qxF '.compile-lock' "$root/.gitignore"; then
    printf '.compile-lock\n' >> "$root/.gitignore"
    echo ".gitignore: added .compile-lock"
  fi
  echo "done:     $(tilde "$root")"
}

cmd_upgrade_all() {
  local d found=0
  [ -d "$WIKIS_DIR" ] || die "no wikis at $(tilde "$WIKIS_DIR")"
  for d in "$WIKIS_DIR"/*/; do
    d="${d%/}"
    is_wiki "$d" || continue
    found=1
    echo "== ${d##*/}"
    upgrade_one "$d"
  done
  [ "$found" = 1 ] || echo "(no wikis to upgrade)"
}

cmd_unlock() {
  local root="$1"
  is_wiki "$root" || die "$(tilde "$root") is not a wiki"
  printf 'free\n' > "$root/.compile-lock"
  echo "unlocked: $(tilde "$root")"
}

cmd_claude() {
  local f="$HOME/.claude/CLAUDE.md" dir line
  dir="$(tilde "$WIKIS_DIR")"
  line="My knowledge wikis live in $dir, one folder per repository, named after the repository (the last part of its remote URL, or its folder name), plus a shared one at $dir/$SHARED. At session start, find the wiki for the repository you are working in, read its AGENTS.md, and follow it. If that repository has no wiki yet, read $dir/$SHARED/AGENTS.md and follow that, and create the repository's wiki with \`$(tilde "$REPO")/wiki.sh new <repository-name>\` the first time you have something to file there. Outside any repository, use the shared wiki."
  if [ -f "$f" ] && grep -qF "knowledge wikis live in" "$f"; then
    echo "already there: ~/.claude/CLAUDE.md has a wiki line. Edit it by hand to change it."
    return 0
  fi
  mkdir -p "$HOME/.claude"
  if [ -s "$f" ]; then printf '\n' >> "$f"; fi
  printf '%s\n' "$line" >> "$f"
  echo "added to ~/.claude/CLAUDE.md:"
  echo "  $line"
}

# ---- argument parsing ----
[ $# -ge 1 ] || { usage; exit 1; }
cmd="$1"
shift
want_git=0
want_all=0
target=""
for arg in "$@"; do
  case "$arg" in
    --git) want_git=1 ;;
    --all) want_all=1 ;;
    -h | --help) usage; exit 0 ;;
    -*) die "unknown option: $arg" ;;
    *) [ -z "$target" ] || die "too many arguments"; target="$arg" ;;
  esac
done

need_target() { [ -n "$target" ] || die "$cmd needs a wiki name or path"; }

case "$cmd" in
  init) cmd_init "$want_git" ;;
  new) need_target; cmd_new "$(resolve "$target")" "$want_git" ;;
  status) cmd_status ;;
  find) [ -n "$target" ] || die "find needs a word"; cmd_find "$target" ;;
  stale) cmd_stale "${target:-90}" ;;
  upgrade)
    if [ "$want_all" = 1 ]; then cmd_upgrade_all; else need_target; upgrade_one "$(resolve "$target")"; fi
    ;;
  unlock) need_target; cmd_unlock "$(resolve "$target")" ;;
  claude) cmd_claude ;;
  -h | --help | help) usage ;;
  *) usage; exit 1 ;;
esac
