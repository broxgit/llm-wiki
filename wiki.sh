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
  cover <wiki> <repo>...  Record that one wiki covers several repositories.
  which <repo>         Print the wiki that covers a repository.
  status               List wikis: handbook version, notes waiting, lock state.
  find <word>          Search every wiki's index for a word.
  stale [days]         List pages not verified in that many days (default 90).
  upgrade <name|path>  Bring a wiki's handbook and scaffold files up to the template's.
  upgrade --all        Do that for every wiki in the collection.
  unlock <name|path>   Free a stuck compile lock.
  claude               Add the wiki line to ~/.claude/CLAUDE.md so every session finds its wiki.

  journal              Show the work journal's settings and today's entry count.
  journal on | off     Turn the journal on or off. It is on by default.
  journal set <key> <value>  Change a setting. See $(tilde "$WIKIS_DIR")/journal/config.
  journal note <project> <text>  Add one line to today's journal.
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

cmd_init() {
  local want_git="$1"
  mkdir -p "$WIKIS_DIR"
  write_collection_marker
  scaffold "$WIKIS_DIR/$SHARED" 0
  write_journal_config
  if [ "$want_git" = 1 ]; then
    if in_git_repo "$WIKIS_DIR"; then
      echo "git:     $(tilde "$WIKIS_DIR") is already in a repo, skipped"
    else
      [ -f "$WIKIS_DIR/.gitignore" ] || printf '.DS_Store\n.compile-lock\n' > "$WIKIS_DIR/.gitignore"
      git -C "$WIKIS_DIR" init -q
      apply_journal_commit
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
  local d v tv waiting f b lock line note since found=0
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
    if [ -n "$tv" ] && [ "${v:-0}" -lt "$tv" ]; then note="$note  <- behind template v$tv, run: ./wiki.sh upgrade ${d##*/}"; fi
    if [ -f "$d/repos.md" ] && grep -q '^- ' "$d/repos.md"; then
      note="$note  covers: $(sed -n 's/^- //p' "$d/repos.md" | tr '\n' ' ')"
    fi
    printf '%-26s %-9s %-8s %s%s\n' "${d##*/}" "v${v:-?}" "$waiting" "$lock" "$note"
  done
  [ "$found" = 1 ] || echo "(none yet. Run: ./wiki.sh init)"
  if [ -f "$JOURNAL_CFG" ]; then
    echo "journal: $(journal_get enabled), commit $(journal_get commit), entries $(journal_get entries)"
  fi
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
  echo "== journal"
  write_journal_config
  apply_journal_commit
}

cmd_unlock() {
  local root="$1"
  is_wiki "$root" || die "$(tilde "$root") is not a wiki"
  printf 'free\n' > "$root/.compile-lock"
  echo "unlocked: $(tilde "$root")"
}

cmd_claude() {
  local f="$HOME/.claude/CLAUDE.md" dir line tmp
  dir="$(tilde "$WIKIS_DIR")"
  line="My knowledge wikis live in $dir, one folder per project, plus a shared one at $dir/$SHARED. At session start, run \`$(tilde "$REPO")/wiki.sh which <repository-name>\` for the repository you are working in. Its name is the last part of its remote URL, or its folder name. The command prints the wiki that covers it. Read that wiki's AGENTS.md and follow it. If no wiki covers the repository, read $dir/$SHARED/AGENTS.md and follow that, and create the repository's wiki with \`$(tilde "$REPO")/wiki.sh new <repository-name>\` the first time you have something to file there. Outside any repository, use the shared wiki."
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
JOURNAL_KEYS="enabled commit entries format since day_starts workdays code_dirs depth authors exclude save keep_days"

# shellcheck disable=SC2088
journal_default() {
  case "$1" in
    enabled) echo yes ;;
    commit) echo no ;;
    entries) echo yes ;;
    format) echo standup ;;
    since) echo lastworkday ;;
    day_starts) echo 04:00 ;;
    workdays) echo 12345 ;;
    code_dirs) echo "~/dev" ;;
    depth) echo 4 ;;
    authors) echo "" ;;
    exclude) echo "" ;;
    save) echo no ;;
    keep_days) echo 0 ;;
  esac
}

