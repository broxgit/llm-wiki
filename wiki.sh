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

  setup                Walk through every setting, step by step. Safe to rerun.
  setup --new          Only what's new since you last ran it, such as after a template update.
  setup --list         Print current settings without asking.
  init                 Create the wiki collection at $(tilde "$WIKIS_DIR") and its shared wiki, $SHARED.
  new <name|path>      Create a wiki from the template. A bare name goes under $(tilde "$WIKIS_DIR").
  cover <wiki> <repo>...  Record that one wiki covers several repositories.
  which <repo>         Print the wiki that covers a repository.
  status               List wikis: handbook version, notes waiting, lock state.
  find <word>          Search every wiki's index for a word.
  stale [days]         List pages not verified in that many days (default 90).
  patterns             Recurring feedback across wikis, and which patterns are ready to propose.
  delegation [off|ask|auto]  Show handoff mode and results by kind of work, or set the mode.
  upgrade <name|path>  Bring a wiki's handbook and scaffold files up to the template's.
  upgrade --all        Do that for every wiki in the collection.
  unlock <name|path>   Free a stuck compile lock.
  claude               Add the wiki line to ~/.claude/CLAUDE.md so every session finds its wiki.

  journal              Show the work journal's settings and today's entry count.
  journal on | off     Turn the journal on or off. It is on by default.
  journal set <key> <value>  Change a setting. See $(tilde "$WIKIS_DIR")/journal/config.
  journal note [--day DATE] [--at HH:MM] <project> <text>
                       Add one line to today's journal, or a past day's.
  journal backfill [--since 14d] [--until DATE]
                       Digest past Claude Code sessions into journal/backfill.md.
                       An agent turns the digest into entries.
  journal path | prune Print today's journal file. Delete days older than keep_days.
  standup [options]    Gather what you did: commits, journal lines, wiki notes,
                       work in progress, open checks. An agent turns it into a report.
                       --since lastworkday|yesterday|today|week|lastweek|7d|DATE
                       --until DATE  --day DATE  --format standup|summary|detailed
                       --only GLOB  --exclude GLOB  --save

  --git   With init: make the whole collection one git repo.
          With new:  make that wiki its own repo, unless it is already inside one.

Name a wiki after the repository it covers. For a project that spans several
repositories, name it after the project and list the repositories with cover.
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

# Drop . and .. from an absolute path without touching the disk. The path may not exist yet.
normalize() {
  local IFS=/ part out=""
  for part in $1; do
    case "$part" in
      '' | .) ;;
      ..) out="${out%/*}" ;;
      *) out="$out/$part" ;;
    esac
  done
  printf '%s' "${out:-/}"
}

# Turn a bare name or a path into an absolute path.
# shellcheck disable=SC2088
resolve() {
  case "$1" in
    /*) normalize "$1" ;;
    "~/"*) normalize "$HOME/${1:2}" ;;
    */*) normalize "$PWD/$1" ;;
    *) printf '%s' "$WIKIS_DIR/$1" ;;
  esac
}

# A wiki is named after a repository, so its name must be one a repository can have.
valid_name() {
  case "$1" in
    '' | .* | -* | *[!A-Za-z0-9._-]*) return 1 ;;
  esac
}

version_of() {
  sed -n 's/^Handbook version \([0-9][0-9]*\).*/\1/p' "$1" 2>/dev/null | head -n 1
}

is_wiki() { [ -f "$1/AGENTS.md" ] && [ -f "$1/index.md" ]; }

in_git_repo() { git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1; }

# Copy template files into a wiki. Never overwrites a file that is already there.
copy_missing() {
  local root="$1" report="${2:-}" f
  (cd "$TEMPLATE" && find . -type f -print) | while IFS= read -r f; do
    f="${f#./}"
    if [ ! -e "$root/$f" ]; then
      mkdir -p "$root/$(dirname "$f")"
      cp "$TEMPLATE/$f" "$root/$f"
      case "$report:$f" in report:*.gitkeep | :*) ;; *) echo "added:    $f" ;; esac
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
      install_hook "$root"
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

This folder is a collection of LLM-maintained wikis. Each subfolder is one wiki. Most cover a single code repository and are named after it. A wiki for a project that spans several repositories is named after the project and lists them in its `repos.md`. `global` holds knowledge that applies everywhere.

Each wiki's `AGENTS.md` is its handbook. Agents follow it. People can read any page directly.

- Knowledge about a project lives in that project's wiki, whichever session learned it.
- Wikis are created on demand. A missing folder means nothing has been recorded for that repository yet.
- This file marks the folder as a collection. If the folder is a git repo, agents commit and push their wiki changes to it.
EOF
  echo "created: $(tilde "$WIKIS_DIR/WIKIS.md")"
}

# Print the name of the wiki that covers a repository: the wiki named after it,
# or the one whose repos.md lists it. Prints nothing when there is none.
which_wiki() {
  local name="$1" d
  if is_wiki "$WIKIS_DIR/$name"; then
    printf '%s' "$name"
    return 0
  fi
  for d in "$WIKIS_DIR"/*/; do
    d="${d%/}"
    is_wiki "$d" || continue
    if [ -f "$d/repos.md" ] && grep -qxF -- "- $name" "$d/repos.md"; then
      printf '%s' "${d##*/}"
      return 0
    fi
  done
  return 0
}

cmd_which() {
  local name="$1" w
  w="$(which_wiki "$name")"
  if [ -n "$w" ]; then
    tilde "$WIKIS_DIR/$w"
    printf '\n'
  else
    echo "no wiki covers $name" >&2
    exit 1
  fi
}

# cover <wiki> <repo>...: record that one wiki covers several repositories.
cmd_cover() {
  local wiki="$1" root repo owner
  shift
  root="$(resolve "$wiki")"
  is_wiki "$root" || die "$(tilde "$root") is not a wiki"
  [ $# -ge 1 ] || die "cover needs at least one repository name"
  [ -f "$root/repos.md" ] || printf '# Repositories\n' > "$root/repos.md"
  for repo in "$@"; do
    owner="$(which_wiki "$repo")"
    if [ -n "$owner" ] && [ "$WIKIS_DIR/$owner" != "$root" ]; then
      echo "skipped: $repo is already covered by the wiki $owner"
    elif grep -qxF -- "- $repo" "$root/repos.md"; then
      echo "already listed: $repo"
    else
      printf -- '- %s\n' "$repo" >> "$root/repos.md"
      echo "covers:  $repo"
    fi
  done
}

init_collection() {
  mkdir -p "$WIKIS_DIR"
  write_collection_marker
  scaffold "$WIKIS_DIR/$SHARED" 0
  write_journal_config
  write_delegation_file
}

git_init_collection() {
  if in_git_repo "$WIKIS_DIR"; then
    echo "git:     $(tilde "$WIKIS_DIR") is already in a repo, skipped"
    install_hook "$WIKIS_DIR"
    return 0
  fi
  [ -f "$WIKIS_DIR/.gitignore" ] || printf '.DS_Store\n.compile-lock\n' > "$WIKIS_DIR/.gitignore"
  git -C "$WIKIS_DIR" init -q
  install_hook "$WIKIS_DIR"
  apply_journal_commit
  apply_delegation_ignore
  echo "git:     $(tilde "$WIKIS_DIR") is now one repo for every wiki"
  git_first_commit
}

# Commit everything, unless git has no name and email to commit as.
git_first_commit() {
  if [ -z "$(git -C "$WIKIS_DIR" config user.email || true)" ] || [ -z "$(git -C "$WIKIS_DIR" config user.name || true)" ]; then
    echo "git:     no commit name or email set yet, so nothing is committed. ./wiki.sh setup git sets them."
    return 0
  fi
  git -C "$WIKIS_DIR" add -A
  git -C "$WIKIS_DIR" commit -q -m "wikis: start collection"
  echo "git:     first commit made"
}

# ---- secret scan ------------------------------------------------------------
# A pre-commit hook runs gitleaks over staged files, so a key an agent pasted into
# a note never reaches the remote. It goes only in a repo that belongs to the
# wikis: the collection, or a wiki that is its own repo. Never a project's repo.
HOOK_SRC="$REPO/hooks/pre-commit"
HOOK_MARK="# llm-wiki secret scan"

# hook_file <repo dir>: where git looks for this repo's pre-commit hook.
hook_file() {
  local gd
  gd="$(git -C "$1" rev-parse --git-common-dir 2>/dev/null)" || return 1
  case "$gd" in /*) ;; *) gd="$1/$gd" ;; esac
  printf '%s/hooks/pre-commit' "$gd"
}

# hook_state <repo dir>: ours, other (someone else's hook), hookspath, or none.
hook_state() {
  local f
  if [ -n "$(git -C "$1" config --get core.hooksPath || true)" ]; then echo hookspath; return 0; fi
  f="$(hook_file "$1")" || { echo none; return 0; }
  if [ ! -f "$f" ]; then echo none
  elif grep -qF "$HOOK_MARK" "$f"; then echo ours
  else echo other
  fi
}

# install_hook <repo dir>: put the hook in place, or bring ours up to date. Leaves other hooks alone.
install_hook() {
  local dir="$1" f
  in_git_repo "$dir" && [ -f "$HOOK_SRC" ] || return 0
  case "$(hook_state "$dir")" in
    hookspath)
      echo "note:    git here uses core.hooksPath, so the secret scan wasn't installed. To add it, call $(tilde "$HOOK_SRC") from your pre-commit hook."
      return 0
      ;;
    other)
      echo "note:    $(tilde "$dir") already has a pre-commit hook, left alone. To add the secret scan, call $(tilde "$HOOK_SRC") from it."
      return 0
      ;;
  esac
  f="$(hook_file "$dir")"
  cmp -s "$HOOK_SRC" "$f" 2>/dev/null && return 0
  mkdir -p "$(dirname "$f")"
  cp "$HOOK_SRC" "$f"
  chmod +x "$f"
  echo "hook:    secret scan on commits in $(tilde "$dir")"
  command -v gitleaks >/dev/null 2>&1 || echo "note:    gitleaks isn't installed, so commits aren't scanned yet. Install it: brew install gitleaks"
}

# wiki_repo <wiki root>: the repo a wiki's hook belongs in, if any: the wiki's own
# repo, or the collection's. Prints nothing for a wiki inside some other project.
wiki_repo() {
  local top here
  top="$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)" || return 0
  here="$(cd "$1" && pwd -P)"
  if [ "$top" = "$here" ]; then printf '%s' "$1"; return 0; fi
  if [ -f "$WIKIS_DIR/WIKIS.md" ] && [ "$top" = "$(cd "$WIKIS_DIR" && pwd -P)" ]; then printf '%s' "$WIKIS_DIR"; fi
}

cmd_init() {
  init_collection
  if [ "$1" = 1 ]; then git_init_collection; fi
  cat <<EOF

Next:
  1. Give your agent access to $(tilde "$WIKIS_DIR") and $(tilde "$REPO").
  2. Walk through the rest:             ./wiki.sh setup
     Or just let sessions find wikis:   ./wiki.sh claude
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
  local d v tv waiting f b lock line note since n found=0
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
    if [ "$waiting" -ge 5 ]; then note="$note  <- compile due"; fi
    # Ingest entries since the last lint entry. The handbook lints at 10.
    since="$(awk '/^## [0-9-]+ lint/{n=0} /^## [0-9-]+ ingest/{n++} END{print n+0}' "$d/log.md" 2>/dev/null)"
    if [ "${since:-0}" -ge 10 ]; then note="$note  <- lint due ($since ingests)"; fi
    n="$(patterns_ledger "$d" | grep -c '^ready|' || true)"
    if [ "${n:-0}" -gt 0 ]; then note="$note  <- $n pattern(s) ready"; fi
    if [ -n "$tv" ] && [ "${v:-0}" -lt "$tv" ]; then note="$note  <- behind template v$tv, run: ./wiki.sh upgrade ${d##*/}"; fi
    # Someone upgraded a shared wiki with a newer template than this clone.
    if [ -n "$tv" ] && [ "${v:-0}" -gt "$tv" ]; then note="$note  <- ahead of your template v$tv, run: git -C $(tilde "$REPO") pull"; fi
    if [ -f "$d/repos.md" ] && grep -q '^- ' "$d/repos.md"; then
      note="$note  covers: $(sed -n 's/^- //p' "$d/repos.md" | tr '\n' ' ')"
    fi
    printf '%-26s %-9s %-8s %s%s\n' "${d##*/}" "v${v:-?}" "$waiting" "$lock" "$note"
  done
  [ "$found" = 1 ] || echo "(none yet. Run: ./wiki.sh init)"
  if [ -f "$JOURNAL_CFG" ]; then
    echo "journal: $(journal_get enabled), commit $(journal_get commit), entries $(journal_get entries)"
  fi
  if [ -f "$DELEG_FILE" ]; then echo "delegation: mode $(deleg_mode)"; fi
  if in_git_repo "$WIKIS_DIR" && [ -f "$WIKIS_DIR/WIKIS.md" ]; then
    case "$(hook_state "$WIKIS_DIR")" in
      ours) command -v gitleaks >/dev/null 2>&1 || echo "secrets: commits aren't scanned, gitleaks isn't installed. Run: brew install gitleaks" ;;
      none) echo "secrets: commits aren't scanned. Run: ./wiki.sh upgrade --all" ;;
      *) echo "secrets: another pre-commit hook is in place. Call $(tilde "$HOOK_SRC") from it to scan commits." ;;
    esac
  fi
  n="$(setup_pending | wc -l | tr -d ' ')"
  if [ ! -f "$SETUP_STATE" ]; then
    echo "setup:   never run on this machine. Run: ./wiki.sh setup"
  elif [ "$n" -gt 0 ]; then
    echo "setup:   $n new setting(s). Run: ./wiki.sh setup --new"
  fi
}

