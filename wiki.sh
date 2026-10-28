#!/usr/bin/env bash
# wiki.sh: set up and look after LLM wikis built from this template.
# Works with the bash that ships on macOS (3.2) and on Linux.
set -euo pipefail

# Follow symlinks, such as ~/.local/bin/wiki, to the real script: template/ sits beside it.
src="${BASH_SOURCE[0]}"
while [ -L "$src" ]; do
  dir="$(cd "$(dirname "$src")" && pwd)"
  src="$(readlink "$src")"
  case "$src" in /*) ;; *) src="$dir/$src" ;; esac
done
REPO="$(cd "$(dirname "$src")" && pwd)"
TEMPLATE="$REPO/template"
WIKIS_DIR="${WIKIS_DIR:-$HOME/wikis}"
SHARED="global"
# The command people type, for messages. The plugin's stable `wiki` command sets
# LLM_WIKI_CMD. Run as wiki.sh, it's ./wiki.sh from the clone; through a link, the link's name.
case "${0##*/}" in
  wiki.sh) WIKI_CMD="${LLM_WIKI_CMD:-./wiki.sh}" ;;
  *) WIKI_CMD="${LLM_WIKI_CMD:-${0##*/}}" ;;
esac

usage() {
  cat <<EOF
Usage: $WIKI_CMD <command> [options]

  setup                Walk through every setting, step by step. Safe to rerun.
  setup --new          Only what's new since you last ran it, such as after a template update.
  setup --list         Print current settings without asking.
  init                 Create the wiki collection at $(tilde "$WIKIS_DIR") and its shared wiki, $SHARED.
  new <name|path>      Create a wiki from the template. A bare name goes under $(tilde "$WIKIS_DIR").
  capture <wiki> <slug>  Save a note piped on stdin in raw/, named from the clock.
                       --copy FILE stores a document unchanged instead.
  lock <wiki> [--release|--renew]  Take, release or renew the compile lock.
  log <wiki> <type> [title] [--created P] [--updated P] [--fixed T] [--reported T]
                       Append a log.md entry and print its counts.
  sync <wiki> [-m MSG] Commit this wiki's changes, pull with a merge, and push.
  harvest [--dry-run]  Copy Claude Code's own memory notes into the wikis, where every
                       repo and teammate can use them.
  pending [<wiki>] [--show]
                       Notes waiting to be compiled. --show prints a wiki's in one go.
  seed [<repo>] [--wiki NAME] [--max N] [--dry-run]
                       Start a wiki from a repository's own docs: README, agent
                       instructions, skills, docs/, decision records.
  cover <wiki> <repo>...  Record that one wiki covers several repositories.
  which <repo>         Print the wiki that covers a repository.
  status               List wikis: handbook version, notes waiting, lock state.
  find <word>          Search every wiki's index for a word.
  stale [days]         List pages not verified in that many days (default 90).
  patterns             Recurring feedback across wikis, and which patterns are ready to propose.
  skills [link]        Team skills in the wikis, and link them into ~/.claude/skills.
  tips [--mute NAME]   Features your own wikis suggest you'd get something out of.
  completion zsh|bash  Print tab completion for a shell. wiki setup turns it on.
  report [--since R]   Weekly look: tokens per project, what the wikis gained, hit
                       rate, and what needs you. An agent writes it up.
  stats [range]        How often wikis answered the questions sessions checked them for (default 30d).
  delegation [off|ask|auto]  Show handoff mode and results by kind of work, or set the mode.
  delegation log <kind> <model> <effort> <ok|fixed|redone>  Record one handoff.
  upgrade <name|path>  Bring a wiki's handbook and scaffold files up to the template's.
  upgrade --all        Do that for every wiki in the collection.
  unlock <name|path>   Free a stuck compile lock.
  claude               Add the wiki line to ~/.claude/CLAUDE.md so every session finds its wiki.
  claude --print       Print the line, for another agent's instruction file.
  link [--yes]         With the plugin: make wiki a command in every terminal.

  journal              Show the work journal's settings and today's entry count.
  journal on | off     Turn the journal on or off. It is on by default.
  journal set <key> <value>  Change a setting. See $(tilde "$WIKIS_DIR")/journal/config.
  journal note [--day DATE] [--at HH:MM] <project> <text>
                       Add one line to today's journal, or a past day's.
  journal backfill [--since 14d] [--until DATE] [--done]
                       Digest past Claude Code sessions into journal/backfill.md.
                       An agent turns the digest into entries.
  journal path | prune Print today's journal file. Delete days older than keep_days.
  standup [options]    Gather what you did: commits, journal lines, wiki notes,
                       work in progress, open checks. An agent turns it into a report.
                       --since lastworkday|yesterday|today|week|lastweek|7d|DATE
                       --until DATE  --day DATE  --format standup|summary|detailed
                       --only GLOB  --exclude GLOB  --max N  --save

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
    which_miss "$name" >&2
    exit 1
  fi
}

# which_miss <repository>: say so, and point at the likely fix. A repository whose
# folder name differs from its project wiki, like history for cloud-dvr, otherwise
# leaves sessions guessing names.
which_miss() {
  local name="$1" d w t hits=""
  echo "no wiki covers $name"
  for d in "$WIKIS_DIR"/*/; do
    d="${d%/}"
    is_wiki "$d" || continue
    w="${d##*/}"
    # Shares a word of three letters or more, or its index mentions the repository.
    for t in $(printf '%s' "$name" | tr -c 'A-Za-z0-9\n' ' '); do
      [ "${#t}" -ge 3 ] || continue
      case "-$w-" in *"$t"*) hits="$hits $w"; continue 2 ;; esac
    done
    grep -qiF -- "$name" "$d/index.md" 2>/dev/null && hits="$hits $w"
  done
  if [ -n "$hits" ]; then
    # shellcheck disable=SC2086
    echo "Close matches:$(printf ' %s' $hits | tr ' ' '\n' | sort -u | head -n 5 | tr '\n' ' ' | sed 's/ $//')"
    echo "If $name belongs to one of them: $WIKI_CMD cover <wiki> $name"
  fi
  echo "If it's a project of its own, the first session with something to file creates its wiki: $WIKI_CMD new $name"
}

# cover <wiki> <repo>...: record that one wiki covers several repositories.
# ---- bookkeeping ------------------------------------------------------------
# The mechanical steps of capturing and compiling, as commands. Done by hand,
# agents rounded capture times, skipped the Captured line, and spent dozens of
# shell calls on locks and log entries. The handbook names these commands, and
# keeps the by-hand steps for agents without the script.

# wiki_root <name or path>: the wiki's folder, or an error.
wiki_root() {
  local root
  [ -n "${1:-}" ] || die "name a wiki"
  root="$(resolve "$1")"
  is_wiki "$root" || die "$(tilde "$root") is not a wiki"
  printf '%s' "$root"
}

# iso_epoch <YYYY-MM-DDTHH:MM:SSZ>: seconds since 1970, or nothing.
iso_epoch() {
  date -u -d "$1" +%s 2>/dev/null || date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null || true
}

# capture <wiki> <slug> [--copy FILE]
cmd_capture() {
  local wiki="" slug="" copy="" root stamp name ext stem n=2 tmp
  while [ $# -gt 0 ]; do
    case "$1" in
      --copy) copy="${2:-}"; shift 2 ;;
      -*) die "capture options: --copy FILE" ;;
      *) if [ -z "$wiki" ]; then wiki="$1"; elif [ -z "$slug" ]; then slug="$1"; else die "capture takes a wiki and a slug"; fi; shift ;;
    esac
  done
  root="$(wiki_root "$wiki")"
  if [ -n "$copy" ]; then
    [ -f "$copy" ] || die "no file at $copy"
    case "${copy##*/}" in
      ?*.*) ext="${copy##*.}"; stem="${copy##*/}"; stem="${stem%.*}" ;;
      *) ext=txt; stem="${copy##*/}" ;;
    esac
    [ -n "$slug" ] || slug="$stem"
  else
    ext=md
    [ -n "$slug" ] || die "capture needs a short slug for the name, such as decided-postgres"
    [ ! -t 0 ] || die "capture reads the note from stdin: pipe it in, or use a heredoc"
  fi
  slug="$(printf '%s' "$slug" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9][^a-z0-9]*/-/g; s/^-//; s/-$//')"
  [ -n "$slug" ] || die "that slug has no letters or digits"
  # The clock, to the second, in UTC. The name sets ingest order, so never round it.
  stamp="$(date -u +%Y-%m-%d-%H%M%S)"
  name="$stamp-$slug.$ext"
  while [ -e "$root/raw/$name" ]; do name="$stamp-$slug-$n.$ext"; n=$((n + 1)); done
  mkdir -p "$root/raw"
  if [ -n "$copy" ]; then
    cp "$copy" "$root/raw/$name"
  else
    tmp="$(mktemp)"
    cat > "$tmp"
    if [ ! -s "$tmp" ]; then rm -f "$tmp"; die "capture got an empty note"; fi
    {
      head -n 1 "$tmp" | grep -q '^Captured: ' || printf 'Captured: %s\n\n' "$(date -u +%Y-%m-%d)"
      cat "$tmp"
    } > "$root/raw/$name"
    rm -f "$tmp"
  fi
  echo "captured: raw/$name in $(tilde "$root")"
}

# lock <wiki> [--release | --renew]: the compile lock, as rules/compile.md describes.
cmd_lock() {
  local wiki="" mode=take root f line tok when now age then_
  while [ $# -gt 0 ]; do
    case "$1" in
      --release) mode=release; shift ;;
      --renew) mode=renew; shift ;;
      -*) die "lock options: --release, --renew" ;;
      *) wiki="$1"; shift ;;
    esac
  done
  root="$(wiki_root "$wiki")"
  f="$root/.compile-lock"
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  line="$(head -n 1 "$f" 2>/dev/null || true)"
  case "$mode" in
    release)
      printf 'free\n' > "$f"
      echo "released: $(tilde "$root")"
      ;;
    renew)
      case "$line" in held\ *) ;; *) die "the lock on $(tilde "$root") isn't held" ;; esac
      tok="$(printf '%s' "$line" | awk '{ print $2 }')"
      printf 'held %s %s\n' "$tok" "$now" > "$f"
      echo "renewed: $tok, $now"
      ;;
    take)
      case "$line" in
        held\ *)
          when="$(printf '%s' "$line" | awk '{ print $3 }')"
          then_="$(iso_epoch "$when")"
          age=0
          [ -z "$then_" ] || age=$(( $(date -u +%s) - then_ ))
          # Older than 30 minutes is stale. A time we can't read counts as held.
          if [ -z "$then_" ] || [ "$age" -lt 1800 ]; then
            echo "held: another session has held the lock on $(tilde "$root") since $when. Don't compile it now; carry on, and the notes wait for a later pause."
            exit 1
          fi
          ;;
      esac
      tok="$(od -An -N3 -tx1 /dev/urandom | tr -d ' \n')"
      printf 'held %s %s\n' "$tok" "$now" > "$f"
      # Read it back: if another session wrote in between, it's theirs.
      if [ "$(head -n 1 "$f")" != "held $tok $now" ]; then
        echo "held: another session took the lock on $(tilde "$root") first. Don't compile it now."
        exit 1
      fi
      echo "locked: $(tilde "$root"), token $tok. When compiling ends, even if it failed: $WIKI_CMD lock ${wiki} --release"
      ;;
  esac
}

# log <wiki> <type> [<title>] [--created P]... [--updated P]... [--fixed T]... [--reported T]...
#   [--corrections N] [--conflicts N] [--patterns N]
cmd_log() {
  local wiki="" type="" title="" root lines="" nc=0 nu=0 nf=0 nr=0 corrections="" conflicts="" patterns="" v f
  while [ $# -gt 0 ]; do
    case "$1" in
      --created) lines="$lines- created: ${2:-}"$'\n'; nc=$((nc + 1)); shift 2 ;;
      --updated) lines="$lines- updated: ${2:-}"$'\n'; nu=$((nu + 1)); shift 2 ;;
      --fixed) lines="$lines- fixed: ${2:-}"$'\n'; nf=$((nf + 1)); shift 2 ;;
      --reported) lines="$lines- reported: ${2:-}"$'\n'; nr=$((nr + 1)); shift 2 ;;
      --corrections | --conflicts | --patterns)
        v="${2:-}"
        case "$v" in '' | *[!0-9]*) die "$1 takes a number" ;; esac
        case "$1" in --corrections) corrections="$v" ;; --conflicts) conflicts="$v" ;; --patterns) patterns="$v" ;; esac
        shift 2
        ;;
      -*) die "log options: --created P, --updated P, --fixed T, --reported T, --corrections N, --conflicts N, --patterns N" ;;
      *) if [ -z "$wiki" ]; then wiki="$1"; elif [ -z "$type" ]; then type="$1"; else title="${title:+$title }$1"; fi; shift ;;
    esac
  done
  root="$(wiki_root "$wiki")"
  case "$type" in
    ingest) [ -n "$title" ] || die "an ingest entry needs the source page's title"; conflicts="${conflicts:-0}" ;;
    lint | restructure | resolve) ;;
    *) die "log types: ingest, lint, restructure, resolve" ;;
  esac
  [ -z "$corrections" ] || lines="$lines- corrections: $corrections"$'\n'
  [ -z "$patterns" ] || lines="$lines- patterns: $patterns"$'\n'
  [ -z "$conflicts" ] || lines="$lines- conflicts: $conflicts"$'\n'
  f="$root/log.md"
  [ -f "$f" ] || printf '# Log\n' > "$f"
  # A blank line before the entry, whatever the file ended with.
  if [ -n "$(tail -c 1 "$f")" ]; then printf '\n' >> "$f"; fi
  printf '\n## %s %s%s\n%s' "$(date -u +%Y-%m-%d)" "$type" "${title:+: $title}" "$lines" >> "$f"
  case "$type" in
    ingest) echo "logged: ingest: $title. $nc created, $nu updated${corrections:+, $corrections correction(s)}, ${conflicts} conflict(s)" ;;
    lint) echo "logged: lint. $nf fixed, $nr reported" ;;
    *) echo "logged: $type${title:+: $title}. $nc created, $nu updated" ;;
  esac
}