write_journal_config() {
  mkdir -p "$JOURNAL_DIR"
  [ -f "$JOURNAL_CFG" ] && return 0
  cat > "$JOURNAL_CFG" <<'EOF'
# Work journal settings. Change them with: ./wiki.sh journal set <key> <value>
# Agents read this file. See rules/journal.md in any wiki.

# yes: agents keep the journal and answer "what did I do" from it. no: the feature is off.
enabled=yes
# yes: journal files are committed and pushed with the wikis. no: they stay on this machine.
commit=no
# yes: agents add one line for work that leaves no commit (an investigation, a review, a dead end).
entries=yes
# Default report shape: standup (yesterday, today, blockers), summary (by project), or detailed.
format=standup
# Default report range: lastworkday, yesterday, today, week, lastweek, a number of days like 7d, or a date.
since=lastworkday
# Local time a new day starts. Work before it counts toward the previous day.
day_starts=04:00
# Working days, 1 is Monday and 7 is Sunday. Used to find the last workday.
workdays=12345
# Folders to search for code repositories, separated by colons.
code_dirs=~/dev
# How deep to search code_dirs for repositories.
depth=4
# Extra commit author emails or names, separated by commas. Each repository's own user.email always counts.
authors=
# Repositories and wikis to leave out, as comma-separated globs, such as personal-*,scratch.
exclude=
# yes: save each generated report in this folder as YYYY-MM-DD-<format>.md.
save=no
# Delete day files older than this many days. 0 keeps everything.
keep_days=0
EOF
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
  local key="$1" val="$2" k ok=0 tmp
  for k in $JOURNAL_KEYS; do [ "$k" = "$key" ] && ok=1; done
  [ "$ok" = 1 ] || die "unknown journal setting: $key. Settings: $JOURNAL_KEYS"
  case "$key" in
    enabled | commit | entries | save)
      case "$val" in yes | no) ;; *) die "$key takes yes or no" ;; esac ;;
    format)
      case "$val" in standup | summary | detailed) ;; *) die "format takes standup, summary, or detailed" ;; esac ;;
    depth | keep_days)
      case "$val" in '' | *[!0-9]*) die "$key takes a number" ;; esac ;;
    day_starts)
      case "$val" in [0-2][0-9]:[0-5][0-9]) ;; *) die "day_starts takes a time like 04:00" ;; esac ;;
    workdays)
      case "$val" in '' | *[!1-7]*) die "workdays takes digits 1 to 7, such as 12345" ;; esac ;;
    since)
      since_ok "$val" || die "since takes lastworkday, yesterday, today, week, lastweek, a number of days like 7d, or a date" ;;
  esac
  case "$val" in *$'\n'*) die "value must be one line" ;; esac
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
  local project="$1" text="$2" day f
  if [ "$(journal_get enabled)" != yes ] || [ "$(journal_get entries)" != yes ]; then
    echo "journal entries are off, nothing written"
    return 0
  fi
  text="$(printf '%s' "$text" | tr '\n\r' '  ')"
  [ -n "$text" ] || die "journal note needs some text"
  write_journal_config >/dev/null
  day="$(journal_today)"
  f="$(journal_file_for "$day")"
  [ -f "$f" ] || printf '# Journal %s\n\n' "$day" > "$f"
  # One short line per append, so parallel sessions don't interleave.
  printf -- '- %s [%s] %s\n' "$(date +%H:%M)" "$project" "$text" >> "$f"
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

cmd_journal() {
  local sub="${1:-show}"
  [ $# -gt 0 ] && shift
  case "$sub" in
    show) journal_show ;;
    on) write_journal_config >/dev/null; journal_set enabled yes; apply_journal_commit ;;
    off) write_journal_config >/dev/null; journal_set enabled no ;;
    set) [ $# -ge 1 ] || die "usage: ./wiki.sh journal set <key> <value>"; journal_set "$1" "${2:-}" ;;
    note) [ $# -ge 2 ] || die "usage: ./wiki.sh journal note <project> <text>"; journal_note "$1" "$(shift; printf '%s ' "$@" | sed 's/ $//')" ;;
    path) journal_file_for "$(journal_today)"; printf '\n' ;;
    prune) journal_prune ;;
    *) die "journal commands: show, on, off, set <key> <value>, note <project> <text>, path, prune" ;;
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
    if [ "$want_all" = 1 ]; then cmd_upgrade_all; else need_target; upgrade_one "$(resolve "$target")"; fi
    ;;
  unlock) need_target; cmd_unlock "$(resolve "$target")" ;;
  claude) cmd_claude ;;
  -h | --help | help) usage ;;
  *) usage; exit 1 ;;
esac