cmd_find() {
  local word="$1" d hits found=0
  [ -d "$WIKIS_DIR" ] || die "no wikis at $(tilde "$WIKIS_DIR")"
  for d in "$WIKIS_DIR"/*/; do
    d="${d%/}"
    [ -f "$d/index.md" ] || continue
    # Headings like "# Index" and "## Concepts" aren't entries.
    hits="$(grep -v '^#' "$d/index.md" | grep -i -F -- "$word" || true)"
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
  local root="$1" tv wv f r
  is_wiki "$root" || die "$(tilde "$root") is not a wiki (needs AGENTS.md and index.md)"
  tv="$(version_of "$TEMPLATE/AGENTS.md")"
  wv="$(version_of "$root/AGENTS.md")"
  if [ "${wv:-0}" -gt "${tv:-0}" ]; then
    echo "handbook: v$wv is newer than your template (v$tv), left alone. Update the template: git -C $(tilde "$REPO") pull"
  elif [ "${wv:-0}" -eq "${tv:-0}" ]; then
    echo "handbook: already v${wv:-?}, nothing to replace"
  else
    # Outside git there is no history, so keep the old handbook beside the new one.
    in_git_repo "$root" || cp "$root/AGENTS.md" "$root/AGENTS.md.bak"
    cp "$TEMPLATE/AGENTS.md" "$root/AGENTS.md"
    # The rules files are part of the handbook and move with its version.
    if [ -d "$TEMPLATE/rules" ]; then
      mkdir -p "$root/rules"
      for f in "$TEMPLATE"/rules/*.md; do
        [ -e "$root/rules/${f##*/}" ] || echo "added:    rules/${f##*/}"
        cp "$f" "$root/rules/"
      done
    fi
    echo "handbook: v${wv:-?} -> v$tv"
  fi
  # Older scaffolds pointed CLAUDE.md at the handbook in words. An import is reliable.
  if [ -f "$root/CLAUDE.md" ] && ! grep -q '^@AGENTS\.md' "$root/CLAUDE.md" \
    && [ "$(wc -l < "$root/CLAUDE.md" | tr -d ' ')" -le 1 ]; then
    cp "$TEMPLATE/CLAUDE.md" "$root/CLAUDE.md"
    echo "CLAUDE.md: switched to an import of AGENTS.md"
  fi
  copy_missing "$root" report
  if [ -f "$root/.gitignore" ] && ! grep -qxF '.compile-lock' "$root/.gitignore"; then
    printf '.compile-lock\n' >> "$root/.gitignore"
    echo ".gitignore: added .compile-lock"
  fi
  r="$(wiki_repo "$root")"
  [ -z "$r" ] || install_hook "$r"
  echo "done:     $(tilde "$root")"
}

cmd_upgrade_all() {
  local d found=0 behind from
  [ -d "$WIKIS_DIR" ] || die "no wikis at $(tilde "$WIKIS_DIR")"
  behind="$(behind_versions)"
  from="$(oldest_version "$behind")"
  for d in "$WIKIS_DIR"/*/; do
    d="${d%/}"
    is_wiki "$d" || continue
    found=1
    echo "== ${d##*/}"
    upgrade_one "$d"
  done
  [ "$found" = 1 ] || echo "(no wikis to upgrade)"
  echo "== journal"
  write_journal_config
  apply_journal_commit
  echo "== delegation"
  write_delegation_file
  apply_delegation_ignore
  upgrade_summary "$from" "$behind"
}

cmd_upgrade_one() {
  local root="$1" behind="" from
  is_wiki "$root" || die "$(tilde "$root") is not a wiki (needs AGENTS.md and index.md)"
  from="$(version_of "$root/AGENTS.md")"
  if [ "${from:-0}" -lt "$(version_of "$TEMPLATE/AGENTS.md")" ]; then behind=" ${root##*/}:${from:-0}"; fi
  upgrade_one "$root"
  upgrade_summary "${from:-0}" "$behind" "$root"
}

# Wikis behind the template, as " name:version" pairs. 0 means no version line.
behind_versions() {
  local d v
  for d in $(setup_upgrade_needed); do
    v="$(version_of "$WIKIS_DIR/$d/AGENTS.md")"
    printf ' %s:%s' "$d" "${v:-0}"
  done
}

# The lowest version in a list of name:version pairs.
oldest_version() {
  local p v min=""
  for p in $1; do
    v="${p##*:}"
    if [ -z "$min" ] || [ "$v" -lt "$min" ]; then min="$v"; fi
  done
  printf '%s' "${min:-0}"
}

# Print the CHANGELOG.md entries after version $1, up to the template's.
changelog_since() {
  local to
  to="$(version_of "$TEMPLATE/AGENTS.md")"
  [ -f "$REPO/CHANGELOG.md" ] || return 0
  awk -v f="$1" -v t="${to:-0}" '
    /^## v[0-9]+/ { v = substr($2, 2) + 0; show = (v > f && v <= t); if (show) print "\n" substr($0, 4); next }
    /^## / { show = 0; next }
    show && /^- / { print "  " $0 }
  ' "$REPO/CHANGELOG.md"
}

# upgrade_commit_hint <names> <prefix>: if upgraded wikis have uncommitted changes, say how to commit them.
upgrade_commit_hint() {
  local d paths="" dirty tv
  [ -n "$1" ] && in_git_repo "$WIKIS_DIR" || return 0
  tv="$(version_of "$TEMPLATE/AGENTS.md")"
  for d in $1; do paths="$paths $d"; done
  # Upgrades can add ignore rules for the journal and delegation files.
  if [ -n "$(cd "$WIKIS_DIR" && git status --porcelain -- .gitignore 2>/dev/null)" ]; then paths="$paths .gitignore"; fi
  # shellcheck disable=SC2086
  dirty="$(cd "$WIKIS_DIR" && git status --porcelain -- $paths 2>/dev/null | head -n 1)"
  [ -n "$dirty" ] || return 0
  echo "${2}The upgrade isn't committed. To commit it now:"
  echo "    git -C $(tilde "$WIKIS_DIR") add${paths} && git -C $(tilde "$WIKIS_DIR") commit -m \"wikis: handbook v$tv\" && git -C $(tilde "$WIKIS_DIR") push"
}