# sync <wiki> [-m MESSAGE]: commit this wiki's changes, pull, and push.
cmd_sync() {
  local wiki="" msg="" root repo path top err
  while [ $# -gt 0 ]; do
    case "$1" in
      -m) msg="${2:-}"; shift 2 ;;
      -*) die "sync options: -m MESSAGE" ;;
      *) wiki="$1"; shift ;;
    esac
  done
  root="$(wiki_root "$wiki")"
  top="$(git -C "$root" rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$top" ] && [ "$top" = "$(cd "$root" && pwd -P)" ]; then
    repo="$root"; path="."
  elif [ -n "$top" ] && [ -f "$WIKIS_DIR/WIKIS.md" ] && [ "$top" = "$(cd "$WIKIS_DIR" && pwd -P)" ]; then
    repo="$WIKIS_DIR"; path="${root##*/}"
  else
    echo "$(tilde "$root") isn't in a repo the wikis own, so there's nothing to sync. Commits are up to you there."
    return 0
  fi
  [ -n "$msg" ] || msg="${root##*/}: update"
  # Only this wiki: other sessions may have notes waiting, uncommitted, in other wikis.
  git -C "$repo" add -A -- "$path"
  if ! git -C "$repo" diff --cached --quiet -- "$path"; then
    if ! err="$(git -C "$repo" commit -q -m "$msg" -- "$path" 2>&1)"; then
      printf '%s\n' "$err"
      die "the commit was refused. If the secret scan stopped it, redact the secret as the handbook says, then sync again."
    fi
    echo "committed: $msg"
  else
    echo "nothing to commit in ${root##*/}"
  fi
  [ -n "$(git -C "$repo" remote)" ] || { echo "no remote, so nothing to pull or push"; return 0; }
  # A merge, never a rebase or a stash: a rebase refuses to run while another
  # wiki has uncommitted notes, and a merge doesn't mind them.
  if ! err="$(git -C "$repo" pull -q --no-rebase --no-edit 2>&1)"; then
    if [ -n "$(git -C "$repo" ls-files -u)" ]; then
      git -C "$repo" ls-files -u | awk '{ print $4 }' | sort -u | sed 's/^/  conflict: /'
      die "the pull hit a merge conflict. index.md and log.md merge on their own; for a page, stop and ask the user."
    fi
    printf '%s\n' "$err"
    die "the pull failed. If uncommitted changes in another wiki clash with what came in, run $WIKI_CMD sync for that wiki first."
  fi
  if ! git -C "$repo" push -q 2>/dev/null; then
    # Someone pushed in between: pull and push once more.
    git -C "$repo" pull -q --no-rebase --no-edit && git -C "$repo" push -q || die "the push was rejected twice. Ask the user."
  fi
  echo "synced: pulled and pushed $(tilde "$repo")"
}

# ---- pending ----------------------------------------------------------------
# Waiting files, for a compile. --show prints them in one go, so an agent compiling
# twenty seeded documents makes one call instead of twenty. Capped, so a big
# backlog comes in batches.
PENDING_SHOW_BYTES=150000

# pending_files <wiki root>: raw files with no source page yet, oldest first.
pending_files() {
  local f b
  for f in "$1"/raw/*; do
    [ -f "$f" ] || continue
    b="${f##*/}"
    case "$b" in .*) continue ;; esac
    [ -e "$1/wiki/sources/${b%.*}.md" ] || printf '%s\n' "$f"
  done
}

# pending [<wiki>] [--show]
cmd_pending() {
  local wiki="" show=0 root f size total=0 n=0 left=0 d
  while [ $# -gt 0 ]; do
    case "$1" in
      --show) show=1; shift ;;
      -*) die "pending options: --show" ;;
      *) wiki="$1"; shift ;;
    esac
  done
  if [ -z "$wiki" ]; then
    [ "$show" = 0 ] || die "pending --show needs a wiki name"
    for d in "$WIKIS_DIR"/*/; do
      d="${d%/}"
      is_wiki "$d" || continue
      n="$(pending_files "$d" | wc -l | tr -d ' ')"
      [ "$n" -eq 0 ] || echo "${d##*/}: $n waiting"
    done
    return 0
  fi
  root="$(resolve "$wiki")"
  is_wiki "$root" || die "$(tilde "$root") is not a wiki"
  if [ "$show" = 0 ]; then
    pending_files "$root" | while IFS= read -r f; do
      printf '%s  %s bytes\n' "raw/${f##*/}" "$(wc -c < "$f" | tr -d ' ')"
    done
    return 0
  fi
  while IFS= read -r f; do
    size="$(wc -c < "$f" | tr -d ' ')"
    if [ "$n" -gt 0 ] && [ $((total + size)) -gt "$PENDING_SHOW_BYTES" ]; then
      left=$((left + 1))
      continue
    fi
    total=$((total + size))
    n=$((n + 1))
    printf '===== raw/%s\n' "${f##*/}"
    cat "$f"
    printf '\n'
  done < <(pending_files "$root")
  printf '===== %d file(s) shown' "$n"
  if [ "$left" -gt 0 ]; then
    printf '. %d more wait. Compile these first, then run this again for the rest.\n' "$left"
  else
    printf ', none left.\n'
  fi
}

# ---- harvest ----------------------------------------------------------------
# Some agents keep notes of their own. Claude Code saves them per project folder,
# in ~/.claude/projects/<folder>/memory/, and only sessions in that folder load
# them, so a rule saved while working in one repo never reaches another. harvest
# copies them into the wikis' raw/ to be compiled. It never edits or deletes them.