# upgrade_summary <from> <upgraded names> [one wiki root]: what changed and what to do next.
upgrade_summary() {
  local from="$1" names="$2" one="${3:-}" tv n d groups=""
  tv="$(version_of "$TEMPLATE/AGENTS.md")"
  echo
  echo "== What changed"
  # names arrives as name:version pairs. Group them by the version they came from.
  if [ -n "$names" ]; then
    groups="$(for d in $names; do echo "${d##*:} ${d%:*}"; done | sort -k1,1rn -k2,2 | awk '
      $1 != last { if (line) print line; line = ($1 == 0 ? "  from an unversioned handbook:" : "  from v" $1 ":"); last = $1 }
      { line = line " " $2 } END { if (line) print line }')"
    names="$(for d in $names; do printf ' %s' "${d%:*}"; done)"
  fi
  if [ -z "$names" ] && [ -n "$one" ]; then
    echo "Nothing. ${one##*/} was already on handbook v$tv."
  elif [ -z "$names" ]; then
    echo "Nothing. Every wiki was already on handbook v$tv."
  else
    n="$(echo "$names" | wc -w | tr -d ' ')"
    printf 'Upgraded %s wiki(s) to handbook v%s.\n%s\n' "$n" "$tv" "$groups"
    if [ "$from" = 0 ]; then echo; echo "What's new (all versions on record):"; else echo; echo "What's new since v$from:"; fi
    changelog_since "$from"
  fi
  echo
  echo "== Next"
  if [ -n "$names" ]; then
    echo "- New sessions load the new handbook. Sessions already running keep the old one until you restart them."
  fi
  upgrade_commit_hint "$names" "- "
  if [ "$(claude_state)" = old ]; then
    echo "- Your Claude Code wiki line is out of date: ./wiki.sh claude"
  fi
  if [ -n "$(setup_pending)" ]; then
    echo "- New settings to look at: ./wiki.sh setup --new"
  fi
  echo "- Settings any time: ./wiki.sh setup --list"
}

cmd_unlock() {
  local root="$1"
  is_wiki "$root" || die "$(tilde "$root") is not a wiki"
  printf 'free\n' > "$root/.compile-lock"
  echo "unlocked: $(tilde "$root")"
}

CLAUDE_FILE="$HOME/.claude/CLAUDE.md"

# claude_state: current, old (an older wiki line), or missing.
claude_state() {
  if [ -f "$CLAUDE_FILE" ] && grep -qxF "$(claude_line)" "$CLAUDE_FILE"; then
    echo current
  elif [ -f "$CLAUDE_FILE" ] && grep -qF "knowledge wikis live in" "$CLAUDE_FILE"; then
    echo old
  else
    echo missing
  fi
}

claude_line() {
  local dir
  dir="$(tilde "$WIKIS_DIR")"
  printf '%s' "My knowledge wikis live in $dir, one folder per project, plus a shared one at $dir/$SHARED. At session start, run \`$(tilde "$REPO")/wiki.sh which <repository-name>\` for the repository you are working in. Its name is the last part of its remote URL, or its folder name. The command prints the wiki that covers it. Read that wiki's AGENTS.md and follow it. If no wiki covers the repository, read $dir/$SHARED/AGENTS.md and follow that, and create the repository's wiki with \`$(tilde "$REPO")/wiki.sh new <repository-name>\` the first time you have something to file there. Outside any repository, use the shared wiki. Hand large, self-contained work to sub-agents on cheaper models as $dir/delegation.md says, following $dir/$SHARED/rules/delegation.md."
}

cmd_claude() {
  local f="$CLAUDE_FILE" line tmp
  line="$(claude_line)"
  mkdir -p "$HOME/.claude"
  if [ -f "$f" ] && grep -qF "knowledge wikis live in" "$f"; then
    if grep -qxF "$line" "$f"; then
      echo "already up to date: ~/.claude/CLAUDE.md"
      return 0
    fi
    # Replace the older wiki line in place. Everything else in the file is kept.
    tmp="$f.tmp"
    grep -vF "knowledge wikis live in" "$f" > "$tmp" || true
    printf '%s\n' "$line" >> "$tmp"
    mv "$tmp" "$f"
    echo "replaced the wiki line in ~/.claude/CLAUDE.md:"
  else
    if [ -s "$f" ]; then printf '\n' >> "$f"; fi
    printf '%s\n' "$line" >> "$f"
    echo "added to ~/.claude/CLAUDE.md:"
  fi
  echo "  $line"
}

# ---- journal ----------------------------------------------------------------
# The journal lives beside the wikis in $WIKIS_DIR/journal. One file per day of
# entries, plus a config file. Dates are local time, shifted by day_starts so
# late-night work counts toward the day it belongs to.

JOURNAL_DIR="$WIKIS_DIR/journal"
JOURNAL_CFG="$JOURNAL_DIR/config"
# Every journal setting, one per line: key|type|level|default|description.
# This list drives the config file, `journal set` validation, and `setup`.
# To add a setting, add a line here and read it with journal_get. `setup --new`
# then asks about it on every machine that hasn't seen it.
#   type:  yesno, number, time, days, since, text, or a choice like a/b/c
#   level: basic settings are asked in every setup; advanced ones sit behind one question
JOURNAL_SETTINGS='enabled|yesno|basic|yes|yes: agents keep the journal and answer "what did I do" from it. no: the feature is off.
commit|yesno|basic|no|yes: journal files are committed and pushed with the wikis. no: they stay on this machine.
entries|yesno|basic|yes|yes: agents add one line for work that leaves no commit (an investigation, a review, a dead end).
format|standup/summary/detailed|basic|standup|Default report shape: standup (yesterday, today, blockers), summary (by project), or detailed.
since|since|basic|lastworkday|Default report range: lastworkday, yesterday, today, week, lastweek, a number of days like 7d, or a date.
code_dirs|text|basic|~/dev|Folders to search for code repositories, separated by colons.
day_starts|time|advanced|04:00|Local time a new day starts. Work before it counts toward the previous day.
workdays|days|advanced|12345|Working days, 1 is Monday and 7 is Sunday. Used to find the last workday.
depth|number|advanced|4|How deep to search code_dirs for repositories.
authors|text|advanced||Extra commit author emails or names, separated by commas. Each repository'"'"'s own user.email always counts.
exclude|text|advanced||Repositories and wikis to leave out, as comma-separated globs, such as personal-*,scratch.
save|yesno|advanced|no|yes: save each generated report in this folder as YYYY-MM-DD-<format>.md.
keep_days|number|advanced|0|Delete day files older than this many days. 0 keeps everything.'
JOURNAL_KEYS="$(printf '%s\n' "$JOURNAL_SETTINGS" | cut -d '|' -f 1 | tr '\n' ' ' | sed 's/ $//')"

# journal_field <key> <n>: field n of a setting. 2 type, 3 level, 4 default, 5 description.
journal_field() {
  printf '%s\n' "$JOURNAL_SETTINGS" | awk -F '|' -v k="$1" -v n="$2" '$1 == k { print $n; exit }'
}

journal_default() { journal_field "$1" 4; }

# journal_check <key> <value>: print why a value is wrong and fail, or succeed quietly.
journal_check() {
  local key="$1" val="$2" type
  type="$(journal_field "$key" 2)"
  [ -n "$type" ] || { echo "unknown journal setting: $key. Settings: $JOURNAL_KEYS"; return 1; }
  case "$val" in *$'\n'*) echo "value must be one line"; return 1 ;; esac
  case "$type" in
    yesno) case "$val" in yes | no) ;; *) echo "$key takes yes or no"; return 1 ;; esac ;;
    number) case "$val" in '' | *[!0-9]*) echo "$key takes a number"; return 1 ;; esac ;;
    time) case "$val" in [0-2][0-9]:[0-5][0-9]) ;; *) echo "$key takes a time like 04:00"; return 1 ;; esac ;;
    days) case "$val" in '' | *[!1-7]*) echo "$key takes digits 1 to 7, such as 12345"; return 1 ;; esac ;;
    since) since_ok "$val" || { echo "$key takes lastworkday, yesterday, today, week, lastweek, a number of days like 7d, or a date"; return 1; } ;;
    text) ;;
    */*)
      case "$val" in '' | */*) echo "$key takes one of: ${type//\// }"; return 1 ;; esac
      case "/$type/" in
        */"$val"/*) ;;
        *) echo "$key takes one of: ${type//\// }"; return 1 ;;
      esac
      ;;
  esac
  return 0
}

write_journal_config() {
  local key def desc
  mkdir -p "$JOURNAL_DIR"
  [ -f "$JOURNAL_CFG" ] && return 0
  {
    echo "# Work journal settings. Change them with: ./wiki.sh journal set <key> <value>"
    echo "# or walk through them with: ./wiki.sh setup journal"
    echo "# Agents read this file. See rules/journal.md in any wiki."
    printf '%s\n' "$JOURNAL_SETTINGS" | while IFS='|' read -r key _ _ def desc; do
      printf '\n# %s\n%s=%s\n' "$desc" "$key" "$def"
    done
  } > "$JOURNAL_CFG"
  echo "created: $(tilde "$JOURNAL_CFG") (journal on, not committed)"
}

journal_get() {
  local key="$1" val=""
  if [ -f "$JOURNAL_CFG" ]; then
    val="$(sed -n "s/^$key=//p" "$JOURNAL_CFG" | tail -n 1)"
    # A key present but empty is a real value, for authors and exclude.
    if grep -q "^$key=" "$JOURNAL_CFG"; then
      printf '%s' "$val"
      return 0
    fi
  fi
  journal_default "$key"
}

# Add a line to a file unless it is already there. Copes with a missing final newline.
ensure_line() {
  local file="$1" line="$2"
  [ -f "$file" ] && grep -qxF -- "$line" "$file" && return 0
  if [ -s "$file" ] && [ -n "$(tail -c 1 "$file")" ]; then printf '\n' >> "$file"; fi
  printf '%s\n' "$line" >> "$file"
}

remove_line() {
  local file="$1" line="$2" tmp
  [ -f "$file" ] || return 0
  grep -qxF -- "$line" "$file" || return 0
  tmp="$file.tmp"
  grep -vxF -- "$line" "$file" > "$tmp" || true
  mv "$tmp" "$file"
}

# Keep the collection's .gitignore in step with the commit setting.
apply_journal_commit() {
  local gi="$WIKIS_DIR/.gitignore"
  in_git_repo "$WIKIS_DIR" || return 0
  if [ "$(journal_get commit)" = yes ]; then
    remove_line "$gi" "journal/"
    if git -C "$WIKIS_DIR" check-ignore -q journal/config 2>/dev/null; then
      echo "note:    another ignore rule still hides journal/. Check $(tilde "$gi")."
    fi
  else
    ensure_line "$gi" "journal/"
    if [ -n "$(git -C "$WIKIS_DIR" ls-files journal 2>/dev/null)" ]; then
      echo "note:    journal files are already tracked. To stop tracking them: git -C $(tilde "$WIKIS_DIR") rm -r --cached journal"
    fi
  fi
}

journal_set() {
  local key="$1" val="$2" tmp err
  err="$(journal_check "$key" "$val")" || die "$err"
  write_journal_config >/dev/null
  tmp="$JOURNAL_CFG.tmp"
  awk -v k="$key" -v v="$val" 'BEGIN{done=0} $0 ~ "^"k"=" {print k"="v; done=1; next} {print} END{if(!done) print k"="v}' "$JOURNAL_CFG" > "$tmp"
  mv "$tmp" "$JOURNAL_CFG"
  echo "journal: $key=$val"
  [ "$key" = commit ] && apply_journal_commit
  return 0
}

# ---- dates (GNU date on Linux, BSD date on macOS) ----
is_gnu_date() { date --version >/dev/null 2>&1; }

date_add() { # date_add YYYY-MM-DD N  -> YYYY-MM-DD
  if is_gnu_date; then
    date -d "$1 $2 day" +%Y-%m-%d
  elif [ "$2" -ge 0 ]; then
    date -j -v+"$2"d -f %Y-%m-%d "$1" +%Y-%m-%d
  else
    date -j -v"$2"d -f %Y-%m-%d "$1" +%Y-%m-%d
  fi
}

day_of_week() { # 1 is Monday
  if is_gnu_date; then date -d "$1" +%u; else date -j -f %Y-%m-%d "$1" +%u; fi
}

to_epoch() { # "YYYY-MM-DD HH:MM" in local time
  if is_gnu_date; then date -d "$1" +%s; else date -j -f "%Y-%m-%d %H:%M" "$1" +%s; fi
}

epoch_to_utc_stamp() {
  if is_gnu_date; then date -u -d "@$1" +%Y%m%d%H%M%S; else date -u -r "$1" +%Y%m%d%H%M%S; fi
}

# The journal day it is now: today's local date, or yesterday's before day_starts.
journal_today() {
  local d now ds
  d="$(date +%Y-%m-%d)"
  now="$(date +%H:%M)"
  ds="$(journal_get day_starts)"
  if [[ "$now" < "$ds" ]]; then d="$(date_add "$d" -1)"; fi
  printf '%s' "$d"
}

last_workday() {
  local d wd
  d="$(date_add "$1" -1)"
  wd="$(journal_get workdays)"
  for _ in 1 2 3 4 5 6 7; do
    case "$wd" in *"$(day_of_week "$d")"*) printf '%s' "$d"; return 0 ;; esac
    d="$(date_add "$d" -1)"
  done
  date_add "$1" -1
}

# Monday of the week that holds a date.
week_start() {
  local d="$1"
  date_add "$d" "-$(( $(day_of_week "$d") - 1 ))"
}

since_ok() {
  case "$1" in
    lastworkday | yesterday | today | week | lastweek) return 0 ;;
    [0-9]d | [0-9][0-9]d | [0-9][0-9][0-9]d) return 0 ;;
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) return 0 ;;
  esac
  return 1
}

since_to_date() {
  local today="$1" s="$2"
  case "$s" in
    lastworkday) last_workday "$today" ;;
    yesterday) date_add "$today" -1 ;;
    today) printf '%s' "$today" ;;
    week) week_start "$today" ;;
    lastweek) week_start "$(date_add "$(week_start "$today")" -1)" ;;
    *d) date_add "$today" "-${s%d}" ;;
    *) printf '%s' "$s" ;;
  esac
}

# ---- journal command ----
journal_file_for() { printf '%s/%s.md' "$JOURNAL_DIR" "$1"; }

journal_note() {
  local project="$1" text="$2" day="${3:-}" at="${4:-}" f
  if [ "$(journal_get enabled)" != yes ] || [ "$(journal_get entries)" != yes ]; then
    echo "journal entries are off, nothing written"
    return 0
  fi
  text="$(printf '%s' "$text" | tr '\n\r' '  ')"
  [ -n "$text" ] || die "journal note needs some text"
  write_journal_config >/dev/null
  [ -n "$day" ] || day="$(journal_today)"
  [ -n "$at" ] || at="$(date +%H:%M)"
  f="$(journal_file_for "$day")"
  [ -f "$f" ] || printf '# Journal %s\n\n' "$day" > "$f"
  # One short line per append, so parallel sessions don't interleave.
  printf -- '- %s [%s] %s\n' "$at" "$project" "$text" >> "$f"
  echo "journal: $(tilde "$f")"
  journal_prune quiet
}

journal_prune() {
  local keep f b cutoff n=0
  keep="$(journal_get keep_days)"
  [ "${keep:-0}" -gt 0 ] || { [ "${1:-}" = quiet ] || echo "keep_days is 0, nothing pruned"; return 0; }
  cutoff="$(date_add "$(journal_today)" "-$keep")"
  for f in "$JOURNAL_DIR"/20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]*.md; do
    [ -f "$f" ] || continue
    b="${f##*/}"
    if [[ "${b:0:10}" < "$cutoff" ]]; then rm -f "$f"; n=$((n + 1)); fi
  done
  [ "${1:-}" = quiet ] || echo "pruned $n file(s) older than $cutoff"
}

journal_show() {
  local k today f
  if [ ! -f "$JOURNAL_CFG" ]; then
    echo "no journal config yet. It is on by default: ./wiki.sh journal on creates it."
    return 0
  fi
  echo "journal: $(tilde "$JOURNAL_DIR")"
  for k in $JOURNAL_KEYS; do printf '  %-11s %s\n' "$k" "$(journal_get "$k")"; done
  today="$(journal_today)"
  f="$(journal_file_for "$today")"
  if [ -f "$f" ]; then
    echo "today ($today): $(grep -c '^- ' "$f") entr(ies)"
  else
    echo "today ($today): no entries"
  fi
}

# journal note [--day YYYY-MM-DD] [--at HH:MM] <project> <text>
cmd_journal_note() {
  local day="" at=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --day) day="${2:-}"; shift 2 ;;
      --at) at="${2:-}"; shift 2 ;;
      *) break ;;
    esac
  done
  case "$day" in '' | [0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]) ;; *) die "--day takes a date like 2026-10-21" ;; esac
  case "$at" in '' | [0-2][0-9]:[0-5][0-9]) ;; *) die "--at takes a time like 14:05" ;; esac
  if [ -n "$day" ] && [[ "$day" > "$(journal_today)" ]]; then die "--day can't be in the future"; fi
  [ $# -ge 2 ] || die "usage: ./wiki.sh journal note [--day DATE] [--at HH:MM] <project> <text>"
  journal_note "$1" "$(shift; printf '%s ' "$@" | sed 's/ $//')" "$day" "$at"
}

# journal backfill: digest past Claude Code sessions into journal/backfill.md.
# An agent then writes entries from it. See rules/journal.md.
journal_backfill() {
  local since="14d" until="" from="$HOME/.claude/projects" today start out
  while [ $# -gt 0 ]; do
    case "$1" in
      --since) since="${2:-}"; shift 2 ;;
      --until) until="${2:-}"; shift 2 ;;
      --from) from="${2:-}"; shift 2 ;;
      *) die "backfill options: --since lastworkday|yesterday|week|lastweek|14d|DATE, --until DATE, --from DIR" ;;
    esac
  done
  since_ok "$since" || die "--since takes lastworkday, yesterday, today, week, lastweek, a number of days like 14d, or a date"
  [ -d "$from" ] || die "no Claude Code sessions at $(tilde "$from"). Use --from DIR."
  command -v python3 >/dev/null 2>&1 || die "backfill needs python3 to read session files"
  write_journal_config >/dev/null
  today="$(journal_today)"
  start="$(since_to_date "$today" "$since")"
  until="${until:-$today}"
  out="$JOURNAL_DIR/backfill.md"
  python3 - "$from" "$start" "$until" "$(journal_get day_starts)" "$WIKIS_DIR" "$(journal_get exclude)" "$out" <<'PY'
# Digest Claude Code transcripts into one markdown file: per local day, per
# project, the user's prompts, files changed, whether it committed, and how it ended.
import json, os, re, subprocess, sys, fnmatch
from datetime import datetime, timedelta, date
from pathlib import Path

sess_dir, start, end, day_starts, wikis, exclude, out = sys.argv[1:8]
start = date.fromisoformat(start); end = date.fromisoformat(end)
ds_h, ds_m = (int(x) for x in day_starts.split(":"))
excl = [g for g in exclude.split(",") if g]

# repo -> wiki, from each wiki's repos.md
cover = {}
for rp in Path(wikis).glob("*/repos.md"):
    for line in rp.read_text(errors="replace").splitlines():
        if line.startswith("- "):
            cover[line[2:].strip()] = rp.parent.name

# Names that count as projects: every wiki, and every repository a wiki covers.
known = set(cover) | {d.name for d in Path(wikis).iterdir() if (d / "AGENTS.md").is_file() and (d / "index.md").is_file()}

_proj = {}
def project(cwd):
    if not cwd: return "unknown"
    if cwd in _proj: return _proj[cwd]
    name = os.path.basename(cwd.rstrip("/")) or cwd
    def git(*a):
        try:
            return subprocess.run(["git", "-C", cwd, *a], capture_output=True, text=True, timeout=5).stdout.strip()
        except Exception:
            return ""
    if os.path.isdir(cwd):
        url = git("config", "--get", "remote.origin.url")
        top = git("rev-parse", "--show-toplevel")
        if url: name = re.sub(r"\.git$", "", url.rstrip("/")).split("/")[-1].split(":")[-1]
        elif top: name = os.path.basename(top)
    if os.path.realpath(cwd) == os.path.realpath(wikis): name = "wikis"
    # A scratch folder inside a project, such as politiboop/sweeps/b41, belongs to that project.
    if name not in known:
        for part in reversed(Path(cwd).parts[:-1]):
            if part in known:
                name = part
                break
    _proj[cwd] = cover.get(name, name)
    return _proj[cwd]

# Prompts written by tools, not the user. Side-session briefs are kept, marked.
MACHINE = ("<task-notification", "<side-sessions-event", "<cross-session-message", "Caveat:",
           "[Request interrupted", "This session is being continued")
BRIEF = ("Background (from the session that started this one)", "Task (from the session that started this one)")

def local(ts):
    t = datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone()
    d = (t - timedelta(hours=ds_h, minutes=ds_m)).date()
    return d, t.strftime("%H:%M")

NOISE = re.compile(r"<(system-reminder|command-[a-z]+|local-command-[a-z]+)>.*?</\1>", re.S)
def clean(s, n):
    s = NOISE.sub("", s).strip()
    s = re.sub(r"\s+", " ", s)
    return s if len(s) <= n else s[: n - 3] + "..."

def texts(content):
    if isinstance(content, str): return [content]
    return [c.get("text", "") for c in content or [] if isinstance(c, dict) and c.get("type") == "text"]