# memory_project <project folder>: the wiki a Claude Code project folder belongs to.
# Its transcripts record the working folder, mapped the way the report does.
memory_project() {
  local cwd name w part
  cwd="$(cat "$1"/*.jsonl 2>/dev/null | grep -m 1 -o '"cwd":"[^"]*"' | sed 's/^"cwd":"//; s/"$//' || true)"
  [ -n "$cwd" ] || return 0
  if top="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)"; then name="$(repo_name "$top")"; else name="${cwd##*/}"; fi
  w="$(which_wiki "$name")"
  if [ -z "$w" ]; then
    # A scratch folder inside a project, such as politiboop/sweeps/b41, belongs to it.
    local IFS=/
    for part in $cwd; do [ -n "$part" ] && [ -n "$(which_wiki "$part")" ] && w="$(which_wiki "$part")"; done
  fi
  printf '%s' "$w"
}

# memory_type <file>: user, feedback, project, reference, or nothing.
memory_type() { sed -n '/^---$/,/^---$/s/^ *type: *\([a-z]*\).*/\1/p' "$1" | head -n 1; }

# harvest [--from DIR] [--dry-run]
cmd_harvest() {
  local from="$HOME/.claude/projects" dry=0 dir f type wiki slug stamp dest n=0 same=0 g d man
  while [ $# -gt 0 ]; do
    case "$1" in
      --from) from="${2:-}"; shift 2 ;;
      --dry-run) dry=1; shift ;;
      *) die "harvest options: --from DIR, --dry-run" ;;
    esac
  done
  [ -d "$from" ] || die "no Claude Code projects at $(tilde "$from")"
  is_wiki "$WIKIS_DIR/$SHARED" || die "there's no shared wiki at $(tilde "$WIKIS_DIR/$SHARED"). Run: $WIKI_CMD setup"
  stamp="$(date -u +%Y-%m-%d-%H%M%S)"
  man="$(mktemp)"
  for dir in "$from"/*/; do
    dir="${dir%/}"
    [ -d "$dir/memory" ] || continue
    wiki="$(memory_project "$dir")"
    for f in "$dir"/memory/*.md; do
      [ -f "$f" ] || continue
      [ "${f##*/}" = MEMORY.md ] && continue
      type="$(memory_type "$f")"
      # Notes about the user, and corrections, are how agents should work everywhere.
      case "$type" in
        user | feedback) g="$SHARED" ;;
        *) g="${wiki:-$SHARED}" ;;
      esac
      slug="$(basename "$f" .md | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9][^a-z0-9]*/-/g; s/^-//; s/-$//')"
      # The same note harvested before, from any folder: skip it.
      for d in "$WIKIS_DIR/$g"/raw/*-harvest-*; do
        [ -f "$d" ] && cmp -s "$f" "$d" && { same=$((same + 1)); continue 2; }
      done
      n=$((n + 1))
      dest="$stamp-harvest-$(printf '%02d' "$n")-$slug.md"
      if [ "$dry" = 1 ]; then
        printf 'would copy: %s -> %s (%s, from %s)\n' "$(tilde "$f")" "$g" "${type:-untyped}" "${wiki:-an unknown project}"
      else
        cp "$f" "$WIKIS_DIR/$g/raw/$dest"
        printf '%s\t- raw/%s: %s note, saved while working in %s\n' "$g" "$dest" "${type:-untyped}" "${wiki:-an unknown project}" >> "$man"
      fi
    done
  done
  # One manifest per wiki, first in ingest order, saying where the copies came from.
  if [ "$dry" = 0 ] && [ -s "$man" ]; then
    for g in $(cut -f 1 "$man" | sort -u); do
      {
        printf 'Captured: %s\n\n# Harvested from Claude Code memory\n\n' "$(date -u +%Y-%m-%d)"
        printf '%s\n\n' "\`wiki.sh harvest\` copied these notes from Claude Code's own memory, which only reaches sessions in the folder it was saved in. Compile them like any source. Each copy keeps its frontmatter, whose \`type\` says what it is: \`user\` and \`feedback\` notes are how the user wants agents to work, and belong in the shared wiki's \`wiki/conventions.md\` under \`## For agents\`. File everything else as AGENTS.md says under Ownership: a lesson that holds beyond one project goes in the shared wiki. Treat claims about code as unchecked until you check them. Some notes repeat what a wiki already says: merge them, don't copy. A note that turns out to be about one project only belongs in that project's wiki: each line below says where it was saved."
        awk -F '\t' -v g="$g" '$1 == g { print $2 }' "$man"
      } > "$WIKIS_DIR/$g/raw/$stamp-harvest-00-manifest.md"
      printf '%s: %s note(s)\n' "$g" "$(awk -F '\t' -v g="$g" '$1 == g' "$man" | wc -l | tr -d ' ')"
    done
  fi
  rm -f "$man"
  if [ "$dry" = 0 ]; then mkdir -p "${HARVEST_STAMP%/*}" && touch "$HARVEST_STAMP"; fi
  [ "$same" -eq 0 ] || echo "skipped $same already harvested"
  if [ "$n" -eq 0 ]; then
    echo "nothing new to harvest from $(tilde "$from")"
  elif [ "$dry" = 1 ]; then
    echo "$n note(s) would be copied. Nothing in $(tilde "$from") changes."
  else
    echo "$n note(s) copied into the wikis' raw/. The next sessions compile them; general ones end up in the shared wiki. Your Claude Code memory is unchanged."
  fi
}

# ---- seed -------------------------------------------------------------------
# A new wiki is empty, so nothing seems to happen for days. seed copies a
# repository's own documents into its wiki's raw/, and the next session compiles
# them. Only files git tracks, so build output and dependencies never come along.
SEED_MAX_BYTES=100000

# seed_candidates <repo top>: tracked documents worth compiling, most useful first:
# the README, agent instructions and top-level guides, skills and editor rules,
# decision records, docs/, then READMEs and agent instructions further down.
seed_candidates() {
  git -C "$1" -c core.quotePath=false ls-files 2>/dev/null | awk '
    { f = $0; l = tolower(f); n = split(l, p, "/"); base = p[n] }
    l ~ /(^|\/)(node_modules|vendor|third_party)\// { next }
    # How agents should work in this repository: often its best-kept docs.
    l == "claude.md" || l == "agents.md" || l == "gemini.md" || l == ".cursorrules" || l == ".windsurfrules" \
      || l == ".github/copilot-instructions.md" { printf "1 %d %s\n", n, f; next }
    l ~ /^\.claude\/skills\/[^\/]+\/skill\.md$/ || l ~ /^\.cursor\/rules\/[^\/]+\.(md|mdc)$/ { printf "2 %d %s\n", n, f; next }
    l ~ /(^|\/)\.github\// { next }
    l ~ /(^|\/)(changelog|history|license|licence|notice|code_of_conduct|security|codeowners)[^\/]*$/ { next }
    l !~ /\.(md|mdx|markdown|rst|adoc|txt)$/ { next }
    {
      if (n == 1 && base ~ /^readme/) r = 0
      else if (n == 1 && base ~ /^(architecture|design|contributing|development|overview)/) r = 1
      else if (l ~ /(^|\/)(adr|adrs|decisions|rfc|rfcs)\//) r = 2
      else if (l ~ /^(doc|docs|documentation)\//) r = 3
      else if (base ~ /^(readme|claude\.md|agents\.md)/) r = 4
      else next
      printf "%d %d %s\n", r, n, f
    }' | sort -k1,1n -k2,2n -k3 | cut -d ' ' -f 3-
}

# seed [<repo path>] [--wiki NAME] [--max N] [--dry-run]
cmd_seed() {
  local src="" wiki="" max=20 dry=0 top name root stamp commit f ext stem slug dest size
  local n=0 more=0 already=0 big="" list=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --wiki) wiki="${2:-}"; shift 2 ;;
      --max) max="${2:-}"; shift 2 ;;
      --dry-run) dry=1; shift ;;
      -*) die "seed options: --wiki NAME, --max N, --dry-run" ;;
      *) [ -z "$src" ] || die "seed takes one repository"; src="$1"; shift ;;
    esac
  done
  case "$max" in '' | *[!0-9]*) die "--max takes a number" ;; esac
  top="$(git -C "${src:-.}" rev-parse --show-toplevel 2>/dev/null)" || die "${src:-this folder} isn't in a git repository"
  name="$(repo_name "$top")"
  [ -n "$wiki" ] || wiki="$(which_wiki "$name")"
  [ -n "$wiki" ] || wiki="$name"
  valid_name "$wiki" || die "\"$wiki\" can't be a wiki name. Pass one with --wiki."
  root="$WIKIS_DIR/$wiki"
  if [ "$dry" = 0 ] && ! is_wiki "$root"; then scaffold "$root" 0; fi
  stamp="$(date -u +%Y-%m-%d-%H%M%S)"
  commit="$(git -C "$top" rev-parse --short HEAD 2>/dev/null || echo none)"
  while IFS= read -r f; do
    [ -f "$top/$f" ] || continue
    size="$(wc -c < "$top/$f" | tr -d ' ')"
    [ "$size" -gt 0 ] || continue
    if [ "$size" -gt "$SEED_MAX_BYTES" ]; then big="$big  $f ($((size / 1000))KB)"$'\n'; continue; fi
    # A file with no extension, like .cursorrules, is copied as .txt.
    case "${f##*/}" in
      .*.* | [!.]*.*) ext="${f##*.}"; stem="${f%.*}" ;;
      *) ext=txt; stem="$f" ;;
    esac
    slug="$(printf '%s' "$stem" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9][^a-z0-9]*/-/g; s/^-//; s/-$//')"
    # Seeded before: the same document under any earlier stamp.
    if ls "$root"/raw/*-seed-[0-9][0-9]-"$slug.$ext" >/dev/null 2>&1; then already=$((already + 1)); continue; fi
    if [ "$n" -ge "$max" ]; then more=$((more + 1)); continue; fi
    n=$((n + 1))
    dest="$stamp-seed-$(printf '%02d' "$n")-$slug.$ext"
    if [ "$dry" = 1 ]; then
      echo "would copy: $f"
    else
      cp "$top/$f" "$root/raw/$dest"
      echo "seeded:  $f"
    fi
    list="$list- raw/$dest: $f"$'\n'
  done < <(seed_candidates "$top")
  # A note first in ingest order, so the compile knows where the copies came from.
  if [ "$dry" = 0 ] && [ "$n" -gt 0 ]; then
    # Never overwrite: a second seed in the same second gets -2, as the handbook names captures.
    dest="$stamp-seed-00-manifest.md"
    f=2
    while [ -e "$root/raw/$dest" ]; do dest="$stamp-seed-00-manifest-$f.md"; f=$((f + 1)); done
    cat > "$root/raw/$dest" <<EOF
Captured: $(date -u +%Y-%m-%d)

# Seeded from the $name repository

\`wiki.sh seed\` copied these documents from the $name repository at commit $commit. They are the repository's own docs, as its authors wrote them. Compile them like any source. Treat their claims about code as unchecked until checked against the code, and don't stamp \`commit\` on them before that.

$list
EOF
  fi
  [ -z "$big" ] || printf 'skipped, over %sKB:\n%s' "$((SEED_MAX_BYTES / 1000))" "$big"
  [ "$already" -eq 0 ] || echo "skipped $already already seeded"
  [ "$more" -eq 0 ] || echo "left out $more more. Rerun with a higher --max to take them too."
  if [ "$n" -eq 0 ]; then
    echo "nothing new to seed from $(tilde "$top")"
  elif [ "$dry" = 1 ]; then
    echo "$n document(s) would go into $(tilde "$root")"
  else
    echo "$n document(s) are waiting in $(tilde "$root/raw"). The next session there compiles them, or say \"compile $wiki\"."
  fi
}

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

# The shared wiki's conventions page. Sessions read its For agents section at every
# start, and check code against the rest, so it has to exist before anyone fills it.
ensure_shared_conventions() {
  local g="$WIKIS_DIR/$SHARED" f today
  is_wiki "$g" || return 0
  f="$g/wiki/conventions.md"
  [ -f "$f" ] && return 0
  today="$(date -u +%Y-%m-%d)"
  mkdir -p "$g/wiki"
  cat > "$f" <<EOF
---
title: Conventions
summary: Rules every session follows, in every project. How agents work with the user, and conventions for code.
tags: [conventions]
sources: []
updated: $today
verified: $today
---

# Conventions

One rule per line, each naming where it came from: a note in \`raw/\`, or a \`patterns.md\` entry in brackets. Sessions read **For agents** at every start, and check code against **For code** before calling it done.

## For agents

How the user wants agents to work with them, in every repository: committing and pushing, branches, writing style, when to ask and when to look it up.

## For code

Conventions for code in every repository. A rule about using one library belongs in that library's wiki, under \`## For code that uses this\`.
EOF
  if ! grep -q 'wiki/conventions.md' "$g/index.md"; then
    printf '\n## Conventions\n- [Conventions](wiki/conventions.md): Rules every session follows, in every project. How agents work with the user, and conventions for code.\n' >> "$g/index.md"
  fi
  echo "created: $(tilde "$f")"
}

init_collection() {
  mkdir -p "$WIKIS_DIR"
  write_collection_marker
  scaffold "$WIKIS_DIR/$SHARED" 0
  ensure_shared_conventions
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
    echo "git:     no commit name or email set yet, so nothing is committed. $WIKI_CMD setup git sets them."
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

# How to add the scan to someone else's pre-commit hook. The plugin's folder is
# deleted after an update, so from the plugin the advice is to copy, not to call.
hook_advice() {
  if from_plugin; then
    printf 'copy the lines of %s into it. Copy, because that folder is deleted after a plugin update.' "$(tilde "$HOOK_SRC")"
  else
    printf 'call %s from it.' "$(tilde "$HOOK_SRC")"
  fi
}

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
      echo "note:    git here uses core.hooksPath, so the secret scan wasn't installed. To add it to your pre-commit hook, $(hook_advice)"
      return 0
      ;;
    other)
      echo "note:    $(tilde "$dir") already has a pre-commit hook, left alone. To add the secret scan, $(hook_advice)"
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
  # The plugin's hook finds each session's wiki, and Claude Code reaches the plugin's own files.
  if from_plugin; then
    cat <<EOF

Next:
  1. Give Claude Code access to $(tilde "$WIKIS_DIR"), or approve the prompt the first time it reaches for it.
  2. Walk through the rest:             $WIKI_CMD setup
EOF
    return 0
  fi
  cat <<EOF

Next:
  1. Give your agent access to $(tilde "$WIKIS_DIR") and $(tilde "$REPO").
  2. Walk through the rest:             $WIKI_CMD setup
     Or just let sessions find wikis:   $WIKI_CMD claude
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
  [ -d "$WIKIS_DIR" ] || { echo "no wikis at $(tilde "$WIKIS_DIR"). Run: $WIKI_CMD init"; return 0; }
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
    if [ -n "$tv" ] && [ "${v:-0}" -lt "$tv" ]; then note="$note  <- behind template v$tv, run: $WIKI_CMD upgrade ${d##*/}"; fi
    # Someone upgraded a shared wiki with a newer template than this clone.
    if [ -n "$tv" ] && [ "${v:-0}" -gt "$tv" ]; then note="$note  <- ahead of your template v$tv, run: git -C $(tilde "$REPO") pull"; fi
    if [ -f "$d/repos.md" ] && grep -q '^- ' "$d/repos.md"; then
      note="$note  covers: $(sed -n 's/^- //p' "$d/repos.md" | tr '\n' ' ')"
    fi
    printf '%-26s %-9s %-8s %s%s\n' "${d##*/}" "v${v:-?}" "$waiting" "$lock" "$note"
  done
  [ "$found" = 1 ] || echo "(none yet. Run: $WIKI_CMD init)"
  if [ -f "$JOURNAL_CFG" ]; then
    echo "journal: $(journal_get enabled), commit $(journal_get commit), entries $(journal_get entries)"
  fi
  if [ -f "$DELEG_FILE" ]; then echo "delegation: mode $(deleg_mode)"; fi
  if from_plugin; then
    n="$(plugin_key)"
    [ "$(autoupdate_state "${n#*@}")" != off ] || echo "plugin:  auto-update is off, so fixes don't arrive. Run: $WIKI_CMD setup plugin"
  fi
  if in_git_repo "$WIKIS_DIR" && [ -f "$WIKIS_DIR/WIKIS.md" ]; then
    case "$(hook_state "$WIKIS_DIR")" in
      ours) command -v gitleaks >/dev/null 2>&1 || echo "secrets: commits aren't scanned, gitleaks isn't installed. Run: brew install gitleaks" ;;
      none) echo "secrets: commits aren't scanned. Run: $WIKI_CMD upgrade --all" ;;
      *) echo "secrets: another pre-commit hook is in place. To scan commits, $(hook_advice)" ;;
    esac
  fi
  n="$(TIP_REPO="$PWD" tips_due | wc -l | tr -d ' ')"
  [ "$n" -eq 0 ] || echo "tips:    $n feature(s) your wikis suggest trying. Run: $WIKI_CMD tips"
  n="$(setup_pending | wc -l | tr -d ' ')"
  if [ ! -f "$SETUP_STATE" ]; then
    echo "setup:   never run on this machine. Run: $WIKI_CMD setup"
  elif [ "$n" -gt 0 ]; then
    echo "setup:   $n new setting(s). Run: $WIKI_CMD setup --new"
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
  ensure_shared_conventions
  echo "== journal"
  write_journal_config
  apply_journal_commit
  echo "== delegation"
  write_delegation_file
  apply_delegation_ignore
  if [ -d "$HOME/.claude" ]; then
    echo "== skills"
    skills_link quiet
  fi
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

# upgrade_commit <names> <prefix>: commit what the upgrade changed in those wikis, so
# it can't sit uncommitted. Sessions upgrade on their own and were leaving it to the
# agent, which didn't always commit. Only files the handbook owns, and template files
# the upgrade added, go in: a wiki's own uncommitted notes and pages stay out. Pushing
# is left to the session, as for any wiki commit.
upgrade_commit() {
  local d f paths="" tv msg
  # Even with no wiki behind, an upgrade can change collection files, such as the
  # ignore rules, so this runs every time.
  in_git_repo "$WIKIS_DIR" || return 0
  tv="$(version_of "$TEMPLATE/AGENTS.md")"
  for d in $1; do
    for f in AGENTS.md CLAUDE.md rules .gitattributes .gitignore; do
      [ -e "$WIKIS_DIR/$d/$f" ] && paths="$paths $d/$f"
    done
    # Template files the upgrade created, such as patterns.md in an old wiki.
    while IFS= read -r f; do
      [ -n "$f" ] && paths="$paths $f"
    done < <(cd "$WIKIS_DIR" && (cd "$TEMPLATE" && find . -type f | sed "s#^\./#$d/#") | while IFS= read -r f; do
      [ -e "$f" ] && ! git ls-files --error-unmatch -- "$f" >/dev/null 2>&1 && printf '%s\n' "$f"
    done)
  done
  # Upgrades can add ignore rules for the journal, delegation and stats files.
  [ -f "$WIKIS_DIR/.gitignore" ] && paths="$paths .gitignore"
  # And the shared wiki's conventions page, when the upgrade created it.
  if [ -f "$WIKIS_DIR/$SHARED/wiki/conventions.md" ] && ! git -C "$WIKIS_DIR" ls-files --error-unmatch -- "$SHARED/wiki/conventions.md" >/dev/null 2>&1; then
    paths="$paths $SHARED/wiki/conventions.md $SHARED/index.md"
  fi
  # shellcheck disable=SC2086
  [ -n "$(cd "$WIKIS_DIR" && git status --porcelain -- $paths 2>/dev/null | head -n 1)" ] || return 0
  # shellcheck disable=SC2086
  if [ -n "$1" ]; then msg="wikis: handbook v$tv"; else msg="wikis: update collection files"; fi
  # shellcheck disable=SC2086
  if (cd "$WIKIS_DIR" && git add -- $paths && git commit -q -m "$msg" -- $paths) >/dev/null 2>&1; then
    echo "${2}Committed the upgrade as \"$msg\"."
    [ -z "$(git -C "$WIKIS_DIR" remote)" ] || echo "${2}Push it: git -C $(tilde "$WIKIS_DIR") push"
  else
    echo "${2}The upgrade isn't committed: git refused. Commit it yourself:"
    echo "    git -C $(tilde "$WIKIS_DIR") add${paths} && git -C $(tilde "$WIKIS_DIR") commit -m \"$msg\""
  fi
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
  upgrade_commit "$names" "- "
  if [ "$(claude_state)" = old ]; then
    echo "- Your Claude Code wiki line is out of date: $WIKI_CMD claude"
  fi
  if [ -n "$(setup_pending)" ]; then
    echo "- New settings to look at: $WIKI_CMD setup --new"
  fi
  echo "- Settings any time: $WIKI_CMD setup --list"
}