# (day, project) -> record
work = {}
cutoff = datetime.combine(start - timedelta(days=1), datetime.min.time()).timestamp()
files = [p for p in Path(sess_dir).rglob("*.jsonl") if p.stat().st_mtime >= cutoff]
for f in files:
    recs = []
    for line in open(f, errors="replace"):
        try: r = json.loads(line)
        except ValueError: continue
        if r.get("type") not in ("user", "assistant") or r.get("isSidechain") or r.get("isMeta"): continue
        if r.get("timestamp"): recs.append(r)
    # A session started from a stray folder (/tmp, a memory folder) belongs to the
    # known project most of its records ran in, if there is one.
    seen = {}
    for r in recs:
        p = project(r.get("cwd"))
        if p in known: seen[p] = seen.get(p, 0) + 1
    main = max(seen, key=seen.get) if seen else None
    for r in recs:
        ts = r["timestamp"]
        d, hm = local(ts)
        if d < start or d > end: continue
        p = project(r.get("cwd"))
        if p not in known and main: p = main
        if any(fnmatch.fnmatch(p, g) for g in excl): continue
        w = work.setdefault((d, p), {"first": hm, "last": hm, "sessions": set(), "prompts": [], "files": [], "commit": False, "end": "", "branch": ""})
        w["first"] = min(w["first"], hm); w["last"] = max(w["last"], hm)
        w["sessions"].add(r.get("sessionId", f.stem))
        if r.get("gitBranch") and r["gitBranch"] != "HEAD": w["branch"] = r["gitBranch"]
        msg = r.get("message") or {}
        if r["type"] == "user":
            for t in texts(msg.get("content")):
                t = t.strip()
                if not t or t.startswith(MACHINE): continue
                if t.startswith(BRIEF):
                    t = "(side session brief) " + clean(t.split(":", 1)[-1], 160)
                else:
                    t = clean(t, 240)
                if t: w["prompts"].append((hm, t))
        else:
            for c in msg.get("content") or []:
                if not isinstance(c, dict): continue
                if c.get("type") == "text":
                    t = clean(c.get("text", ""), 400)
                    if t: w["end"] = t
                elif c.get("type") == "tool_use":
                    inp = c.get("input") or {}
                    fp = inp.get("file_path") or inp.get("notebook_path")
                    if fp and c.get("name") in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
                        b = os.path.basename(fp)
                        if b not in w["files"]: w["files"].append(b)
                    if "git commit" in str(inp.get("command", "")): w["commit"] = True

with open(out, "w") as o:
    o.write(f"# Session digest {start} to {end}\n\n")
    o.write("Written by `wiki.sh journal backfill` from Claude Code transcripts. An agent turns this into journal entries, then this file can go.\n")
    o.write("Times are local. Each block is one project on one day: the user's prompts, files changed, and the last thing the agent said.\n")
    day = None
    for (d, p) in sorted(work):
        w = work[(d, p)]
        if not w["prompts"]: continue
        if d != day:
            o.write(f"\n## {d}\n"); day = d
        meta = [f"{w['first']}-{w['last']}", f"{len(w['sessions'])} session(s)"]
        if w["branch"]: meta.append(f"branch {w['branch']}")
        if w["commit"]: meta.append("ran git commit")
        o.write(f"\n### [{p}] {', '.join(meta)}\n")
        ps = sorted(w["prompts"], key=lambda x: x[0])
        if len(ps) > 14: ps = ps[:9] + [("", f"... {len(ps) - 14} more prompts ...")] + ps[-5:]
        for hm, t in ps: o.write(f"- {hm} {t}\n" if hm else f"- {t}\n")
        if w["files"]: o.write(f"- files changed: {', '.join(w['files'][:12])}{' ...' if len(w['files']) > 12 else ''}\n")
        if w["end"]: o.write(f"- last reply: {w['end']}\n")
n = sum(1 for k in work if work[k]["prompts"])
print(f"{n} project-day(s) from {len(files)} transcript file(s)")
PY
  echo "digest:  $(tilde "$out") ($start to $until)"
  echo "Next: tell an agent \"backfill my journal from the digest\". It writes the entries, then deletes the digest."
}

cmd_journal() {
  local sub="${1:-show}"
  [ $# -gt 0 ] && shift
  case "$sub" in
    show) journal_show ;;
    on) write_journal_config >/dev/null; journal_set enabled yes; apply_journal_commit ;;
    off) write_journal_config >/dev/null; journal_set enabled no ;;
    set) [ $# -ge 1 ] || die "usage: ./wiki.sh journal set <key> <value>"; journal_set "$1" "${2:-}" ;;
    note) cmd_journal_note "$@" ;;
    backfill) journal_backfill "$@" ;;
    path) journal_file_for "$(journal_today)"; printf '\n' ;;
    prune) journal_prune ;;
    *) die "journal commands: show, on, off, set <key> <value>, note [--day DATE] [--at HH:MM] <project> <text>, backfill [--since X] [--until DATE], path, prune" ;;
  esac
}

# ---- standup ----
repo_name() {
  local url
  url="$(git -C "$1" config --get remote.origin.url 2>/dev/null || true)"
  if [ -n "$url" ]; then url="${url%/}"; url="${url##*/}"; url="${url##*:}"; printf '%s' "${url%.git}"; else printf '%s' "${1##*/}"; fi
}

excluded() {
  local name="$1" pats p
  pats="$(journal_get exclude)"
  pats="${pats:+$pats,}${STANDUP_EXCLUDE:-}"
  pats="${pats%,}"
  # --only is a glob on purpose.
  # shellcheck disable=SC2254
  [ -n "${STANDUP_ONLY:-}" ] && { case "$name" in $STANDUP_ONLY) ;; *) return 0 ;; esac; }
  [ -n "$pats" ] || return 1
  local IFS=,
  for p in $pats; do
    p="$(printf '%s' "$p" | sed 's/^ *//; s/ *$//')"
    [ -n "$p" ] || continue
    # shellcheck disable=SC2254
    case "$name" in $p) return 0 ;; esac
  done
  return 1
}

# shellcheck disable=SC2088
find_repos() {
  local dirs depth d
  dirs="$(journal_get code_dirs)"
  depth="$(journal_get depth)"
  local IFS=:
  for d in $dirs; do
    case "$d" in "~/"*) d="$HOME/${d:2}" ;; "~") d="$HOME" ;; esac
    [ -d "$d" ] || continue
    find "$d" -maxdepth "$depth" -name .git -prune -print 2>/dev/null
  done | sed 's#/\.git$##' | sort -u
}

cmd_standup() {
  local since="" until="" day="" fmt="" save="" only="" arg
  while [ $# -gt 0 ]; do
    case "$1" in
      --since) since="${2:-}"; shift ;;
      --until) until="${2:-}"; shift ;;
      --day) day="${2:-}"; shift ;;
      --format) fmt="${2:-}"; shift ;;
      --only) only="${2:-}"; shift ;;
      --exclude) STANDUP_EXCLUDE="${STANDUP_EXCLUDE:+$STANDUP_EXCLUDE,}${2:-}"; shift ;;
      --save) save=yes ;;
      *) die "standup options: --since X, --until DATE, --day DATE, --format standup|summary|detailed, --only GLOB, --exclude GLOB, --save" ;;
    esac
    shift
  done
  arg="${since:-$(journal_get since)}"
  since_ok "$arg" || die "--since takes lastworkday, yesterday, today, week, lastweek, a number of days like 7d, or a date"
  [ -z "$fmt" ] || case "$fmt" in standup | summary | detailed) ;; *) die "--format takes standup, summary, or detailed" ;; esac
  STANDUP_ONLY="$only"

  local today ds start_date end_date start_local end_local s_utc e_utc end_label
  today="$(journal_today)"
  ds="$(journal_get day_starts)"
  if [ -n "$day" ]; then
    since_ok "$day" || die "--day takes a date like 2026-10-21"
    start_date="$day"; end_date="$day"
  else
    start_date="$(since_to_date "$today" "$arg")"
    # Last week means Monday through Sunday, not through now.
    if [ "$arg" = lastweek ] && [ -z "$until" ]; then until="$(date_add "$(week_start "$today")" -1)"; fi
    end_date="${until:-$today}"
  fi
  start_local="$start_date $ds"
  if [ -z "$day" ] && [ -z "$until" ]; then
    end_local="$(date '+%Y-%m-%d %H:%M')"; end_label="now"
  else
    end_local="$(date_add "$end_date" 1) $ds"; end_label="$end_local"
  fi
  s_utc="$(epoch_to_utc_stamp "$(to_epoch "$start_local")")"
  e_utc="$(epoch_to_utc_stamp "$(to_epoch "$end_local")")"

  local out r name authors a lines n_repos=0 n_commits=0 skipped=0 me
  out="$(mktemp)"
  {
    echo "# Activity: $start_local to $end_label (local time)"
    echo
    echo "Report format: ${fmt:-$(journal_get format)}. Agents: write it up as rules/journal.md says."
    echo
    echo "## Commits"
  } > "$out"
  authors="$(journal_get authors)"
  local since_flag=--since gv
  gv="$(git version | sed -n 's/^git version \([0-9]*\)\.\([0-9]*\).*/\1 \2/p')"
  if [ -n "$gv" ] && { [ "${gv% *}" -gt 2 ] || { [ "${gv% *}" -eq 2 ] && [ "${gv#* }" -ge 37 ]; }; }; then
    since_flag=--since-as-filter
  fi
  local inprog
  inprog="$(mktemp)"
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    case "$r/" in "$WIKIS_DIR"/*) continue ;; esac
    name="$(repo_name "$r")"
    excluded "$name" && continue
    me="$(git -C "$r" config user.email 2>/dev/null || true)"
    set -- 
    [ -n "$me" ] && set -- "--author=$me"
    if [ -n "$authors" ]; then
      local IFS_SAVE="$IFS"; IFS=,
      for a in $authors; do a="$(printf '%s' "$a" | sed 's/^ *//; s/ *$//')"; [ -n "$a" ] && set -- "$@" "--author=$a"; done
      IFS="$IFS_SAVE"
    fi
    if [ $# -eq 0 ]; then skipped=$((skipped + 1)); continue; fi
    # --since stops walking history at the first older commit, which hides newer work
    # under an old branch tip. --since-as-filter (git 2.37) checks every commit.
    lines="$(git -C "$r" log --all --no-merges "$@" "$since_flag=$start_local" --until="$end_local" \
      --date=format-local:'%Y-%m-%d %H:%M' --format='- %cd %h %s' 2>/dev/null | sort -u || true)"
    if [ -n "$lines" ]; then
      n_repos=$((n_repos + 1)); n_commits=$((n_commits + $(printf '%s\n' "$lines" | wc -l)))
      { echo; echo "### $name"; printf '%s\n' "$lines"; } >> "$out"
    fi
    # Work in progress: uncommitted files, unpushed commits, a non-default branch.
    local dirty ahead br
    dirty="$(git -C "$r" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
    ahead="$(git -C "$r" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)"
    br="$(git -C "$r" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
    if [ "$dirty" -gt 0 ] || [ "$ahead" -gt 0 ] || { [ -n "$lines" ] && [ "$br" != main ] && [ "$br" != master ]; }; then
      echo "- $name: branch $br, $dirty uncommitted file(s), $ahead unpushed commit(s)" >> "$inprog"
    fi
  done < <(find_repos)
  [ "$n_commits" -gt 0 ] || { echo; echo "None found."; } >> "$out"
  [ "$skipped" -eq 0 ] || { echo; echo "($skipped repo(s) skipped: no user.email set and no authors configured.)"; } >> "$out"

  # Journal entries for the days in range.
  { echo; echo "## Journal entries"; } >> "$out"
  local d f got=0
  d="$start_date"
  while [[ ! "$d" > "$end_date" ]]; do
    f="$(journal_file_for "$d")"
    if [ -f "$f" ]; then
      while IFS= read -r line; do
        local proj="${line#*[}"; proj="${proj%%]*}"
        excluded "$proj" && continue
        echo "- $d ${line#- }" >> "$out"; got=1
      done < <(grep '^- ' "$f" || true)
    fi
    d="$(date_add "$d" 1)"
  done
  [ "$got" = 1 ] || { echo; echo "None."; } >> "$out"

  # Wiki notes captured in range, by their UTC filename stamps, and wiki log entries.
  { echo; echo "## Wiki notes captured"; } >> "$out"
  local w b stamp title any=0 s_day e_day
  s_day="${s_utc:0:4}-${s_utc:4:2}-${s_utc:6:2}"; e_day="${e_utc:0:4}-${e_utc:4:2}-${e_utc:6:2}"
  for w in "$WIKIS_DIR"/*/; do
    w="${w%/}"; is_wiki "$w" || continue
    excluded "${w##*/}" && continue
    lines=""
    for f in "$w"/raw/20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]*; do
      [ -f "$f" ] || continue
      b="${f##*/}"
      stamp="$(printf '%s' "$b" | sed -n 's/^\([0-9]\{4\}\)-\([0-9]\{2\}\)-\([0-9]\{2\}\)-\([0-9]\{6\}\).*/\1\2\3\4/p')"
      [ -n "$stamp" ] || stamp="$(printf '%s' "${b:0:10}" | tr -d '-')000000"
      if [[ ! "$stamp" < "$s_utc" ]] && [[ "$stamp" < "$e_utc" ]]; then
        title="$(grep -m 1 '^# ' "$f" 2>/dev/null | sed 's/^# //' || true)"
        lines="$lines- ${b%.*}: ${title:-(no title)}"$'\n'
      fi
    done
    if [ -n "$lines" ]; then any=1; { echo; echo "### ${w##*/}"; printf '%s' "$lines"; } >> "$out"; fi
  done
  [ "$any" = 1 ] || { echo; echo "None."; } >> "$out"

  { echo; echo "## Wiki changes"; } >> "$out"
  any=0
  for w in "$WIKIS_DIR"/*/; do
    w="${w%/}"; is_wiki "$w" || continue
    excluded "${w##*/}" && continue
    lines="$(awk -v s="$s_day" -v e="$e_day" '/^## [0-9]{4}-[0-9]{2}-[0-9]{2} /{ if ($2>=s && $2<=e) { $1=""; sub(/^ /,""); print "- " $0 } }' "$w/log.md" 2>/dev/null || true)"
    if [ -n "$lines" ]; then any=1; printf '%s\n' "$lines" | sed "s/^- /- ${w##*/}: /" >> "$out"; fi
  done
  [ "$any" = 1 ] || { echo; echo "None."; } >> "$out"

  { echo; echo "## In progress"; } >> "$out"
  if [ -s "$inprog" ]; then cat "$inprog" >> "$out"; else { echo; echo "None."; } >> "$out"; fi
  rm -f "$inprog"

  { echo; echo "## Open checks and conflicts"; } >> "$out"
  any=0
  for w in "$WIKIS_DIR"/*/; do
    w="${w%/}"; is_wiki "$w" || continue
    excluded "${w##*/}" && continue
    [ -d "$w/wiki" ] || continue
    lines="$(grep -rhE '^> \*\*(Check|Conflict):\*\*' "$w/wiki" 2>/dev/null | head -n 5 | sed "s/^> /- ${w##*/}: /" || true)"
    if [ -n "$lines" ]; then any=1; printf '%s\n' "$lines" >> "$out"; fi
  done
  [ "$any" = 1 ] || { echo; echo "None."; } >> "$out"

  { echo; echo "Totals: $n_commits commit(s) in $n_repos repo(s)."; } >> "$out"
  cat "$out"
  if [ "$save" = yes ] || [ "$(journal_get save)" = yes ]; then
    mkdir -p "$JOURNAL_DIR"
    f="$JOURNAL_DIR/$today-activity.md"
    cp "$out" "$f"
    echo
    echo "saved: $(tilde "$f")"
  fi
  rm -f "$out"
}