cmd_unlock() {
  local root="$1"
  is_wiki "$root" || die "$(tilde "$root") is not a wiki"
  printf 'free\n' > "$root/.compile-lock"
  echo "unlocked: $(tilde "$root")"
}

CLAUDE_FILE="$HOME/.claude/CLAUDE.md"

# This copy came with the Claude Code plugin. Its session hook does the line's job,
# and a line naming this folder would break when the plugin updates.
from_plugin() { case "$REPO" in "$HOME/.claude/plugins/"*) return 0 ;; esac; return 1; }

# claude_state: current, old (an older wiki line), or missing. With the plugin, current.
claude_state() {
  if from_plugin; then echo current; return 0; fi
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
  if from_plugin; then
    echo "This wiki.sh came with the llm-wiki Claude Code plugin. Its session hook finds each session's wiki, so no line is needed."
    return 0
  fi
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
keep_days|number|advanced|0|Delete day files older than this many days. 0 keeps everything.
max_commits|number|advanced|15|Commits listed per repository in a report, newest first. 0 lists them all. Detailed reports always list them all.'
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
    echo "# Work journal settings. Change them with: $WIKI_CMD journal set <key> <value>"
    echo "# or walk through them with: $WIKI_CMD setup journal"
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
  # Anchored with /: unanchored, it would also hide any folder called journal in a wiki.
  remove_line "$gi" "journal/"
  if [ "$(journal_get commit)" = yes ]; then
    remove_line "$gi" "/journal/"
    if git -C "$WIKIS_DIR" check-ignore -q journal/config 2>/dev/null; then
      echo "note:    another ignore rule still hides journal/. Check $(tilde "$gi")."
    fi
  else
    ensure_line "$gi" "/journal/"
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
    echo "no journal config yet. It is on by default: $WIKI_CMD journal on creates it."
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
  [ $# -ge 2 ] || die "usage: $WIKI_CMD journal note [--day DATE] [--at HH:MM] <project> <text>"
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
      --done)
        # The agent has written the entries. Removing the digest here, not with an
        # agent's rm, keeps a safety check from refusing it as destructive.
        rm -f "$JOURNAL_DIR/backfill.md"
        echo "removed: $(tilde "$JOURNAL_DIR/backfill.md")"
        return 0
        ;;
      *) die "backfill options: --since lastworkday|yesterday|week|lastweek|14d|DATE, --until DATE, --from DIR, --done" ;;
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
    set) [ $# -ge 1 ] || die "usage: $WIKI_CMD journal set <key> <value>"; journal_set "$1" "${2:-}" ;;
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
  local since="" until="" day="" fmt="" save="" only="" max="" arg
  while [ $# -gt 0 ]; do
    case "$1" in
      --since) since="${2:-}"; shift ;;
      --until) until="${2:-}"; shift ;;
      --day) day="${2:-}"; shift ;;
      --format) fmt="${2:-}"; shift ;;
      --only) only="${2:-}"; shift ;;
      --exclude) STANDUP_EXCLUDE="${STANDUP_EXCLUDE:+$STANDUP_EXCLUDE,}${2:-}"; shift ;;
      --save) save=yes ;;
      --max) max="${2:-}"; shift ;;
      *) die "standup options: --since X, --until DATE, --day DATE, --format standup|summary|detailed, --only GLOB, --exclude GLOB, --max N, --save" ;;
    esac
    shift
  done
  arg="${since:-$(journal_get since)}"
  since_ok "$arg" || die "--since takes lastworkday, yesterday, today, week, lastweek, a number of days like 7d, or a date"
  [ -z "$fmt" ] || case "$fmt" in standup | summary | detailed) ;; *) die "--format takes standup, summary, or detailed" ;; esac
  STANDUP_ONLY="$only"
  # A busy repository can list 50 commits a day, which costs tokens and buries the rest.
  [ -n "$max" ] || max="$(journal_get max_commits)"
  case "$max" in '' | *[!0-9]*) die "--max takes a number" ;; esac
  [ "${fmt:-$(journal_get format)}" != detailed ] || max=0

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
    # git compares to the second and this is to the minute, so end a minute ahead
    # or work from the last few seconds is left out.
    end_local="$(date -d '+1 minute' '+%Y-%m-%d %H:%M' 2>/dev/null || date -v+1M '+%Y-%m-%d %H:%M')"; end_label="now"
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
      --date=format-local:'%Y-%m-%d %H:%M' --format='- %cd %h %s' 2>/dev/null | awk '!seen[$0]++' || true)"
    if [ -n "$lines" ]; then
      local count
      count="$(printf '%s\n' "$lines" | wc -l | tr -d ' ')"
      n_repos=$((n_repos + 1)); n_commits=$((n_commits + count))
      { echo; echo "### $name"
        # Newest first, as git lists them.
        if [ "$max" -gt 0 ] && [ "$count" -gt "$max" ]; then
          printf '%s\n' "$lines" | head -n "$max"
          echo "- ($((count - max)) earlier commit(s) not listed)"
        else
          printf '%s\n' "$lines"
        fi; } >> "$out"
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

# ---- skills -----------------------------------------------------------------
# A skill that comes out of a pattern lives in the wiki that owns it, as
# <wiki>/skills/<name>/SKILL.md, so everyone who syncs the collection gets it and a
# fix reaches everyone. Claude Code finds skills in ~/.claude/skills, so `skills
# link` links each one there. Skills that didn't come from the wikis are left alone.
SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
TAB="$(printf '\t')"

# collection_skills: one line per skill, tab-separated: wiki, name, folder, link name.
# The link name is the skill's own, or wiki-name when two wikis use the same name.
collection_skills() {
  local d sk
  for d in "$WIKIS_DIR"/*/; do
    d="${d%/}"
    is_wiki "$d" || continue
    for sk in "$d"/skills/*/; do
      sk="${sk%/}"
      [ -f "$sk/SKILL.md" ] || continue
      printf '%s\t%s\t%s\n' "${d##*/}" "${sk##*/}" "$sk"
    done
  done | awk -F '\t' '{ line[NR] = $0; name[NR] = $2; seen[$2]++ }
    END { for (i = 1; i <= NR; i++) { split(line[i], f, "\t"); print line[i] "\t" (seen[name[i]] > 1 ? f[1] "-" f[2] : f[2]) } }'
}

# skill_description <folder>: the description line from SKILL.md's frontmatter.
skill_description() {
  sed -n '/^---$/,/^---$/s/^description: *//p' "$1/SKILL.md" | head -n 1 | cut -c 1-90
}

# skills_link [quiet]: link every collection skill into ~/.claude/skills, and remove
# links into the collection whose skill is gone or renamed. Prints what it changed.
skills_link() {
  local quiet="${1:-}" all wiki name src dest l target n=0
  all="$(collection_skills)"
  [ -n "$all" ] || [ -d "$SKILLS_DIR" ] || return 0
  mkdir -p "$SKILLS_DIR"
  while IFS="$TAB" read -r wiki name src dest; do
    [ -n "$dest" ] || continue
    if [ -L "$SKILLS_DIR/$dest" ] && [ "$SKILLS_DIR/$dest" -ef "$src" ]; then continue; fi
    if [ -e "$SKILLS_DIR/$dest" ] || [ -L "$SKILLS_DIR/$dest" ]; then
      case "$(readlink "$SKILLS_DIR/$dest" 2>/dev/null)" in
        "$WIKIS_DIR"/*) ;;
        *)
          [ -n "$quiet" ] || echo "skipped: $(tilde "$SKILLS_DIR/$dest") is a skill that didn't come from the wikis, so $wiki's $name isn't linked"
          continue
          ;;
      esac
    fi
    ln -sfn "$src" "$SKILLS_DIR/$dest"
    n=$((n + 1))
    echo "linked:  $dest (from $wiki)"
  done <<EOF
$all
EOF
  for l in "$SKILLS_DIR"/*; do
    [ -L "$l" ] || continue
    target="$(readlink "$l")"
    case "$target" in "$WIKIS_DIR"/*) ;; *) continue ;; esac
    if [ ! -f "$l/SKILL.md" ] || ! printf '%s\n' "$all" | cut -f 4 | grep -qxF -- "${l##*/}"; then
      rm "$l"
      echo "removed: ${l##*/} (no longer in the wikis)"
    fi
  done
  [ -n "$quiet" ] || [ "$n" -gt 0 ] || echo "nothing new to link"
}

# skills_unlinked: how many collection skills linking would add. A name already
# taken by a skill from elsewhere doesn't count: linking can't fix it.
skills_unlinked() {
  local wiki name src dest n=0
  while IFS="$TAB" read -r wiki name src dest; do
    [ -n "$dest" ] || continue
    [ "$SKILLS_DIR/$dest" -ef "$src" ] && continue
    if [ -e "$SKILLS_DIR/$dest" ]; then case "$(readlink "$SKILLS_DIR/$dest" 2>/dev/null)" in "$WIKIS_DIR"/*) ;; *) continue ;; esac; fi
    n=$((n + 1))
  done <<EOF
$(collection_skills)
EOF
  echo "$n"
}

cmd_skills() {
  local wiki name src dest state
  case "${1:-list}" in
    link) skills_link; return 0 ;;
    list) ;;
    *) die "skills commands: list, link" ;;
  esac
  if [ -z "$(collection_skills)" ]; then
    echo "No team skills yet. When a procedure keeps coming up, an agent proposes one, and it lands in <wiki>/skills/."
    return 0
  fi
  printf '%-22s %-26s %-9s %s\n' "WIKI" "SKILL" "LINKED" "DESCRIPTION"
  while IFS="$TAB" read -r wiki name src dest; do
    [ -n "$dest" ] || continue
    if [ "$SKILLS_DIR/$dest" -ef "$src" ]; then state=yes
    elif [ -e "$SKILLS_DIR/$dest" ] && ! case "$(readlink "$SKILLS_DIR/$dest" 2>/dev/null)" in "$WIKIS_DIR"/*) true ;; *) false ;; esac; then state=clash
    else state=no; fi
    printf '%-22s %-26s %-9s %s\n' "$wiki" "$dest" "$state" "$(skill_description "$src")"
  done <<EOF
$(collection_skills)
EOF
  [ "$(skills_unlinked)" -eq 0 ] || echo "Link them for Claude Code: $WIKI_CMD skills link"
}

# ---- tips -------------------------------------------------------------------
# Features nobody tries go unused. A tip points at something in this person's own
# records that a feature would help with, and only then. The session hook shows
# at most one per session, at a stopping point. A shown tip rests for two weeks, a
# muted one for good, and a tip whose feature has been used goes away.
TIPS_STATE="${XDG_CONFIG_HOME:-$HOME/.config}/llm-wiki/tips"
TIPS_COOLDOWN_DAYS=14
TIPS_ORDER="harvest seed share-skill standup backfill stats stale find delegation"

# tip_get <key>: the date recorded for used:<cmd>, shown:<tip> or muted:<tip>.
tip_get() { [ -f "$TIPS_STATE" ] && awk -v k="$1" '$1 == k { d = $2 } END { if (d) print d }' "$TIPS_STATE"; return 0; }

# tip_set <key>: record today's date for a key, replacing an older one.
tip_set() {
  local today tmp
  today="$(date -u +%Y-%m-%d)"
  mkdir -p "${TIPS_STATE%/*}"
  [ -f "$TIPS_STATE" ] || printf '# Commands used, and tips shown or muted, on this machine. Written by wiki.sh.\n' > "$TIPS_STATE"
  tmp="$TIPS_STATE.tmp"
  awk -v k="$1" -v d="$today" '$1 != k' "$TIPS_STATE" > "$tmp" && printf '%s %s\n' "$1" "$today" >> "$tmp" && mv "$tmp" "$TIPS_STATE"
}

# record_use <command> [sub]: note that a feature was used, so its tip stops.
record_use() {
  case "$1:${2:-}" in
    seed:* | standup:* | stats:* | find:* | stale:* | skills:* | delegation:*) tip_set "used:$1" ;;
    harvest:--dry-run) ;;
    harvest:*) tip_set "used:harvest" ;;
    report:--due) ;;
    report:*) tip_set "used:report" ;;
    journal:backfill) tip_set "used:backfill" ;;
  esac
  return 0
}

used() { [ -n "$(tip_get "used:$1")" ]; }

# Each check prints one line, the tip with its evidence, or nothing. Cheap: the
# session hook runs them. $TIP_REPO is the repository the session works in.
HARVEST_STAMP="${TIPS_STATE%/*}/harvested"

tip_harvest() {
  local n folders newer=()
  [ -d "$HOME/.claude/projects" ] || return 0
  # Memory notes never harvested, or changed since the last harvest, to the second.
  # The ${a[@]+...} form: bash 3.2 calls an empty array unbound under set -u.
  [ ! -f "$HARVEST_STAMP" ] || newer=(-newer "$HARVEST_STAMP")
  n="$(find "$HOME/.claude/projects" -path '*/memory/*.md' ! -name MEMORY.md ${newer[@]+"${newer[@]}"} 2>/dev/null | wc -l | tr -d ' ')"
  [ "$n" -gt 0 ] || return 0
  folders="$(find "$HOME/.claude/projects" -path '*/memory/*.md' ! -name MEMORY.md ${newer[@]+"${newer[@]}"} 2>/dev/null | sed 's#/memory/[^/]*$##' | sort -u | wc -l | tr -d ' ')"
  echo "Claude Code holds $n note(s) of its own memory, across $folders project folder(s), that no other repository sees: working rules, corrections, project facts. \`wiki harvest\` copies them into the wikis, where every repository and teammate gets them. \`wiki harvest --dry-run\` shows where each would go first."
}

tip_seed() {
  local top name w pages docs
  [ -n "${TIP_REPO:-}" ] || return 0
  top="$(git -C "$TIP_REPO" rev-parse --show-toplevel 2>/dev/null)" || return 0
  name="$(repo_name "$top")"
  w="$(which_wiki "$name")"
  if [ -n "$w" ]; then
    ls "$WIKIS_DIR/$w"/raw/*-seed-* >/dev/null 2>&1 && return 0
    pages="$(find "$WIKIS_DIR/$w/wiki" -name '*.md' ! -path '*/sources/*' 2>/dev/null | wc -l | tr -d ' ')"
    [ "$pages" -lt 3 ] || return 0
  fi
  docs="$(seed_candidates "$top" | wc -l | tr -d ' ')"
  [ "$docs" -ge 2 ] || return 0
  if [ -n "$w" ]; then
    echo "The $w wiki has only $pages page(s), but $name has $docs documents of its own, such as its README and agent instructions. \`wiki seed\`, run in the repository, copies them in to be compiled, so the wiki can answer questions about $name from day one."
  else
    echo "$name has no wiki yet, but it has $docs documents of its own, such as its README and agent instructions. \`wiki seed\`, run in the repository, starts its wiki from them."
  fi
}

tip_share_skill() {
  local d names="" n=0
  [ -d "$SKILLS_DIR" ] && [ -d "$WIKIS_DIR/$SHARED" ] || return 0
  for d in "$SKILLS_DIR"/*/; do
    d="${d%/}"
    [ -L "$d" ] && continue
    [ -f "$d/SKILL.md" ] || continue
    n=$((n + 1))
    [ "$n" -gt 3 ] || names="$names${names:+, }${d##*/}"
  done
  [ "$n" -gt 0 ] || return 0
  echo "$n skill(s) in ~/.claude/skills are only on this machine: $names$([ "$n" -le 3 ] || echo ", ..."). Moving one into ~/wikis/global/skills/ and running \`wiki skills link\` shares it with everyone who syncs the wikis, and keeps it working here."
}