# ---- patterns ---------------------------------------------------------------
# Each wiki's patterns.md tallies recurring feedback. See template/rules/patterns.md.

# patterns_ledger <wiki root>: one line per entry: ready|name|kind|status|sightings|repos
patterns_ledger() {
  [ -f "$1/patterns.md" ] || return 0
  awk '
    function flush() {
      if (name == "") return
      nrep = 0; for (r in repos) nrep++
      ready = (status ~ /^watching/ && (n >= 3 || (n >= 2 && (kind == "review" || nrep >= 2)))) ? "ready" : ""
      print ready "|" name "|" kind "|" status "|" n "|" nrep
      name = ""; kind = ""; status = ""; n = 0; delete repos
    }
    /^## / { flush(); name = substr($0, 4); next }
    /^- kind:/ { kind = $3 }
    /^- status:/ { sub(/^- status: */, ""); status = $0 }
    /^- seen:/ { c = 1; if ($NF ~ /^x[0-9]+$/) c = substr($NF, 2) + 0; n += c; if ($4 != "-") repos[$4] = 1 }
    END { flush() }
  ' "$1/patterns.md"
}

# Feedback lines in raw notes that haven't been compiled yet.
patterns_pending() {
  local d="$1" f b
  for f in "$d"/raw/*; do
    [ -f "$f" ] || continue
    b="${f##*/}"
    [ -e "$d/wiki/sources/${b%.*}.md" ] && continue
    grep -h '^Feedback:' "$f" 2>/dev/null | sed "s#^#$b: #" || true
  done
}

cmd_patterns() {
  local d line ready name kind status n nrep pend found=0 total=0
  [ -d "$WIKIS_DIR" ] || die "no wikis at $(tilde "$WIKIS_DIR")"
  for d in "$WIKIS_DIR"/*/; do
    d="${d%/}"
    is_wiki "$d" || continue
    line="$(patterns_ledger "$d")"
    pend="$(patterns_pending "$d")"
    [ -n "$line$pend" ] || continue
    found=1
    echo "== ${d##*/}"
    if [ -n "$line" ]; then
      while IFS='|' read -r ready name kind status n nrep; do
        if [ "$ready" = ready ]; then total=$((total + 1)); printf '  READY  '; else printf '         '; fi
        printf '%s (%s, seen %s, %s repo(s)): %s\n' "$name" "${kind:-?}" "$n" "$nrep" "${status:-watching}"
      done <<EOF2
$line
EOF2
    fi
    if [ -n "$pend" ]; then
      echo "  not yet compiled:"
      printf '%s\n' "$pend" | sed 's/^/    /'
    fi
  done
  [ "$found" = 1 ] || { echo "No patterns yet. Agents add Feedback lines to their notes as corrections come in."; return 0; }
  echo
  echo "$total ready to propose. An agent proposes each at a stopping point, per rules/patterns.md."
}

# ---- delegation -------------------------------------------------------------
# delegation.md in the collection holds the user's handoff preferences: a mode
# line, a table of work to model tiers, and an Auto list. Agents read it and
# follow rules/delegation.md. delegation-log.csv records each handoff. Git
# ignores both: they belong to one person on one machine.
DELEG_FILE="$WIKIS_DIR/delegation.md"
DELEG_LOG="$WIKIS_DIR/delegation-log.csv"

write_delegation_file() {
  [ -d "$WIKIS_DIR" ] || return 0
  [ -f "$DELEG_FILE" ] && return 0
  cat > "$DELEG_FILE" <<'EOF2'
# Delegation

How sessions hand work to sub-agents on cheaper models. This file is yours alone: git ignores it, so it never reaches coworkers or your other machines. Edit it freely. Agents read it and follow `rules/delegation.md` in any wiki. Change the mode with `./wiki.sh setup delegation`.

mode: ask

Modes: `off` never hands off unless you ask. `ask` suggests each handoff and waits for a yes. `auto` hands off and says so after.

## Who does what

| Work | Model | Effort |
|---|---|---|
| Searching or sweeping many files, gathering facts | sonnet | low |
| Running tests or builds, summarizing failures | sonnet | low |
| Link checks, data extraction, format conversions | haiku | low |
| Boilerplate that copies an existing pattern | sonnet | medium |
| First drafts of docs from code | sonnet | medium |
| Design, debugging, code review, security, anything that needs this conversation | stay | - |

Model names are tiers. Use the ones your tool offers.

## Auto

Kinds of work you have approved for handoff without asking, even in `ask` mode. One per line, starting with `- `.
EOF2
  echo "created: $(tilde "$DELEG_FILE") (mode ask)"
}

deleg_mode() {
  local m=""
  [ -f "$DELEG_FILE" ] && m="$(sed -n 's/^mode: *\([a-z]*\).*/\1/p' "$DELEG_FILE" | head -n 1)"
  printf '%s' "${m:-ask}"
}

deleg_set_mode() {
  local tmp
  case "$1" in off | ask | auto) ;; *) die "delegation mode takes off, ask, or auto" ;; esac
  write_delegation_file >/dev/null
  tmp="$DELEG_FILE.tmp"
  if grep -q '^mode:' "$DELEG_FILE"; then
    sed "s/^mode:.*/mode: $1/" "$DELEG_FILE" > "$tmp" && mv "$tmp" "$DELEG_FILE"
  else
    printf '\nmode: %s\n' "$1" >> "$DELEG_FILE"
  fi
  echo "delegation: mode $1"
}

# The preferences and the handoff log are one person's, so they stay on this
# machine. In a shared collection, coworkers would otherwise overwrite each other's mode.
apply_delegation_ignore() {
  in_git_repo "$WIKIS_DIR" || return 0
  ensure_line "$WIKIS_DIR/.gitignore" "delegation.md"
  ensure_line "$WIKIS_DIR/.gitignore" "delegation-log.csv"
  if [ -n "$(git -C "$WIKIS_DIR" ls-files delegation.md delegation-log.csv 2>/dev/null)" ]; then
    echo "note:    delegation files are tracked from before. To keep them on this machine only: git -C $(tilde "$WIKIS_DIR") rm --cached delegation.md delegation-log.csv"
  fi
}