tip_standup() {
  local n
  used standup && return 0
  [ "$(journal_get enabled)" = yes ] || return 0
  n="$(cat "$JOURNAL_DIR"/20[0-9][0-9]-[0-9][0-9]-[0-9][0-9].md 2>/dev/null | grep -c '^- ' || true)"
  [ "${n:-0}" -ge 3 ] || return 0
  echo "The journal holds $n entries, but no standup has been written from it yet. Asking \"give me my standup\" turns commits, journal entries and wiki notes into Yesterday, Today and Blockers."
}

tip_backfill() {
  local first older
  used backfill && return 0
  [ "$(journal_get enabled)" = yes ] && [ -d "$HOME/.claude/projects" ] || return 0
  first="$(ls "$JOURNAL_DIR"/20[0-9][0-9]-[0-9][0-9]-[0-9][0-9].md 2>/dev/null | head -n 1)"
  first="${first##*/}"
  first="${first%.md}"
  [ -z "$first" ] || [[ ! "$first" < "$(days_ago 14)" ]] || return 0
  older="$(find "$HOME/.claude/projects" -name '*.jsonl' -mtime +3 2>/dev/null | head -n 1)"
  [ -n "$older" ] || return 0
  echo "The journal ${first:+starts on $first}${first:-is empty}, but Claude Code kept transcripts of earlier sessions. \`wiki journal backfill --since 14d\` digests them, then \"backfill my journal\" fills in those days."
}

tip_stats() {
  local n first low
  [ -s "$STATS_FILE" ] || return 0
  [ -z "$(tip_get used:stats)" ] || [[ "$(tip_get used:stats)" < "$(days_ago 30)" ]] || return 0
  n="$(grep -c '^20' "$STATS_FILE" || true)"
  first="$(grep -m 1 '^20' "$STATS_FILE" | cut -d , -f 1)"
  [ "${n:-0}" -ge 20 ] && [[ "$first" < "$(days_ago 13)" ]] || return 0
  low="$(awk -F, '$1 ~ /^20/ { n[$2]++; if ($3 ~ /^hit/) h[$2]++ }
    END { for (w in n) if (n[w] >= 5 && h[w] / n[w] < 0.4) printf "%s (%d%%) ", w, 100 * h[w] / n[w] }' "$STATS_FILE")"
  echo "Sessions have logged $n wiki lookups since $first.${low:+ Some wikis rarely answer: ${low% }.} \`wiki stats\` shows each wiki's hit rate, so you can see which ones earn their keep."
}

tip_stale() {
  local d cutoff n=0 v
  [ -z "$(tip_get used:stale)" ] || [[ "$(tip_get used:stale)" < "$(days_ago 30)" ]] || return 0
  cutoff="$(days_ago 90)"
  for d in "$WIKIS_DIR"/*/wiki; do
    [ -d "$d" ] || continue
    while IFS= read -r v; do
      [[ "$v" < "$cutoff" ]] && n=$((n + 1))
    done < <(grep -rh --include='*.md' --exclude-dir=sources '^verified:' "$d" 2>/dev/null | sed 's/^verified: *//')
  done
  [ "$n" -ge 3 ] || return 0
  echo "$n wiki pages haven't been checked in over 90 days. \`wiki stale\` lists them, and \"re-verify the stale pages in <wiki>\" has an agent check them against the code."
}

tip_find() {
  local d n=0
  used find && return 0
  for d in "$WIKIS_DIR"/*/; do is_wiki "${d%/}" && n=$((n + 1)); done
  [ "$n" -ge 4 ] || return 0
  echo "There are $n wikis. \`wiki find <word>\` searches all their indexes at once, when you don't know which project knows about something."
}

tip_delegation() {
  used delegation && return 0
  [ "$(deleg_mode)" = ask ] && [ ! -s "$DELEG_LOG" ] || return 0
  [ -f "$WIKIS_DIR/WIKIS.md" ] && [ -n "$(find "$WIKIS_DIR/WIKIS.md" -mtime +7 2>/dev/null)" ] || return 0
  echo "No work has been handed to a cheaper model yet. Sessions can give test runs and file sweeps to a sub-agent on a cheaper model, and \`wiki setup delegation\` sets whether they ask first."
}

# tips_due [all|first]: "<id><TAB><tip>" lines for tips that apply. Without "all",
# only those not muted and not shown in the last two weeks. "first" stops at one.
tips_due() {
  local id text when
  [ -d "$WIKIS_DIR" ] || return 0
  for id in $TIPS_ORDER; do
    if [ "${1:-}" != all ]; then
      [ -z "$(tip_get "muted:$id")" ] || continue
      when="$(tip_get "shown:$id")"
      [ -z "$when" ] || [[ "$when" < "$(days_ago "$TIPS_COOLDOWN_DAYS")" ]] || continue
    fi
    text="$("tip_${id//-/_}" 2>/dev/null)"
    [ -n "$text" ] || continue
    printf '%s\t%s\n' "$id" "$text"
    [ "${1:-}" != first ] || break
  done
  return 0
}

# tips [--next] [--mute ID] [--unmute ID] [--repo DIR]
cmd_tips() {
  local mode=list id="" line text
  TIP_REPO="$PWD"
  while [ $# -gt 0 ]; do
    case "$1" in
      --next) mode=next; shift ;;
      --mute) mode=mute; id="${2:-}"; shift 2 ;;
      --unmute) mode=unmute; id="${2:-}"; shift 2 ;;
      --repo) TIP_REPO="${2:-}"; shift 2 ;;
      *) die "tips options: --next, --mute ID, --unmute ID, --repo DIR" ;;
    esac
  done
  case "$mode" in
    mute | unmute)
      case " $TIPS_ORDER " in *" $id "*) ;; *) die "no tip called $id. Tips: $TIPS_ORDER" ;; esac
      if [ "$mode" = mute ]; then
        tip_set "muted:$id"
        echo "tip $id muted. $WIKI_CMD tips --unmute $id brings it back."
      else
        [ ! -f "$TIPS_STATE" ] || { awk -v k="muted:$id" '$1 != k' "$TIPS_STATE" > "$TIPS_STATE.tmp" && mv "$TIPS_STATE.tmp" "$TIPS_STATE"; }
        echo "tip $id unmuted"
      fi
      ;;
    next)
      # For the session hook: one tip, recorded as shown.
      line="$(tips_due first)"
      [ -n "$line" ] || return 0
      tip_set "shown:${line%%$TAB*}"
      printf '%s\n' "$line"
      ;;
    list)
      line="$(tips_due all)"
      if [ -z "$line" ]; then echo "No tips right now: nothing in your wikis points at an unused feature."; return 0; fi
      while IFS="$TAB" read -r id text; do
        if [ -n "$(tip_get "muted:$id")" ]; then printf '%s (muted)\n' "$id"; else printf '%s\n' "$id"; fi
        printf '  %s\n\n' "$text"
      done <<EOF
$line
EOF
      echo "Mute one for good: $WIKI_CMD tips --mute <name>"
      ;;
  esac
}

# ---- completion -------------------------------------------------------------
# Tab completion. `completion zsh|bash` prints a small script for the shell, which
# asks `__complete` for candidates on every Tab. The candidates live here, so a
# plugin update can't leave completion stale.
COMMANDS="setup init new seed harvest capture lock log sync pending cover which status find stale patterns skills tips report stats delegation upgrade unlock claude link journal standup completion"
RANGES="lastworkday yesterday today week lastweek 7d 14d 30d"

wiki_names() {
  local d
  for d in "$WIKIS_DIR"/*/; do d="${d%/}"; is_wiki "$d" && printf '%s\n' "${d##*/}"; done
  return 0
}

# complete_choices <journal key>: the values a journal setting takes, if it's a choice.
complete_choices() {
  local type
  type="$(journal_field "$1" 2)"
  case "$type" in
    yesno) printf 'yes\nno\n' ;;
    since) printf '%s\n' $RANGES ;;
    */*) printf '%s\n' "${type//\//$'\n'}" ;;
  esac
}

# __complete <index> <word>...: candidates for the word at index (1 is the command).
cmd_complete() {
  local i="$1" k
  shift
  local cmd="${1:-}" prev=""
  [ "$i" -gt 1 ] && prev="$(eval "printf '%s' \"\${$((i - 1)):-}\"")"
  if [ "$i" -le 1 ]; then printf '%s\n' $COMMANDS; return 0; fi
  case "$prev" in
    --since) printf '%s\n' $RANGES; return 0 ;;
    --format) printf 'standup\nsummary\ndetailed\n'; return 0 ;;
    --mute | --unmute) printf '%s\n' $TIPS_ORDER; return 0 ;;
    --wiki) wiki_names; return 0 ;;
    --repo | --from) echo __dirs__; return 0 ;;
  esac
  case "$cmd" in
    new | unlock | pending | find) [ "$i" -eq 2 ] && wiki_names; [ "$cmd" = pending ] && echo --show ;;
    upgrade) wiki_names; echo --all ;;
    capture) [ "$i" -eq 2 ] && wiki_names; echo --copy ;;
    lock) [ "$i" -eq 2 ] && wiki_names; printf -- '--release\n--renew\n' ;;
    sync) [ "$i" -eq 2 ] && wiki_names; echo -m ;;
    log)
      if [ "$i" -eq 2 ]; then wiki_names
      elif [ "$i" -eq 3 ]; then printf 'ingest\nlint\nrestructure\nresolve\n'
      else printf -- '--created\n--updated\n--fixed\n--reported\n--corrections\n--conflicts\n--patterns\n'; fi
      ;;
    cover) [ "$i" -eq 2 ] && wiki_names ;;
    seed) [ "$i" -eq 2 ] && echo __dirs__; printf -- '--wiki\n--max\n--dry-run\n' ;;
    stale) printf '30\n90\n180\n' ;;
    skills) echo link ;;
    harvest) printf -- '--dry-run\n--from\n' ;;
    tips) printf -- '--mute\n--unmute\n' ;;
    report) printf -- '--since\n' ;;
    stats) printf '%s\n' $RANGES ;;
    delegation)
      if [ "$i" -eq 2 ]; then printf 'off\nask\nauto\nlog\n'
      elif [ "${2:-}" = log ] && [ "$i" -eq 6 ]; then printf 'ok\nfixed\nredone\n'; fi
      ;;
    claude) echo --print ;;
    link) echo --yes ;;
    init) echo --git ;;
    completion) printf 'zsh\nbash\n' ;;
    setup)
      printf -- '--new\n--list\ncollection\ngit\ngit.identity\nclaude\nplugin\nupgrade\nskills\ndelegation\njournal\n'
      for k in $JOURNAL_KEYS; do printf 'journal.%s\n' "$k"; done
      ;;
    journal)
      if [ "$i" -eq 2 ]; then printf 'show\non\noff\nset\nnote\nbackfill\npath\nprune\n'; return 0; fi
      case "${2:-}" in
        set) if [ "$i" -eq 3 ]; then printf '%s\n' $JOURNAL_KEYS; elif [ "$i" -eq 4 ]; then complete_choices "${3:-}"; fi ;;
        backfill) printf -- '--since\n--until\n--from\n' ;;
        note) printf -- '--day\n--at\n'; wiki_names ;;
      esac
      ;;
    standup) printf -- '--since\n--until\n--day\n--format\n--only\n--exclude\n--max\n--save\n' ;;
  esac
  return 0
}

cmd_completion() {
  case "${1:-}" in
    zsh)
      cat <<'EOF'
# Tab completion for llm-wiki's wiki command. Written by `wiki completion zsh`.
_llm_wiki() {
  local -a c
  c=("${(@f)$(${words[1]} __complete $((CURRENT - 1)) ${words[2,-1]} 2>/dev/null)}")
  if [[ "${c[1]}" == __dirs__ ]]; then _files -/; return; fi
  compadd -a c
}
(( $+functions[compdef] )) || { autoload -Uz compinit && compinit -i; }
compdef _llm_wiki wiki wiki.sh
EOF
      ;;
    bash)
      cat <<'EOF'
# Tab completion for llm-wiki's wiki command. Written by `wiki completion bash`.
_llm_wiki() {
  local cur="${COMP_WORDS[COMP_CWORD]}" out
  # Set IFS only after this: bash 3.2 joins "${COMP_WORDS[@]:1}" when IFS is a newline.
  out="$("${COMP_WORDS[0]}" __complete "$COMP_CWORD" "${COMP_WORDS[@]:1}" 2>/dev/null)"
  local IFS=$'\n'
  if [ "${out%%$'\n'*}" = __dirs__ ]; then COMPREPLY=($(compgen -d -- "$cur")); return; fi
  COMPREPLY=($(compgen -W "$out" -- "$cur"))
}
complete -F _llm_wiki wiki wiki.sh ./wiki.sh
EOF
      ;;
    *) die "completion takes zsh or bash" ;;
  esac
}

# The file a shell profile sources for completion. Rewritten on every setup, so
# it follows updates; the profile line never changes.
completion_file() { printf '%s/llm-wiki/completion.%s' "${XDG_CONFIG_HOME:-$HOME/.config}" "$1"; }

# completion_shell: zsh or bash, from $SHELL, or nothing.
completion_shell() { case "${SHELL##*/}" in zsh | bash) printf '%s' "${SHELL##*/}" ;; esac; return 0; }

# completion_on <shell>: the shell's profile loads llm-wiki's completion.
completion_on() { local prof; prof="$(completion_profile "$1")"; [ -f "$prof" ] && grep -qF "$(completion_file "$1")" "$prof"; }

completion_profile() { case "$1" in zsh) printf '%s' "$HOME/.zshrc" ;; bash) printf '%s' "$HOME/.bashrc" ;; esac; }