cmd_delegation() {
  case "${1:-show}" in
    off | ask | auto) deleg_set_mode "$1"; return 0 ;;
    show) ;;
    *) die "delegation commands: show, off, ask, auto" ;;
  esac
  if [ ! -f "$DELEG_FILE" ]; then
    echo "no $(tilde "$DELEG_FILE") yet. Mode is ask by default. ./wiki.sh setup delegation creates it."
    return 0
  fi
  echo "delegation: mode $(deleg_mode)   ($(tilde "$DELEG_FILE"))"
  sed -n '/^## Auto/,$p' "$DELEG_FILE" | grep '^- ' | sed 's/^- /  auto: /' || true
  if [ ! -s "$DELEG_LOG" ]; then
    echo "no handoffs logged yet"
    return 0
  fi
  echo
  printf '%-44s %5s %5s %6s %7s\n' "KIND (MODEL)" "RUNS" "OK" "FIXED" "REDONE"
  awk -F, 'NR > 1 && NF >= 6 {
      kind = $3; for (i = 4; i <= NF - 3; i++) kind = kind "," $i
      k = kind " (" $(NF - 2) ")"; n[k]++; r[k "|" $NF]++
    }
    END { for (k in n) printf "%-44s %5d %5d %6d %7d\n", substr(k, 1, 44), n[k], r[k "|ok"], r[k "|fixed"], r[k "|redone"] }' "$DELEG_LOG" | sort
}

# ---- setup ------------------------------------------------------------------
# A walkthrough of every choice, for a new machine or an existing one.
# Two kinds of step:
#   checks    (collection, claude, upgrade) run every time and ask only when
#             something is missing or out of date.
#   questions (git, git.identity, journal.<key>) are recorded once answered,
#             so `setup --new` asks only the ones this machine hasn't seen.
# The record is per machine, outside the collection, so it never syncs.
SETUP_STATE="${XDG_CONFIG_HOME:-$HOME/.config}/llm-wiki/setup"
SETUP_MODE=all

setup_done() { [ -f "$SETUP_STATE" ] && grep -qxF -- "$1" "$SETUP_STATE"; }

setup_mark() {
  mkdir -p "$(dirname "$SETUP_STATE")"
  [ -f "$SETUP_STATE" ] || printf '# Setup questions answered on this machine. Written by ./wiki.sh setup.\n' > "$SETUP_STATE"
  ensure_line "$SETUP_STATE" "$1"
}

# A question step is due in a full run always, and in --new only if unseen.
setup_due() { [ "$SETUP_MODE" = all ] || ! setup_done "$1"; }

# The question steps that apply to this machine right now and haven't been answered.
setup_pending() {
  local k
  [ -d "$WIKIS_DIR" ] || return 0
  setup_done git || echo git
  if in_git_repo "$WIKIS_DIR"; then setup_done git.identity || echo git.identity; fi
  setup_done delegation.mode || echo delegation.mode
  setup_done journal.enabled || echo journal.enabled
  [ "$(journal_get enabled)" = yes ] || return 0
  for k in $JOURNAL_KEYS; do
    [ "$k" = enabled ] && continue
    setup_done "journal.$k" || echo "journal.$k"
  done
}

section() { printf '\n== %s\n' "$1"; }

# ask_yn <question> <y|n>: succeed for yes.
ask_yn() {
  local r hint="[y/N]"
  [ "$2" = y ] && hint="[Y/n]"
  while :; do
    printf '%s %s ' "$1" "$hint"
    IFS= read -r r || die "input ended"
    case "${r:-$2}" in
      y | Y | yes) return 0 ;;
      n | N | no) return 1 ;;
    esac
    echo "  Answer y or n."
  done
}

# ask <question> <current>: Enter keeps the current value, a single - clears it.
# The answer is left in ANSWER.
ask() {
  local r
  if [ -n "$2" ]; then printf '%s [%s]: ' "$1" "$2"; else printf '%s [none]: ' "$1"; fi
  IFS= read -r r || die "input ended"
  case "$r" in
    '') ANSWER="$2" ;;
    -) ANSWER="" ;;
    *) ANSWER="$r" ;;
  esac
}

setup_collection() {
  local n=0 d
  if [ "$SETUP_MODE" = new ] && [ -f "$WIKIS_DIR/WIKIS.md" ] && is_wiki "$WIKIS_DIR/$SHARED"; then return 0; fi
  section "Collection"
  if [ -d "$WIKIS_DIR" ]; then
    for d in "$WIKIS_DIR"/*/; do is_wiki "${d%/}" && n=$((n + 1)); done
    echo "Wikis live in $(tilde "$WIKIS_DIR"): $n found."
  else
    echo "Wikis will live in $(tilde "$WIKIS_DIR"). For another folder, quit and rerun with WIKIS_DIR=<path> set."
    if ask_yn "Create it now?" y; then
      init_collection | sed 's/^/  /'
    else
      echo "Nothing else to set up without a collection."
      exit 0
    fi
  fi
  write_collection_marker | sed 's/^/  /'
  if ! is_wiki "$WIKIS_DIR/$SHARED"; then
    echo "There is no shared wiki at $(tilde "$WIKIS_DIR/$SHARED"). It holds knowledge that applies to every project."
    if ask_yn "Create it?" y; then scaffold "$WIKIS_DIR/$SHARED" 0 | sed 's/^/  /'; fi
  fi
}

setup_git() {
  local url
  if setup_due git; then
    section "Git"
    if in_git_repo "$WIKIS_DIR"; then
      echo "The collection is a git repo. Agents commit and push their wiki changes to it."
    else
      echo "The collection isn't a git repo. Git gives it history, undo, and sync between machines."
      if ask_yn "Make it one?" y; then
        git_init_collection | sed 's/^/  /'
      else
        setup_mark git
        return 0
      fi
    fi
    url="$(git -C "$WIKIS_DIR" remote get-url origin 2>/dev/null || true)"
    if [ -n "$url" ]; then
      echo "Remote: $url"
    else
      echo "No remote yet. With one, agents push and your other machines pull."
      ask "Remote URL, such as git@github.com:you/wikis.git. Enter for none" ""
      if [ -n "$ANSWER" ]; then
        git -C "$WIKIS_DIR" remote add origin "$ANSWER"
        echo "  added remote origin"
      fi
    fi
    setup_mark git
  fi
  in_git_repo "$WIKIS_DIR" || return 0
  # A repo with no commits yet needs a name and email before anything else.
  if setup_due git.identity || ! git -C "$WIKIS_DIR" rev-parse -q --verify HEAD >/dev/null; then
    setup_identity
    if ! git -C "$WIKIS_DIR" rev-parse -q --verify HEAD >/dev/null; then
      git_first_commit | sed 's/^/  /'
    fi
    setup_push_check
  fi
  install_hook "$WIKIS_DIR" | sed 's/^/  /'
}

# Which account commits and pushes. Matters on a machine with work and personal keys.
setup_identity() {
  local cur key cmd url
  section "Git identity for this collection"
  cur="$(git -C "$WIKIS_DIR" config user.name 2>/dev/null || true)"
  if [ -z "$cur" ]; then
    while :; do
      ask "Name for commits in this repo" ""
      [ -n "$ANSWER" ] && break
    done
    git -C "$WIKIS_DIR" config user.name "$ANSWER"
  fi
  cur="$(git -C "$WIKIS_DIR" config user.email 2>/dev/null || true)"
  echo "Commits are made as: ${cur:-nobody yet}"
  while :; do
    ask "Email for commits in this repo only" "$cur"
    [ -n "$ANSWER" ] && break
    echo "  Commits need an email."
  done
  if [ "$ANSWER" != "$cur" ] || [ -z "$(git -C "$WIKIS_DIR" config --local user.email || true)" ]; then
    git -C "$WIKIS_DIR" config user.email "$ANSWER"
    echo "  set user.email for this repo"
  fi
  cmd="$(git -C "$WIKIS_DIR" config --local core.sshCommand 2>/dev/null || true)"
  key="$(printf '%s' "$cmd" | sed -n 's/.*-i \([^ ]*\).*/\1/p')"
  url="$(git -C "$WIKIS_DIR" remote get-url origin 2>/dev/null || true)"
  case "$url" in
    ssh://* | *@*:*)
      echo "If your usual SSH key belongs to another account, name the key for this repo."
      echo "It is used alone, without ~/.ssh/config, so host aliases there don't apply here."
      while :; do
        ask "SSH key path. Enter keeps it, - uses your normal SSH setup" "$(tilde "$key")"
        # shellcheck disable=SC2088
        case "$ANSWER" in "~/"*) ANSWER="$HOME/${ANSWER:2}" ;; esac
        case "$ANSWER" in *" "*) echo "  Use a key path without spaces."; continue ;; esac
        if [ -z "$ANSWER" ] || [ -f "$ANSWER" ]; then break; fi
        echo "  No file at $ANSWER."
      done
      if [ -z "$ANSWER" ]; then
        if [ -n "$cmd" ]; then
          git -C "$WIKIS_DIR" config --local --unset core.sshCommand
          echo "  removed the repo's SSH key setting"
        fi
      elif [ "$ANSWER" != "$key" ]; then
        git -C "$WIKIS_DIR" config --local core.sshCommand "ssh -i $ANSWER -o IdentitiesOnly=yes -F /dev/null"
        echo "  this repo now pushes with $(tilde "$ANSWER")"
      fi
      ;;
  esac
  setup_mark git.identity
}

# Try a push without sending anything, so a wrong key shows up now, not in an agent's session.
setup_push_check() {
  local url cmd err
  url="$(git -C "$WIKIS_DIR" remote get-url origin 2>/dev/null || true)"
  [ -n "$url" ] || return 0
  git -C "$WIKIS_DIR" rev-parse -q --verify HEAD >/dev/null || return 0
  ask_yn "Check that you can push to $url now?" y || return 0
  cmd="$(git -C "$WIKIS_DIR" config core.sshCommand 2>/dev/null || echo ssh)"
  if err="$(GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="$cmd -o BatchMode=yes -o ConnectTimeout=10" \
    git -C "$WIKIS_DIR" push --dry-run --quiet origin HEAD 2>&1)"; then
    echo "  ok: push access works"
  else
    echo "  push failed:"
    printf '%s\n' "$err" | grep -v '^$' | head -n 4 | sed 's/^/    /'
    echo "  Fix the key or the remote, then run: ./wiki.sh setup git"
  fi
}

setup_claude() {
  local state
  state="$(claude_state)"
  [ "$SETUP_MODE" = new ] && [ "$state" = current ] && return 0
  section "Claude Code"
  case "$state" in
    current) echo "$(tilde "$CLAUDE_FILE") has the current wiki line. Every session finds its wiki." ;;
    old)
      echo "$(tilde "$CLAUDE_FILE") has an older wiki line."
      if ask_yn "Replace it with the current one?" y; then cmd_claude | head -n 1 | sed 's/^/  /'; fi
      ;;
    missing)
      echo "One line in $(tilde "$CLAUDE_FILE") lets every Claude Code session find its wiki."
      echo "Other agents: put the same line in their user-level instruction file."
      if ask_yn "Add it?" y; then cmd_claude | head -n 1 | sed 's/^/  /'; fi
      ;;
  esac
}