# Turn tab completion on: write the file, and source it from the profile.
setup_completion() {
  local sh f prof line
  sh="$(completion_shell)"
  [ -n "$sh" ] || return 0
  f="$(completion_file "$sh")"
  prof="$(completion_profile "$sh")"
  line="[ -f \"$f\" ] && source \"$f\""
  mkdir -p "${f%/*}"
  cmd_completion "$sh" > "$f"
  completion_on "$sh" && return 0
  [ "$SETUP_MODE" = new ] && setup_done completion.$sh && return 0
  section "Tab completion"
  echo "Tab completion fills in commands, wiki names and settings when you press Tab after wiki."
  if ask_yn "Turn it on? It adds one line to $(tilde "$prof")." y; then
    ensure_line "$prof" "$line"
    echo "  added. Open a new terminal to use it."
  fi
  setup_mark "completion.$sh"
}

# ---- report -----------------------------------------------------------------
# A weekly look at whether the wikis earn their keep, and what waits on a person.
# Tokens come from Claude Code's transcripts, which record each reply's usage.
# "Wiki reads" is an estimate: the size of what sessions read from the wikis, at
# about four characters a token. The agent writes the material up.

# report_tokens <start> <end>: the Tokens section, from transcripts.
report_tokens() {
  local from="$HOME/.claude/projects"
  if [ ! -d "$from" ] || ! command -v python3 >/dev/null 2>&1; then
    echo "No Claude Code transcripts on this machine${from:+ (or no python3)}, so no token counts."
    return 0
  fi
  python3 - "$from" "$1" "$2" "$(journal_get day_starts)" "$WIKIS_DIR" "$REPO" <<'PY'
import json, os, re, subprocess, sys
from datetime import datetime, timedelta, date
from pathlib import Path

sess_dir, start, end, day_starts, wikis, repo = sys.argv[1:7]
start = date.fromisoformat(start); end = date.fromisoformat(end)
dh, dm = (int(x) for x in day_starts.split(":"))
wikis_real = os.path.realpath(wikis)

cover = {}
for rp in Path(wikis).glob("*/repos.md"):
    for line in rp.read_text(errors="replace").splitlines():
        if line.startswith("- "):
            cover[line[2:].strip()] = rp.parent.name
known = set(cover) | set(cover.values()) | {d.name for d in Path(wikis).iterdir() if (d / "AGENTS.md").is_file()}
_proj = {}
def project(cwd):
    if not cwd: return None
    if cwd in _proj: return _proj[cwd]
    name = os.path.basename(cwd.rstrip("/")) or cwd
    if os.path.isdir(cwd):
        def git(*a):
            try: return subprocess.run(["git", "-C", cwd, *a], capture_output=True, text=True, timeout=5).stdout.strip()
            except Exception: return ""
        url = git("config", "--get", "remote.origin.url"); top = git("rev-parse", "--show-toplevel")
        if url: name = re.sub(r"\.git$", "", url.rstrip("/")).split("/")[-1].split(":")[-1]
        elif top: name = os.path.basename(top)
    if os.path.realpath(cwd) == wikis_real: name = "wikis"
    name = cover.get(name, name)
    # A scratch folder inside a project, such as politiboop/sweeps/b41, belongs to it.
    if name not in known and name != "wikis":
        name = next((x for x in reversed(Path(cwd).parts[:-1]) if x in known), None)
    _proj[cwd] = name
    return name

def is_wiki_path(p):
    return isinstance(p, str) and (os.path.realpath(os.path.expanduser(p)).startswith(wikis_real + os.sep))
def touches_wiki(use):
    inp = use.get("input") or {}
    for k in ("file_path", "notebook_path", "path"):
        if is_wiki_path(inp.get(k)): return True
    cmd = str(inp.get("command", ""))
    return wikis in cmd or wikis_real in cmd or "~/wikis" in cmd or "wiki.sh" in cmd or re.match(r"\s*wiki\s", cmd) is not None

def day_of(ts):
    t = datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone()
    return (t - timedelta(hours=dh, minutes=dm)).date()

cutoff = datetime.combine(start - timedelta(days=1), datetime.min.time()).timestamp()
rows = {}      # project -> counts
seen = set()   # message ids already counted
for f in Path(sess_dir).rglob("*.jsonl"):
    if f.stat().st_mtime < cutoff: continue
    wiki_uses = {}   # tool_use id -> project
    recs = []
    for line in open(f, errors="replace"):
        try: r = json.loads(line)
        except ValueError: continue
        if r.get("timestamp"): recs.append(r)
    # A session started in a stray folder counts toward the project it mostly ran in.
    counts = {}
    for r in recs:
        x = project(r.get("cwd"))
        if x: counts[x] = counts.get(x, 0) + 1
    main = max(counts, key=counts.get) if counts else None
    for r in recs:
        d = day_of(r["timestamp"])
        if d < start or d > end: continue
        p = project(r.get("cwd")) or main or "other folders"
        row = rows.setdefault(p, {"sessions": set(), "new": 0, "cached": 0, "out": 0, "wiki": 0})
        row["sessions"].add(r.get("sessionId", f.stem))
        msg = r.get("message") or {}
        u = msg.get("usage")
        mid = msg.get("id")
        if u and mid not in seen:
            seen.add(mid)
            row["new"] += u.get("input_tokens", 0) + u.get("cache_creation_input_tokens", 0)
            row["cached"] += u.get("cache_read_input_tokens", 0)
            row["out"] += u.get("output_tokens", 0)
        for c in msg.get("content") or []:
            if not isinstance(c, dict): continue
            if c.get("type") == "tool_use" and touches_wiki(c):
                wiki_uses[c.get("id")] = p
                row["wiki"] += len(json.dumps(c.get("input") or {})) // 4
            elif c.get("type") == "tool_result" and c.get("tool_use_id") in wiki_uses:
                body = c.get("content")
                if isinstance(body, list): body = " ".join(x.get("text", "") for x in body if isinstance(x, dict))
                rows[wiki_uses[c["tool_use_id"]]]["wiki"] += len(str(body or "")) // 4

rows = {p: r for p, r in rows.items() if r["new"] or r["out"]}
if not rows:
    print("No Claude Code sessions in this range."); sys.exit()
def k(n): return f"{n / 1e6:.1f}M" if n >= 1e6 else (f"{n / 1e3:.0f}k" if n >= 1e3 else str(n))
print("| Project | Sessions | New input | Cache reads | Output | Wiki reads (est.) |")
print("|---|---|---|---|---|---|")
tot = {"s": 0, "new": 0, "cached": 0, "out": 0, "wiki": 0}
for p, r in sorted(rows.items(), key=lambda x: -(x[1]["new"] + x[1]["cached"])):
    print(f"| {p} | {len(r['sessions'])} | {k(r['new'])} | {k(r['cached'])} | {k(r['out'])} | {k(r['wiki'])} |")
    tot["s"] += len(r["sessions"]); tot["new"] += r["new"]; tot["cached"] += r["cached"]; tot["out"] += r["out"]; tot["wiki"] += r["wiki"]
print(f"| all | {tot['s']} | {k(tot['new'])} | {k(tot['cached'])} | {k(tot['out'])} | {k(tot['wiki'])} |")
share = 100 * tot["wiki"] / tot["new"] if tot["new"] else 0
print(f"\nWiki reads are about {share:.1f}% of new input. New input is what entered a session's context for the first time; cache reads are that context read again on later turns.")
PY
}

# report_gains <start> <end>: per wiki, what was captured, compiled and added. Also
# sets REPORT_NOTES and REPORT_FEEDBACK, the range's notes and Feedback lines.
REPORT_NOTES=0
REPORT_FEEDBACK=0
report_gains() {
  local d notes line any=0 s="$1" e="$2" fb
  for d in "$WIKIS_DIR"/*/; do
    d="${d%/}"
    is_wiki "$d" || continue
    excluded "${d##*/}" && continue
    notes="$(ls "$d"/raw 2>/dev/null | awk -v s="$s" -v e="$e" '{ x = substr($0, 1, 10) } x >= s && x <= e' | wc -l | tr -d ' ' || true)"
    line="$(awk -v s="$s" -v e="$e" '
      /^## [0-9]{4}-[0-9]{2}-[0-9]{2} / { inr = ($2 >= s && $2 <= e); if (inr && $3 == "ingest:") ing++; if (inr && $3 == "lint") lint++; next }
      inr && /^- created: / && $3 !~ /^wiki\/sources\// { c++ }
      inr && /^- updated: / && $3 !~ /^wiki\/sources\// { u++ }
      END { printf "%d %d %d %d", ing, c, u, lint }' "$d/log.md" 2>/dev/null)"
    set -- $line
    fb="$(ls "$d"/raw 2>/dev/null | awk -v s="$s" -v e="$e" '{ x = substr($0, 1, 10) } x >= s && x <= e' | while IFS= read -r f; do grep -c '^Feedback:' "$d/raw/$f" 2>/dev/null || true; done | awk '{ n += $1 } END { print n + 0 }')"
    REPORT_NOTES=$((REPORT_NOTES + notes))
    REPORT_FEEDBACK=$((REPORT_FEEDBACK + fb))
    local skills
    skills=0
    [ ! -d "$d/skills" ] || skills="$(find "$d/skills" -name SKILL.md -newermt "$s" 2>/dev/null | wc -l | tr -d ' ')"
    [ "$notes$1$2$3$4$skills" != "000000" ] || continue
    any=1
    printf -- '- %s: %s note(s) captured, %s compiled, pages %s created and %s updated%s%s\n' "${d##*/}" "$notes" "${1:-0}" "${2:-0}" "${3:-0}" \
      "$([ "${4:-0}" -gt 0 ] && echo ", ${4} lint run(s)")" "$([ "$skills" -gt 0 ] && echo ", $skills skill(s) added or changed")"
  done
  [ "$any" = 1 ] || echo "Nothing captured or compiled in this range."
  echo "- Corrections recorded as Feedback lines: $REPORT_FEEDBACK, in $REPORT_NOTES note(s)."
}

# report_lookups <start> <end>: hit rate per wiki, from stats.csv.
report_lookups() {
  if [ ! -s "$STATS_FILE" ]; then echo "No lookups logged. Sessions on handbook v16 or later log them."; return 0; fi
  awk -F, -v s="$1" -v e="$2" '
    $1 ~ /^20/ && $1 >= s && $1 <= e && NF >= 3 { n[$2]++; if ($3 ~ /^hit/) h[$2]++; t++; ht += ($3 ~ /^hit/) }
    END {
      if (!t) { print "No lookups logged in this range."; exit }
      for (w in n) printf "- %s: %d lookup(s), %d%% answered\n", w, n[w], 100 * h[w] / n[w]
      printf "- all: %d lookup(s), %d%% answered\n", t, 100 * ht / t
    }' "$STATS_FILE"
}

# report_needs_you: what waits on a person, whatever the range.
report_needs_you() {
  local d n lines any=0 tv v cutoff stale=0 muted
  tv="$(version_of "$TEMPLATE/AGENTS.md")"
  cutoff="$(days_ago 90)"
  for d in "$WIKIS_DIR"/*/; do
    d="${d%/}"
    is_wiki "$d" || continue
    excluded "${d##*/}" && continue
    lines="$(grep -rhE '^> \*\*(Check|Conflict):\*\*' "$d/wiki" 2>/dev/null | head -n 3 | sed 's/^> //' || true)"
    if [ -n "$lines" ]; then any=1; printf '%s\n' "$lines" | sed "s/^/- ${d##*/}: open /"; fi
    lines="$(awk '/^## /{ name = substr($0, 4) } /^- status: proposed/{ print name }' "$d/patterns.md" 2>/dev/null || true)"
    if [ -n "$lines" ]; then any=1; printf '%s\n' "$lines" | sed "s/^/- ${d##*/}: a proposed fix still waits for an answer: /"; fi
    n="$(patterns_ledger "$d" | grep -c '^ready|' || true)"
    if [ "${n:-0}" -gt 0 ]; then any=1; echo "- ${d##*/}: $n repeated pattern(s) ready for a fix. wiki patterns lists them."; fi
    n="$(pending_files "$d" | wc -l | tr -d ' ')"
    if [ "$n" -gt 10 ]; then any=1; echo "- ${d##*/}: $n notes waiting to be compiled."; fi
    v="$(version_of "$d/AGENTS.md")"
    if [ -n "$tv" ] && [ "${v:-0}" -lt "$tv" ]; then any=1; echo "- ${d##*/}: handbook v${v:-?}, behind v$tv."; fi
    while IFS= read -r v; do
      [[ "$v" < "$cutoff" ]] && stale=$((stale + 1))
    done < <(grep -rh --include='*.md' --exclude-dir=sources '^verified:' "$d/wiki" 2>/dev/null | sed 's/^verified: *//' || true)
  done
  if [ "$stale" -gt 0 ]; then any=1; echo "- $stale page(s) not checked in over 90 days. wiki stale lists them."; fi
  muted="$( [ ! -f "$TIPS_STATE" ] || awk '$1 ~ /^muted:/ { sub(/^muted:/, "", $1); printf "%s ", $1 }' "$TIPS_STATE")"
  if [ -n "$muted" ]; then any=1; echo "- Muted tips: ${muted% }. If everyone mutes one, it may not be worth keeping."; fi
  # A busy week with no corrections recorded usually means they went somewhere else.
  if [ "$REPORT_FEEDBACK" -eq 0 ] && [ "$REPORT_NOTES" -ge 10 ]; then
    any=1
    echo "- No corrections were recorded this week, across $REPORT_NOTES notes. If you corrected an agent, the correction may have gone to its own memory instead of the wiki, where no other repository sees it."
  fi
  [ "$any" = 1 ] || echo "Nothing."
}

# report [--since RANGE] [--due]
cmd_report() {
  local since=7d today start due=0 w
  while [ $# -gt 0 ]; do
    case "$1" in
      --since) since="${2:-}"; shift 2 ;;
      --due) due=1; shift ;;
      *) die "report options: --since lastworkday|week|lastweek|7d|DATE, --due" ;;
    esac
  done
  if [ "$due" = 1 ]; then
    # For the session hook: due once a week, once the collection is a week old.
    [ -f "$WIKIS_DIR/WIKIS.md" ] && [ -n "$(find "$WIKIS_DIR/WIKIS.md" -mtime +6 2>/dev/null)" ] || return 0
    for w in used:report shown:report; do
      [ -z "$(tip_get "$w")" ] || [[ "$(tip_get "$w")" < "$(days_ago 6)" ]] || return 0
    done
    tip_set shown:report
    echo due
    return 0
  fi
  since_ok "$since" || die "--since takes lastworkday, yesterday, today, week, lastweek, a number of days like 7d, or a date"
  today="$(journal_today)"
  start="$(since_to_date "$today" "$since")"
  echo "# Wiki report: $start to $today"
  echo
  echo "Agents: write this up in the user's usual reply style, outcomes first, leading with Needs you if it has anything. Don't paste the tables. If they prefer short replies, give Needs you and a line of totals, and offer the rest."
  echo
  echo "## Tokens (Claude Code)"
  echo
  report_tokens "$start" "$today"
  echo
  echo "## What the wikis gained"
  echo
  report_gains "$start" "$today"
  echo
  echo "## Lookups"
  echo
  report_lookups "$start" "$today"
  echo
  echo "## Needs you"
  echo
  report_needs_you
}

# ---- stats ------------------------------------------------------------------
# Agents log each wiki lookup to stats.csv in the collection: date,wiki,hit|miss.
# A hit means the pages answered at least part of the question. stats sums it, so
# you can tell whether a wiki earns its keep.
STATS_FILE="$WIKIS_DIR/stats.csv"

cmd_stats() {
  local since="${1:-30d}" from
  since_ok "$since" || die "stats takes a range: lastworkday, yesterday, today, week, lastweek, a number of days like 30d, or a date"
  if [ ! -s "$STATS_FILE" ]; then
    echo "No lookups logged yet. Sessions on handbook v16 or later log one line per question they check a wiki for."
    return 0
  fi
  from="$(since_to_date "$(journal_today)" "$since")"
  echo "Wiki lookups since $from"
  awk -F, -v from="$from" '
    NR == 1 && $1 == "date" { next }
    $1 >= from && NF >= 3 { n[$2]++; if ($3 ~ /^hit/) h[$2]++; total++; hits += ($3 ~ /^hit/) }
    END {
      if (!total) { print "  none in this range"; exit }
      printf "%-26s %7s %5s %6s %6s\n", "WIKI", "LOOKUPS", "HITS", "MISSES", "RATE"
      for (w in n) printf "%-26s %7d %5d %6d %5.0f%%\n", w, n[w], h[w], n[w] - h[w], 100 * h[w] / n[w]
      printf "%-26s %7d %5d %6d %5.0f%%\n", "all", total, hits, total - hits, 100 * hits / total
    }' "$STATS_FILE"
  echo "A wiki that keeps missing may be missing pages, or may not be worth keeping."
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

How sessions hand work to sub-agents on cheaper models. This file is yours alone: git ignores it, so it never reaches coworkers or your other machines. Edit it freely. Agents read it and follow `rules/delegation.md` in any wiki. Change the mode with `wiki.sh setup delegation`.

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

# The preferences, the handoff log and the lookup stats are one person's, so they
# stay on this machine. In a shared collection, coworkers would otherwise overwrite them.
apply_delegation_ignore() {
  local f
  in_git_repo "$WIKIS_DIR" || return 0
  # Anchored with /, so they match only at the top of the collection. Unanchored,
  # delegation.md also hid every wiki's rules/delegation.md, which belongs in git.
  for f in delegation.md delegation-log.csv stats.csv; do
    remove_line "$WIKIS_DIR/.gitignore" "$f"
    ensure_line "$WIKIS_DIR/.gitignore" "/$f"
  done
  if [ -n "$(git -C "$WIKIS_DIR" ls-files delegation.md delegation-log.csv 2>/dev/null)" ]; then
    echo "note:    delegation files are tracked from before. To keep them on this machine only: git -C $(tilde "$WIKIS_DIR") rm --cached delegation.md delegation-log.csv"
  fi
}

# deleg_log <kind> <model> <effort> <ok|fixed|redone> [--project NAME]: one handoff.
deleg_log() {
  local project="" top
  [ $# -ge 4 ] || die "usage: $WIKI_CMD delegation log <kind> <model> <effort> <ok|fixed|redone> [--project NAME]"
  local kind="$1" model="$2" effort="$3" result="$4"
  shift 4
  [ "${1:-}" != --project ] || project="${2:-}"
  case "$result" in ok | fixed | redone) ;; *) die "the result is ok, fixed or redone" ;; esac
  case "$kind$model$effort$project" in *,*) die "no commas: the log is CSV" ;; esac
  if [ -z "$project" ]; then
    top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    if [ -n "$top" ]; then project="$(repo_name "$top")"; else project=-; fi
  fi
  [ -s "$DELEG_LOG" ] || printf 'date,project,kind,model,effort,result\n' > "$DELEG_LOG"
  printf '%s,%s,%s,%s,%s,%s\n' "$(date -u +%Y-%m-%d)" "$project" "$kind" "$model" "$effort" "$result" >> "$DELEG_LOG"
  echo "logged: $kind on $model ($effort), $result, for $project"
}

cmd_delegation() {
  case "${1:-show}" in
    off | ask | auto) deleg_set_mode "$1"; return 0 ;;
    log) shift; deleg_log "$@"; return 0 ;;
    show) ;;
    *) die "delegation commands: show, off, ask, auto, log" ;;
  esac
  if [ ! -f "$DELEG_FILE" ]; then
    echo "no $(tilde "$DELEG_FILE") yet. Mode is ask by default. $WIKI_CMD setup delegation creates it."
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

# ---- plugin -----------------------------------------------------------------
# From the plugin, setup also does the fiddly parts of installing: it puts `wiki`
# on the PATH, turns on auto-update, and removes the old CLAUDE.md line. Then a
# new person's install is two commands, one session, and `wiki setup`.

# plugin_key: plugin@marketplace for this copy, from its folder in the plugin cache.
plugin_key() {
  local d="${REPO%/*}"
  printf '%s@%s' "${d##*/}" "$(basename "${d%/*}")"
}

# The command the session hook writes, in the plugin's data folder. Its path
# doesn't change between versions. The command itself says where it is.
plugin_cmd() {
  local k
  k="$(plugin_key)"
  printf '%s' "${LLM_WIKI_SHIM:-$HOME/.claude/plugins/data/${k%@*}-${k#*@}/bin/wiki}"
}

# wiki_linked: `wiki` on the PATH is the plugin's command.
wiki_linked() {
  local cur
  cur="$(command -v wiki 2>/dev/null || true)"
  [ -n "$cur" ] && [ "$cur" -ef "$(plugin_cmd)" ]
}

# link_dir: a writable folder already on the PATH for the command, best first.
link_dir() {
  local d
  for d in "$HOME/.local/bin" "$HOME/bin" /opt/homebrew/bin /usr/local/bin; do
    case ":$PATH:" in *":$d:"*) [ -d "$d" ] && [ -w "$d" ] && { printf '%s' "$d"; return 0; } ;; esac
  done
  return 0
}

# link [--yes]: make `wiki` a command in every new terminal.
# The messages name ~/.local/bin literally, as people type it.
# shellcheck disable=SC2088
cmd_link() {
  local cmd cur dir profile line
  from_plugin || die "link is for the plugin's wiki command. From a clone: ln -s $(tilde "$REPO")/wiki.sh ~/.local/bin/wiki"
  cmd="$(plugin_cmd)"
  [ -x "$cmd" ] || die "the plugin hasn't written its wiki command yet. Start a Claude Code session once, then rerun this."
  if wiki_linked; then echo "wiki: already a command"; return 0; fi
  cur="$(command -v wiki 2>/dev/null || true)"
  # An older link of ours, such as one into a clone, can be replaced. Anything else is someone else's.
  if [ -n "$cur" ] && ! [ -L "$cur" ]; then
    die "$(tilde "$cur") is already a command called wiki and isn't a link, so it's left alone. Run the plugin's as $(tilde "$cmd")"
  fi
  dir="${cur%/*}"
  [ -n "$cur" ] || dir="$(link_dir)"
  if [ -n "$dir" ]; then
    ln -sf "$cmd" "$dir/wiki"
    echo "wiki: linked $(tilde "$dir/wiki")"
    return 0
  fi
  # No writable folder on the PATH: use ~/.local/bin and add it to the PATH.
  mkdir -p "$HOME/.local/bin"
  ln -sf "$cmd" "$HOME/.local/bin/wiki"
  line='export PATH="$HOME/.local/bin:$PATH"'
  case "${SHELL##*/}" in
    zsh) profile="$HOME/.zshrc" ;;
    bash) profile="$HOME/.bash_profile" ;;
    *) profile="" ;;
  esac
  if [ -n "$profile" ] && { [ "${1:-}" = --yes ] || { [ -t 0 ] && ask_yn "~/.local/bin isn't on your PATH. Add it in $(tilde "$profile")?" y; }; }; then
    ensure_line "$profile" "$line"
    echo "wiki: linked ~/.local/bin/wiki and added it to your PATH in $(tilde "$profile"). Open a new terminal to use it."
  else
    echo "wiki: linked ~/.local/bin/wiki, which isn't on your PATH yet. Add this line to your shell profile, then open a new terminal:"
    echo "  $line"
    [ -t 0 ] || [ -z "$profile" ] || echo "Or run: $(tilde "$cmd") link --yes"
  fi
}