setup_upgrade() {
  local d tv behind from
  tv="$(version_of "$TEMPLATE/AGENTS.md")"
  behind="$(setup_upgrade_needed)"
  [ "$SETUP_MODE" = new ] && [ -z "$behind" ] && return 0
  section "Handbooks"
  if [ -z "$behind" ]; then
    echo "Every wiki is on handbook v$tv."
    return 0
  fi
  echo "Behind the template's v$tv:$behind"
  from="$(oldest_version "$(behind_versions)")"
  if ask_yn "Upgrade them now? Pages and notes are untouched." y; then
    for d in $behind; do
      printf '  %s: ' "$d"
      upgrade_one "$WIKIS_DIR/$d" | sed -n 's/^handbook: //p'
    done
    echo "What's new since v$from:"
    changelog_since "$from" | sed 's/^/  /'
    echo "New sessions load the new handbook. Running sessions keep the old one until restarted."
    upgrade_commit_hint "$behind" ""
  fi
}

setup_delegation() {
  local cur
  setup_due delegation.mode || return 0
  section "Delegation"
  write_delegation_file | sed 's/^/  /'
  apply_delegation_ignore | sed 's/^/  /'
  echo "Sessions can hand big, self-contained work, like test runs and file sweeps, to sub-agents on cheaper models."
  echo "off: never unless you ask. ask: suggest each one and wait for a yes. auto: do it and say so after."
  echo "Which kinds of work go to which model is a table in $(tilde "$DELEG_FILE"). Edit it any time."
  cur="$(deleg_mode)"
  while :; do
    ask "  mode (off, ask, auto)" "$cur"
    case "$ANSWER" in off | ask | auto) break ;; esac
    echo "  Answer off, ask, or auto."
  done
  if [ "$ANSWER" != "$cur" ] || ! grep -q '^mode:' "$DELEG_FILE"; then deleg_set_mode "$ANSWER" | sed 's/^/  /'; fi
  setup_mark delegation.mode
}

setup_journal_key() {
  local key="$1" cur type desc val err hint
  cur="$(journal_get "$key")"
  type="$(journal_field "$key" 2)"
  desc="$(journal_field "$key" 5)"
  case "$type" in
    yesno) hint="y/n" ;;
    */*) hint="${type//\//, }" ;;
    *) hint="" ;;
  esac
  printf '\n%s\n' "$desc"
  while :; do
    ask "  $key${hint:+ ($hint)}" "$cur"
    val="$ANSWER"
    if [ "$type" = yesno ]; then
      case "$val" in y | Y) val=yes ;; n | N) val=no ;; esac
    fi
    if [ "$type" != text ] && [ -z "$val" ]; then
      echo "  $key can't be empty."
      continue
    fi
    if err="$(journal_check "$key" "$val")"; then break; fi
    echo "  $err"
  done
  if [ "$val" != "$cur" ] || ! grep -q "^$key=" "$JOURNAL_CFG"; then
    journal_set "$key" "$val" | sed 's/^/  /'
  fi
  setup_mark "journal.$key"
}

setup_journal() {
  local k due="" adv=""
  for k in $JOURNAL_KEYS; do
    if setup_due "journal.$k"; then due="$due $k"; fi
  done
  [ -n "$due" ] || return 0
  section "Work journal"
  write_journal_config | sed 's/^/  /'
  echo "Agents note work that leaves no commit, and ./wiki.sh standup turns your day into a report."
  for k in $due; do
    [ "$(journal_field "$k" 3)" = basic ] || { adv="$adv $k"; continue; }
    setup_journal_key "$k"
    if [ "$k" = enabled ] && [ "$(journal_get enabled)" = no ]; then
      echo "  The journal is off. Its other settings are skipped."
      return 0
    fi
  done
  [ -n "$adv" ] || return 0
  if [ "$SETUP_MODE" = all ]; then
    echo
    if ! ask_yn "Change advanced journal settings ($(echo "$adv" | sed 's/^ //; s/ /, /g'))?" n; then
      for k in $adv; do setup_mark "journal.$k"; done
      return 0
    fi
  fi
  for k in $adv; do setup_journal_key "$k"; done
}

setup_list() {
  local k v pending
  pending=" $(setup_pending | tr '\n' ' ')"
  echo "collection          $(tilde "$WIKIS_DIR")$([ -d "$WIKIS_DIR" ] || echo ' (missing)')"
  if in_git_repo "$WIKIS_DIR"; then
    echo "git                 remote $(git -C "$WIKIS_DIR" remote get-url origin 2>/dev/null || echo none)"
    echo "git.identity        $(git -C "$WIKIS_DIR" config user.email 2>/dev/null || echo 'no email set')"
  else
    echo "git                 not a repo"
  fi
  echo "claude              $(claude_state)"
  printf '%-19s %s' "delegation.mode" "$(deleg_mode)"
  case "$pending" in *" delegation.mode "*) printf '  <- new' ;; esac
  printf '\n'

  for k in $JOURNAL_KEYS; do
    v="$(journal_get "$k")"
    printf '%-19s %s' "journal.$k" "${v:-(none)}"
    if [ "$v" = "$(journal_default "$k")" ]; then printf '  (default)'; fi
    case "$pending" in *" journal.$k "*) printf '  <- new' ;; esac
    printf '\n'
  done
  case "$pending" in *" git "* | *" git.identity "*) echo "(git questions not yet answered on this machine)" ;; esac
  echo
  echo "Change one:    ./wiki.sh setup journal.<key>   or   ./wiki.sh setup git.identity"
  echo "Or a section:  ./wiki.sh setup git | claude | upgrade | delegation | journal"
}

cmd_setup() {
  local what="" a n
  for a in "$@"; do
    case "$a" in
      --new) SETUP_MODE=new ;;
      --list) setup_list; return 0 ;;
      -h | --help)
        cat <<'EOF'
Usage: ./wiki.sh setup [--new | --list | <section> | <setting>]

  setup            Walk through every setting. Enter keeps what you have.
  setup --new      Only what's missing, out of date, or added since you last ran it.
  setup --list     Print current values without asking anything.
  setup <section>  Just one section: collection, git, claude, upgrade, delegation, journal.
  setup <setting>  Just one setting: git.identity, or journal.<key> such as journal.format.
                   A bare journal key works too: setup format.
EOF
        return 0
        ;;
      collection | git | claude | upgrade | journal | delegation | git.identity) what="$a" ;;
      journal.*)
        [ -n "$(journal_field "${a#journal.}" 2)" ] || die "no journal setting called ${a#journal.}. Settings: $JOURNAL_KEYS"
        what="$a"
        ;;
      *)
        # A bare journal key works too: setup format
        if [ -n "$(journal_field "$a" 2)" ]; then what="journal.$a"; else
          die "setup: unknown option $a. Try ./wiki.sh setup --help"
        fi
        ;;
    esac
  done
  [ -t 0 ] || die "setup asks questions, so it needs a terminal. ./wiki.sh setup --list prints the current values."
  if [ "$SETUP_MODE" = new ] && [ -d "$WIKIS_DIR" ] && [ "$(claude_state)" = current ]; then
    n="$(setup_pending | wc -l | tr -d ' ')"
    [ "$n" -gt 0 ] || [ -n "$(setup_upgrade_needed)" ] || { echo "Nothing new to set up."; return 0; }
  fi
  echo "Setup for $(tilde "$WIKIS_DIR"). Enter keeps the value in brackets."
  case "$what" in
    collection) setup_collection ;;
    git) SETUP_MODE=all; setup_git ;;
    claude) SETUP_MODE=all; setup_claude ;;
    upgrade) SETUP_MODE=all; setup_upgrade ;;
    journal) SETUP_MODE=all; setup_journal ;;
    delegation) SETUP_MODE=all; setup_delegation ;;
    git.identity)
      in_git_repo "$WIKIS_DIR" || die "$(tilde "$WIKIS_DIR") isn't a git repo yet. Run: ./wiki.sh setup git"
      setup_identity
      setup_push_check
      ;;
    journal.*)
      write_journal_config | sed 's/^/  /'
      setup_journal_key "${what#journal.}"
      ;;
    '')
      setup_collection
      setup_git
      setup_claude
      setup_upgrade
      setup_delegation
      setup_journal
      ;;
  esac
  case "$what" in
    *.*) return 0 ;;
  esac
  echo
  echo "Done. Run ./wiki.sh setup --new after pulling template updates to see what's new."
}

# Names of wikis behind the template handbook, space separated.
setup_upgrade_needed() {
  local d v tv
  tv="$(version_of "$TEMPLATE/AGENTS.md")"
  [ -d "$WIKIS_DIR" ] || return 0
  for d in "$WIKIS_DIR"/*/; do
    d="${d%/}"
    is_wiki "$d" || continue
    v="$(version_of "$d/AGENTS.md")"
    if [ "${v:-0}" -lt "${tv:-0}" ]; then printf ' %s' "${d##*/}"; fi
  done
}

# ---- argument parsing ----
[ $# -ge 1 ] || { usage; exit 1; }
cmd="$1"
shift
if [ "$cmd" = journal ]; then
  cmd_journal "$@"
  exit 0
fi
if [ "$cmd" = standup ]; then
  cmd_standup "$@"
  exit 0
fi
if [ "$cmd" = delegation ]; then
  cmd_delegation "$@"
  exit 0
fi
if [ "$cmd" = setup ]; then
  cmd_setup "$@"
  exit 0
fi
if [ "$cmd" = cover ]; then
  [ $# -ge 2 ] || die "usage: ./wiki.sh cover <wiki> <repo>..."
  cmd_cover "$@"
  exit 0
fi
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
  new)
    need_target
    valid_name "${target##*/}" \
      || die "\"${target##*/}\" can't be a wiki name. Use the repository's name: letters, digits, dots, dashes, underscores."
    case "$target" in
      */*) ;;
      *)
        owner="$(which_wiki "$target")"
        if [ -n "$owner" ] && [ "$owner" != "$target" ]; then
          die "$target is already covered by the wiki $owner. Use that one."
        fi
        ;;
    esac
    cmd_new "$(resolve "$target")" "$want_git"
    ;;
  status) cmd_status ;;
  find) [ -n "$target" ] || die "find needs a word"; cmd_find "$target" ;;
  which) [ -n "$target" ] || die "which needs a repository name"; cmd_which "$target" ;;
  stale) cmd_stale "${target:-90}" ;;
  upgrade)
    if [ "$want_all" = 1 ]; then cmd_upgrade_all; else need_target; cmd_upgrade_one "$(resolve "$target")"; fi
    ;;
  unlock) need_target; cmd_unlock "$(resolve "$target")" ;;
  claude) cmd_claude ;;
  patterns) cmd_patterns ;;
  -h | --help | help) usage ;;
  *) usage; exit 1 ;;
esac