# autoupdate_state <marketplace>: on, off, or unknown.
autoupdate_state() {
  [ -f "$HOME/.claude/settings.json" ] && command -v python3 >/dev/null 2>&1 || { echo unknown; return 0; }
  python3 - "$HOME/.claude/settings.json" "$1" 2>/dev/null <<'PY' || echo unknown
import json, sys
m = json.load(open(sys.argv[1])).get("extraKnownMarketplaces", {}).get(sys.argv[2])
print("unknown" if m is None else ("on" if m.get("autoUpdate") is True else "off"))
PY
}

# autoupdate_on <marketplace>: set autoUpdate in ~/.claude/settings.json, keeping a backup.
autoupdate_on() {
  local f="$HOME/.claude/settings.json"
  cp "$f" "$f.bak" || return 1
  python3 - "$f" "$1" <<'PY'
import json, sys
path, name = sys.argv[1], sys.argv[2]
s = json.load(open(path))
s["extraKnownMarketplaces"][name]["autoUpdate"] = True
with open(path, "w") as f:
    json.dump(s, f, indent=2)
    f.write("\n")
PY
}

# plugin_pending: the plugin step has something to ask.
plugin_pending() {
  local k
  from_plugin || return 1
  k="$(plugin_key)"
  { ! wiki_linked && ! [ "$HOME/.local/bin/wiki" -ef "$(plugin_cmd)" ]; } || [ "$(autoupdate_state "${k#*@}")" = off ] || old_claude_line
}

# Lines in CLAUDE.md from before the plugin. The plugin's hook does their job.
old_claude_line() { from_plugin && [ -f "$CLAUDE_FILE" ] && grep -q "knowledge wikis live in" "$CLAUDE_FILE"; }

setup_plugin() {
  local mkt
  from_plugin || return 0
  mkt="$(plugin_key)"
  mkt="${mkt#*@}"
  if [ "$SETUP_MODE" = new ] && ! plugin_pending; then return 0; fi
  section "Claude Code plugin"
  if wiki_linked; then
    echo "wiki is a command in every terminal."
  elif [ "$HOME/.local/bin/wiki" -ef "$(plugin_cmd)" ]; then
    echo "wiki is linked in ~/.local/bin. Open a new terminal to type it as plain wiki."
  else
    echo "The wiki command isn't on your PATH yet, so for now you run it as $(tilde "$(plugin_cmd)")."
    if ask_yn "Make it plain wiki?" y; then cmd_link | sed 's/^/  /'; fi
  fi
  case "$(autoupdate_state "$mkt")" in
    on) echo "Auto-update is on, so fixes arrive on their own." ;;
    off)
      echo "Auto-update is off for the $mkt marketplace, so you'd get no fixes. Claude Code starts other marketplaces with it off."
      if ask_yn "Turn it on?" y; then
        if autoupdate_on "$mkt"; then echo "  turned on, in ~/.claude/settings.json (backup beside it)"; else echo "  couldn't change ~/.claude/settings.json. Use /plugin in a terminal session instead."; fi
      fi
      ;;
    *) echo "Couldn't tell whether auto-update is on. Check with /plugin in a terminal Claude Code session." ;;
  esac
  if old_claude_line; then
    echo "$(tilde "$CLAUDE_FILE") still has the wiki line from before the plugin. The plugin does its job, and both would point sessions at the handbook twice."
    if ask_yn "Remove it?" y; then
      cp "$CLAUDE_FILE" "$CLAUDE_FILE.bak"
      remove_line "$CLAUDE_FILE" "$(grep -m 1 "knowledge wikis live in" "$CLAUDE_FILE")"
      echo "  removed (backup beside it)"
    fi
  fi
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
  [ -f "$SETUP_STATE" ] || printf '# Setup questions answered on this machine. Written by $WIKI_CMD setup.\n' > "$SETUP_STATE"
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
  # Tab completion, asked once per machine unless the profile already loads it.
  local sh
  sh="$(completion_shell)"
  if [ -n "$sh" ] && ! completion_on "$sh"; then setup_done "completion.$sh" || echo "completion.$sh"; fi
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
  # The gitleaks note is left out here: the question below covers it.
  install_hook "$WIKIS_DIR" | { grep -v 'gitleaks isn' || true; } | sed 's/^/  /'
  if ! command -v gitleaks >/dev/null 2>&1; then
    echo "gitleaks isn't installed, so commits aren't checked for secrets."
    if command -v brew >/dev/null 2>&1; then
      if ask_yn "Install it with Homebrew?" y; then brew install gitleaks </dev/null 2>&1 | tail -n 1 | sed 's/^/  /'; fi
    else
      echo "  Install it from https://github.com/gitleaks/gitleaks, then commits are checked."
    fi
  fi
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
      # Most people need no key here: their normal SSH setup already works, and naming
      # a key bypasses ~/.ssh/config, which can be what makes it work (a passphrase in
      # the keychain, a port-443 host). So try the normal setup first.
      if [ -z "$key" ] && GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=10" \
        git -C "$WIKIS_DIR" ls-remote origin >/dev/null 2>&1; then
        echo "Your normal SSH setup reaches $url, so this repo needs no key of its own."
        setup_mark git.identity
        return 0
      fi
      echo "If your usual SSH key belongs to another account, name the key for this repo."
      echo "It is used alone, without ~/.ssh/config, so host aliases there don't apply here."
      echo "If your normal SSH works for this host, answer - instead."
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
    push_advice "$err" "$url" | sed 's/^/  /'
    echo "  Then run the test again: $WIKI_CMD setup git.identity"
  fi
}

# push_advice <git error> <remote url>: what the failure means, and the fix.
push_advice() {
  local err="$1" url="$2" host
  # git@host:path, ssh://git@host[:port]/path or https://host/path: just the host.
  host="$(printf '%s' "$url" | sed -E 's#^[a-z+]+://##; s#^[^@/]*@##; s#[:/].*##')"
  case "$err" in
    *"could not read Username"* | *"Authentication failed"* | *"terminal prompts disabled"*)
      echo "The remote is an https URL, which signs in with a password or token, not an SSH key."
      echo "Switch it to SSH: git -C $(tilde "$WIKIS_DIR") remote set-url origin git@$host:<group>/<repo>.git"
      ;;
    *"Permission denied (publickey)"*)
      echo "$host didn't accept the key. It may not be added to your account there, or it has a passphrase"
      echo "that isn't loaded. Load it once with: ssh-add --apple-use-keychain <key>"
      echo "If your normal SSH works for $host (ssh -T git@$host), answer - at the key question instead."
      ;;
    *"Host key verification failed"*)
      echo "ssh hasn't seen $host before. Run ssh -T git@$host once and answer yes."
      ;;
    *"timed out"* | *"Could not resolve hostname"* | *"Connection refused"*)
      echo "Couldn't reach $host. Networks that block port 22 need SSH over port 443 in ~/.ssh/config:"
      echo "GitLab uses altssh.gitlab.com, GitHub uses ssh.github.com. Then answer - at the key question,"
      echo "so that config is used."
      ;;
    *"not found"* | *"does not appear to be a git repository"* | *"not exist"*)
      echo "The repository isn't at that address, or this account can't see it. Check the URL,"
      echo "and that the project exists: git -C $(tilde "$WIKIS_DIR") remote -v"
      ;;
    *) echo "Check the key and the remote: git -C $(tilde "$WIKIS_DIR") remote -v" ;;
  esac
}

setup_claude() {
  local state
  state="$(claude_state)"
  [ "$SETUP_MODE" = new ] && [ "$state" = current ] && return 0
  from_plugin && return 0
  section "Claude Code"
  # The plugin step covers Claude Code: the hook does this job.
  from_plugin && return 0
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
    upgrade_commit "$behind" ""
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

# Team skills from the wikis, linked for Claude Code. A check: quiet when nothing is new.
setup_skills() {
  local n
  [ -d "$HOME/.claude" ] || return 0
  n="$(skills_unlinked)"
  [ "$n" -gt 0 ] || return 0
  section "Team skills"
  echo "The wikis hold $n skill(s) that Claude Code can't see yet. Linking puts them in $(tilde "$SKILLS_DIR")."
  if ask_yn "Link them?" y; then skills_link quiet | sed 's/^/  /'; fi
}

setup_journal() {
  local k due="" adv=""
  for k in $JOURNAL_KEYS; do
    if setup_due "journal.$k"; then due="$due $k"; fi
  done
  [ -n "$due" ] || return 0
  section "Work journal"
  write_journal_config | sed 's/^/  /'
  echo "Agents note work that leaves no commit, and $WIKI_CMD standup turns your day into a report."
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
  if [ -n "$(completion_shell)" ]; then
    printf '%-19s %s' "completion" "$(completion_on "$(completion_shell)" && echo "on ($(completion_shell))" || echo off)"
    case "$pending" in *" completion."*) printf '  <- new' ;; esac
    printf '\n'
  fi
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
  echo "Change one:    $WIKI_CMD setup journal.<key>   or   $WIKI_CMD setup git.identity"
  echo "Or a section:  $WIKI_CMD setup git | plugin | claude | upgrade | skills | completion | delegation | journal"
}

cmd_setup() {
  local what="" a n
  for a in "$@"; do
    case "$a" in
      --new) SETUP_MODE=new ;;
      --list) setup_list; return 0 ;;
      -h | --help)
        cat <<EOF
Usage: $WIKI_CMD setup [--new | --list | <section> | <setting>]

  setup            Walk through every setting. Enter keeps what you have.
  setup --new      Only what's missing, out of date, or added since you last ran it.
  setup --list     Print current values without asking anything.
  setup <section>  Just one section: collection, git, claude, upgrade, delegation, journal.
  setup <setting>  Just one setting: git.identity, or journal.<key> such as journal.format.
                   A bare journal key works too: setup format.
EOF
        return 0
        ;;
      collection | git | claude | plugin | upgrade | skills | completion | journal | delegation | git.identity) what="$a" ;;
      journal.*)
        [ -n "$(journal_field "${a#journal.}" 2)" ] || die "no journal setting called ${a#journal.}. Settings: $JOURNAL_KEYS"
        what="$a"
        ;;
      *)
        # A bare journal key works too: setup format
        if [ -n "$(journal_field "$a" 2)" ]; then what="journal.$a"; else
          die "setup: unknown option $a. Try $WIKI_CMD setup --help"
        fi
        ;;
    esac
  done
  [ -t 0 ] || die "setup asks questions, so it needs a terminal. $WIKI_CMD setup --list prints the current values."
  if [ "$SETUP_MODE" = new ] && [ -d "$WIKIS_DIR" ] && [ "$(claude_state)" = current ] && ! plugin_pending; then
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
      in_git_repo "$WIKIS_DIR" || die "$(tilde "$WIKIS_DIR") isn't a git repo yet. Run: $WIKI_CMD setup git"
      setup_identity
      setup_push_check
      ;;
    journal.*)
      write_journal_config | sed 's/^/  /'
      setup_journal_key "${what#journal.}"
      ;;
    plugin) SETUP_MODE=all; setup_plugin ;;
    skills) setup_skills ;;
    completion) SETUP_MODE=all; setup_completion ;;
    '')
      setup_plugin
      setup_collection
      setup_git
      setup_claude
      setup_upgrade
      setup_delegation
      setup_skills
      setup_completion
      setup_journal
      ;;
  esac
  case "$what" in
    *.*) return 0 ;;
  esac
  echo
  if from_plugin; then
    echo "Done. After a plugin update, $WIKI_CMD setup --new shows what's new."
  else
    echo "Done. After you pull template updates, $WIKI_CMD setup --new shows what's new."
  fi
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
record_use "$cmd" "${1:-}"
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
if [ "$cmd" = __push-advice ]; then
  # For tests: the advice for a push-test error, without running setup.
  push_advice "${1:-}" "${2:-}"
  exit 0
fi
if [ "$cmd" = __complete ]; then
  cmd_complete "$@"
  exit 0
fi
if [ "$cmd" = completion ]; then
  cmd_completion "$@"
  exit 0
fi
if [ "$cmd" = tips ]; then
  cmd_tips "$@"
  exit 0
fi
if [ "$cmd" = report ]; then
  cmd_report "$@"
  exit 0
fi
case "$cmd" in
  capture) cmd_capture "$@"; exit 0 ;;
  lock) cmd_lock "$@"; exit 0 ;;
  log) cmd_log "$@"; exit 0 ;;
  sync) cmd_sync "$@"; exit 0 ;;
esac
if [ "$cmd" = harvest ]; then
  cmd_harvest "$@"
  exit 0
fi
if [ "$cmd" = pending ]; then
  cmd_pending "$@"
  exit 0
fi
if [ "$cmd" = seed ]; then
  cmd_seed "$@"
  exit 0
fi
if [ "$cmd" = cover ]; then
  [ $# -ge 2 ] || die "usage: $WIKI_CMD cover <wiki> <repo>..."
  cmd_cover "$@"
  exit 0
fi
want_git=0
want_all=0
want_print=0
want_yes=0
target=""
for arg in "$@"; do
  case "$arg" in
    --git) want_git=1 ;;
    --all) want_all=1 ;;
    --print) want_print=1 ;;
    --yes) want_yes=1 ;;
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
  claude) if [ "$want_print" = 1 ]; then claude_line; printf '\n'; else cmd_claude; fi ;;
  patterns) cmd_patterns ;;
  link) cmd_link "$( [ "$want_yes" = 1 ] && echo --yes)" ;;
  stats) cmd_stats "${target:-30d}" ;;
  skills) cmd_skills "${target:-list}" ;;
  -h | --help | help) usage ;;
  *) usage; exit 1 ;;
esac
