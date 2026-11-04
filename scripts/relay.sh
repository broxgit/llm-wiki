#!/usr/bin/env bash
# wiki relay: the Mac's side of the remote pair-run loop with Microsoft Copilot Cowork.
#
#   relay run     Wait for a deliverable, copy it out of OneDrive, and run the copy on a keypress.
#   relay scan    Put a repository in OneDrive for Cowork to read, in place of an attached scan.
#   relay mr      Put a merge request and what it takes to review it in OneDrive.
#   relay review  Save the review Cowork wrote where you keep your reviews.
#   relay apply   Leave a proven patch in your working tree, uncommitted.
#
# Run through wiki.sh, which finds the OneDrive folder and sets LLM_WIKI_ONEDRIVE.
# shellcheck disable=SC2034  # RUNLIB_DIR and RUNLIB_EXPECT are read by runlib.sh.
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNLIB="$REPO/cowork/remote-pair-run/runlib.sh"
WIKI_CMD="${WIKI_CMD:-wiki}"
# shellcheck source=/dev/null
. "$RUNLIB"

die() { echo "error: $*" >&2; exit 1; }

COWORK="${LLM_WIKI_ONEDRIVE:-}/Documents/Cowork"
WAIT="${LLM_WIKI_RELAY_WAIT:-600}"
POLL="${LLM_WIKI_RELAY_POLL:-5}"
READ_LIMIT="${LLM_WIKI_RELAY_READ_LIMIT:-120}"
CHECK_LIMIT="${LLM_WIKI_RELAY_CHECK_LIMIT:-600}"
REPORTS="${RUNLIB_REPORT_DIR:-$HOME/pair-run-reports}"
SETTINGS="${XDG_CONFIG_HOME:-$HOME/.config}/llm-wiki/relay"
WORK=""
RUN_STARTED=""

cleanup() {
  [ -z "$WORK" ] || rm -rf "$WORK"
  [ -z "$RUN_STARTED" ] || echo "Relay run ended at $(now)."
}

# setting <key> <default>: a line of the settings file `wiki setup copilot-cowork` writes.
setting() {
  local v
  v="$(sed -n "s/^$1=//p" "$SETTINGS" 2>/dev/null | tail -n 1)"
  printf '%s' "${v:-$2}"
}
REVIEWS_DIR="$(setting reviews "$HOME/mr-reviews")"
CLONES_DIRS="$(setting clones "$HOME/dev")"

usage() {
  cat <<EOF
Usage: $WIKI_CMD relay [--dir ONEDRIVE_FOLDER] run [TASK-FOLDER/DELIVERABLE] [--expect VERSION] [--no-install]
       $WIKI_CMD relay [--dir ONEDRIVE_FOLDER] scan [REPOSITORY] [--branch NAME] [--no-wiki]
       $WIKI_CMD relay [--dir ONEDRIVE_FOLDER] mr URL... [--also PATH[@BRANCH]]... [--repo PATH] [--go-prefix PREFIX]... [--checks | --no-checks] [--no-wiki]
       $WIKI_CMD relay [--dir ONEDRIVE_FOLDER] review TASK-FOLDER/DELIVERABLE [--expect VERSION]
       $WIKI_CMD relay [--dir ONEDRIVE_FOLDER] apply TASK-FOLDER/DELIVERABLE --repo PATH [--expect VERSION]

  run    Waits until a deliverable from Copilot Cowork matches its manifest, copies it to a
         local folder, shows you what's there, and runs the copy when you press y. If it gives up, it says what this Mac sees. The report
         goes to Documents/Cowork/relay/<task-folder>/reports in OneDrive, only if a run
         happened. Then tell Cowork "done". With no deliverable named, it uses the newest.
  scan   Puts the repository's current branch and uncommitted changes in OneDrive, at
         Documents/Cowork/relay/scans, with a note of the commit and tool versions. Untracked
         files stay out. Defaults to the repository you're in. The compiled pages of the wiki
         that covers it go too, unless you add --no-wiki. Its raw notes and other wikis stay out.
         --branch NAME scans that branch instead, as origin has it after a fetch, or your
         local copy if origin doesn't have it. Your checkout isn't touched, and uncommitted
         changes stay out.
  mr     Fetches a GitLab merge request with glab, and puts it in OneDrive for Cowork to review:
         its discussions and diff, its source and target branches, the libraries its go.mod
         pins, your earlier review if there is one, and its wiki. It only fetches in your
         clone, finds the clone under $CLONES_DIRS, and puts a prompt for Cowork on the clipboard.
         --also sends another repository, or just one folder of it, at origin's default
         branch or the one you name. Use it as many times as you like. --go-prefix says which
         modules count as yours, if it's not the ones that share your module's host.
         If it's Go, it asks whether to run go build, vet, test and mod tidy on a temporary
         copy of the branch first, and sends the results. --checks and --no-checks answer for you.
  review Waits for the review Cowork published, shows it and what it says it covered, and when
         you press y saves it under $REVIEWS_DIR. A copy you already have is kept as
         <name>.previous.
  apply  Waits for a deliverable, and when you press y applies its patches to the repository's
         working tree. It never commits. Use it once a run has passed.
EOF
}

# ---- run ---------------------------------------------------------------------

# deliverable_path <TASK-FOLDER/DELIVERABLE>: where it is in OneDrive.
deliverable_path() {
  case "$1" in
    */*/* | /* | */ | ..* | */..) die "name a deliverable as TASK-FOLDER/DELIVERABLE: $1" ;;
    */*) printf '%s' "$COWORK/Tasks/${1%%/*}/output/${1#*/}" ;;
    *) die "name a deliverable as TASK-FOLDER/DELIVERABLE: $1" ;;
  esac
}

needs_terminal() {
  [ -t 0 ] || [ -n "${LLM_WIKI_TEST_TTY:-}" ] || die "relay $1 asks before it does anything, so it needs a terminal. Agents: tell the user to run it."
}

newest_deliverable() {
  local m best=""
  for m in "$COWORK"/Tasks/*/output/*/manifest.txt; do
    [ -f "$m" ] || continue
    if [ -z "$best" ] || [ "$m" -nt "$best" ]; then best="$m"; fi
  done
  printf '%s' "${best%/manifest.txt}"
}

manifest_paths() {
  sed -n 's/^sha256 [0-9a-f]*  \(.*\)$/\1/p' "$1/manifest.txt" 2>/dev/null
}

# The manifest comes from the cloud, so it can't name a file outside the folder.
check_manifest_paths() {
  local p
  while IFS= read -r p; do
    case "/$p/" in
      */../* | //*) die "the manifest names a path outside its folder: $p" ;;
    esac
  done < <(manifest_paths "$1")
}

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# macOS marks files with attributes such as com.apple.provenance, and Linux tar warns about each one.
make_archive() {
  local out="$1"
  shift
  COPYFILE_DISABLE=1 tar --no-xattrs -czf "$out" "$@" 2>/dev/null || COPYFILE_DISABLE=1 tar -czf "$out" "$@"
}

# What this Mac says about a file, without reading it. A refusal shows up here too.
describe_file() {
  local out
  out="$(stat -c 'size %s, %b blocks' "$1" 2>/dev/null)" || out="$(stat -f 'size %z, %b blocks, flags %Sf' "$1" 2>&1)"
  printf '%s' "${out##*: }"
}

# Runs a command for at most $1 seconds, so a download that never finishes can't outlast the wait.
limited() {
  local secs="$1" pid i=0
  shift
  "$@" </dev/null &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$i" -ge $((secs * 10)) ]; then
      kill -9 "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      return 124
    fi
    sleep 0.1
    i=$((i + 1))
  done
  wait "$pid" 2>/dev/null
}

# Reads a file out of OneDrive. A read is what makes OneDrive download a file that's only in
# the cloud. This is the only way anything here reads the synced folder, and it always says
# why it couldn't.
read_file() {
  local src="$1" dst="$2" name="$3" rc why
  limited "$READ_LIMIT" cat "$src" >"$dst" 2>"$WORK/read.err"
  rc=$?
  [ "$rc" -eq 0 ] && return 0
  why="$(head -n 1 "$WORK/read.err")"
  case "$rc:$why" in
    124:*) why="still reading after ${READ_LIMIT}s" ;;
    137:*) why="the read was killed" ;;
    *"No such file"*) echo "$name is missing"; return 1 ;;
    *) why="${why##*: }" ;;
  esac
  echo "$name can't be read: ${why:-exit $rc} ($(describe_file "$src"))"
  return 1
}

# One try at copying a deliverable. Copies only what the manifest lists, because Cowork can't
# delete old files from OneDrive, and checks the copy, so nothing can be half-delivered. Prints
# each problem, and prints nothing when the copy is good.
try_copy() {
  local src="$1" dst="$2" p version bad=""
  rm -rf "$dst"
  mkdir -p "$dst" || { echo "can't write to $dst"; return 1; }
  read_file "$src/manifest.txt" "$dst/manifest.txt" manifest.txt || return 1
  version="$(_runlib_manifest_version "$dst/manifest.txt")"
  if [ -z "$version" ]; then
    echo "manifest.txt has no version line: read $(wc -c <"$dst/manifest.txt" | tr -d ' ') bytes, starting $(head -c 12 "$dst/manifest.txt" | od -An -tx1 | tr -s ' ' | sed 's/^ //; s/ $//') ($(describe_file "$src/manifest.txt"))"
    return 1
  fi
  if [ -n "$RUNLIB_EXPECT" ] && [ "$version" != "$RUNLIB_EXPECT" ]; then
    echo "manifest.txt is version $version, expected $RUNLIB_EXPECT"
    return 1
  fi
  check_manifest_paths "$dst"
  while IFS= read -r p; do
    mkdir -p "$dst/$(dirname "$p")" || { echo "can't write to $dst"; return 1; }
    read_file "$src/$p" "$dst/$p" "$p" || bad=1
  done < <(manifest_paths "$dst")
  [ -z "$bad" ] || return 1
  RUNLIB_DIR="$dst"
  _runlib_sync_problems
}

# iTerm was refused for over an hour while Apple's Terminal read the same files at once,
# though not every time. So say it the moment it shows, not after the wait.
refusal_advice() {
  if [ "${TERM_PROGRAM:-}" = Apple_Terminal ]; then
    echo "macOS is refusing to let Apple's Terminal read OneDrive files that aren't on this Mac yet. More waiting rarely helps."
    echo "If your OneDrive allows it, in Finder, right-click the task's output folder and choose Always Keep on This Device."
  else
    echo "macOS is refusing to let ${TERM_PROGRAM:-this terminal app} read OneDrive files that aren't on this Mac yet. More waiting rarely helps."
    echo "Press Ctrl-C, and run the same command in Apple's Terminal, which could read them in one test."
  fi
}

# Keeps trying through every way OneDrive has shown a file isn't ready: missing, out of date,
# unreadable, or refused with "Operation not permitted".
wait_for_deliverable() {
  local named="$1" dst="$2" start="$SECONDS" waited=0 said=0 advised="" problems last=""
  while :; do
    SRC="$named"
    [ -n "$SRC" ] || SRC="$(newest_deliverable)"
    if [ -z "$SRC" ]; then
      problems="no deliverable in $COWORK/Tasks yet"
      # A refused folder looks empty to a glob.
      if ! ls "$COWORK/Tasks" >/dev/null 2>"$WORK/read.err"; then
        grep -q "No such file" "$WORK/read.err" || problems="can't list $COWORK/Tasks: $(sed 's/^.*: //' "$WORK/read.err" | head -n 1)"
      fi
    else
      try_copy "$SRC" "$dst" >"$WORK/problems"
      problems="$(cat "$WORK/problems")"
      if [ -z "$problems" ]; then
        [ -z "$last" ] || echo "Ready after $((SECONDS - start))s."
        return 0
      fi
    fi
    waited=$((SECONDS - start))
    if [ "$problems" != "$last" ]; then
      echo "Waiting for OneDrive (${waited}s of ${WAIT}s):"
      printf '%s\n' "$problems" | head -n 8 | sed 's/^/  /'
      last="$problems"
      said="$waited"
      case "$problems" in
        *"Operation not permitted"*)
          if [ -z "$advised" ]; then
            refusal_advice
            advised=1
          fi
          ;;
      esac
    elif [ $((waited - said)) -ge 60 ]; then
      echo "Still waiting (${waited}s of ${WAIT}s)."
      said="$waited"
    fi
    if [ "$waited" -ge "$WAIT" ]; then
      {
        echo "Still not ready after ${waited}s, at $(now), so nothing ran and no report was sent."
        echo "Paste this output to Cowork. If your OneDrive allows it, in Finder, right-click the task's output folder, choose Always Keep on This Device, and run the same command again."
      } >&2
      return 1
    fi
    sleep "$POLL"
  done
}

show_deliverable() {
  local copy="$1" where="$2" version="$3" p size same="differs from this machine's copy"
  cmp -s "$copy/runlib.sh" "$RUNLIB" && same="same as this machine's copy"
  echo
  echo "Deliverable: $where"
  echo "Version:     $version"
  echo "Files:"
  while IFS= read -r p; do
    size="$(wc -c <"$copy/$p" | tr -d ' ')"
    case "$p" in
      runlib.sh) echo "  $p ($size bytes, $same)" ;;
      *) echo "  $p ($size bytes)" ;;
    esac
  done < <(manifest_paths "$copy")
  echo
}

view_deliverable() {
  local copy="$1" p
  {
    while IFS= read -r p; do
      # A runlib.sh that differs from this machine's is the one to read, so only a match is skipped.
      if [ "$p" = runlib.sh ] && cmp -s "$copy/$p" "$RUNLIB"; then
        printf "\n===== %s: same as this machine's copy, not shown =====\n" "$p"
        continue
      fi
      printf '\n===== %s =====\n' "$p"
      cat "$copy/$p"
    done < <(manifest_paths "$copy")
  } | ${PAGER:-less}
}

# Nothing from the cloud runs until someone says so here.
ask_to_run() {
  local copy="$1" question="${2:-Run it?}" key
  while :; do
    printf '%s [y]es, [v]iew the files, [n]o: ' "$question"
    IFS= read -r -n 1 key || { echo; return 1; }
    echo
    case "$key" in
      y | Y) return 0 ;;
      n | N) return 1 ;;
      v | V) view_deliverable "$copy" ;;
    esac
  done
}

send_report() {
  local report="$1" task="$2" dir i=0
  dir="$COWORK/relay/$task/reports"
  while [ "$i" -lt 3 ]; do
    if mkdir -p "$dir" 2>/dev/null && cp "$report" "$dir/" 2>/dev/null && cmp -s "$report" "$dir/$(basename "$report")"; then
      echo
      echo "Sent to OneDrive: Documents/Cowork/relay/$task/reports/$(basename "$report")"
      echo 'Now tell Cowork: done'
      return 0
    fi
    i=$((i + 1))
    [ "$i" -lt 3 ] && sleep "$POLL"
  done
  echo
  echo "Couldn't put the report in OneDrive. Attach it in Cowork instead: $report" >&2
  return 1
}

cmd_run() {
  local named="" where="" expect="" no_install="" a rc copy version task new
  while [ $# -gt 0 ]; do
    case "$1" in
      --expect)
        [ -n "${2:-}" ] || die "--expect needs a version"
        expect="$2"
        shift 2
        ;;
      --no-install) no_install=1; shift ;;
      -h | --help) usage; return 0 ;;
      -*) die "relay run: unknown option $1. Try $WIKI_CMD relay --help" ;;
      *)
        [ -z "$where" ] || die "relay run takes one deliverable"
        where="$1"
        shift
        ;;
    esac
  done
  if [ -n "$where" ]; then
    named="$(deliverable_path "$where")" || exit 1
  fi
  needs_terminal run

  WORK="$(mktemp -d "${TMPDIR:-/tmp}/llm-wiki-relay.XXXXXX")" || die "can't make a scratch folder"
  trap cleanup EXIT
  copy="$WORK/deliverable"
  RUNLIB_EXPECT="$expect"
  echo "Relay run started at $(now)."
  RUN_STARTED=1
  wait_for_deliverable "$named" "$copy" || return 1

  version="$(_runlib_manifest_version "$copy/manifest.txt")"
  a="${SRC%/*}"
  task="$(basename "${a%/*}")"
  show_deliverable "$copy" "$task/$(basename "$SRC")" "$version"
  if ! ask_to_run "$copy"; then
    echo "Nothing ran, and no report was sent."
    return 1
  fi

  mkdir -p "$REPORTS" || die "can't create $REPORTS"
  ls "$REPORTS" | LC_ALL=C sort >"$WORK/before"
  echo
  # The copy already matches its manifest, so runlib has nothing to wait for.
  if [ -n "$no_install" ]; then
    RUNLIB_REPORT_DIR="$REPORTS" RUNLIB_SYNC_WAIT=0 bash "$copy/run.sh" --expect "$version" --no-install
  else
    RUNLIB_REPORT_DIR="$REPORTS" RUNLIB_SYNC_WAIT=0 bash "$copy/run.sh" --expect "$version"
  fi
  rc=$?

  # A report from this run only: an older one in the folder must never go out in its place.
  new="$(ls "$REPORTS" | LC_ALL=C sort | LC_ALL=C comm -13 "$WORK/before" - | tail -n 1)"
  if [ -z "$new" ]; then
    echo
    echo "That run wrote no report, so nothing was sent to Cowork. Its output is above." >&2
    [ "$rc" -ne 0 ] || rc=1
    return "$rc"
  fi
  send_report "$REPORTS/$new" "$task" || { [ "$rc" -ne 0 ] || rc=1; }
  return "$rc"
}

# ---- scan --------------------------------------------------------------------

# Copies one wiki's index and compiled pages for Cowork to read, and prints how many pages.
# Markdown only, so raw notes, the log and anything else in the wiki stay on this machine.
copy_wiki() {
  local wiki="$1" dst="$2"
  mkdir -p "$dst" || return 1
  cp "$wiki/index.md" "$dst/index.md" || return 1
  if [ -d "$wiki/wiki" ]; then
    cp -R "$wiki/wiki" "$dst/wiki" || return 1
    find "$dst/wiki" ! -type f ! -type d -exec rm -f {} +
    find "$dst/wiki" -type f ! -name '*.md' -exec rm -f {} +
    find "$dst/wiki" -type f -name '.*' -exec rm -f {} +
  fi
  find "$dst" -type f -name '*.md' ! -path "$dst/index.md" | wc -l | tr -d ' '
}

# Finds a named branch, preferring origin's copy, so "master" means what everyone else sees.
# Sets SCAN_REF to the ref and SCAN_SOURCE to what to call it.
find_branch() {
  local root="$1" want="$2"
  git check-ref-format --branch "$want" >/dev/null 2>&1 || die "not a branch name: $want"
  if git -C "$root" remote get-url origin >/dev/null 2>&1; then
    if GIT_TERMINAL_PROMPT=0 git -C "$root" fetch -q origin "+refs/heads/$want:refs/remotes/origin/$want" 2>/dev/null; then
      SCAN_REF="refs/remotes/origin/$want"
      SCAN_SOURCE="origin/$want"
      return 0
    fi
    if git -C "$root" rev-parse --verify -q "refs/remotes/origin/$want" >/dev/null; then
      SCAN_REF="refs/remotes/origin/$want"
      SCAN_SOURCE="origin/$want as of your last fetch, because origin couldn't be reached"
      return 0
    fi
  fi
  git -C "$root" rev-parse --verify -q "refs/heads/$want" >/dev/null || die "no branch named $want, on origin or here"
  SCAN_REF="refs/heads/$want"
  SCAN_SOURCE="your local $want, not on origin"
}

# collect_wiki <repository> <no-wiki flag>: copies the wiki that covers a repository into the
# scratch folder, and sets WIKI_LINE, WIKI_NAME, WIKI_PAGES and WIKI_PART for the caller.
# Only that wiki. The shared wiki can hold personal rules, so it stays out.
collect_wiki() {
  local wiki=""
  WIKI_LINE="none covers this repository"
  WIKI_NAME=""
  WIKI_PAGES=0
  WIKI_PART=""
  if [ -n "$2" ]; then
    WIKI_LINE="left out with --no-wiki"
    return 0
  fi
  wiki="$("$REPO/wiki.sh" which "$1" 2>/dev/null)" || wiki=""
  # wiki which shortens the path to a literal ~/.
  # shellcheck disable=SC2088
  case "$wiki" in "~/"*) wiki="$HOME/${wiki#"~/"}" ;; esac
  WIKI_NAME="${wiki##*/}"
  if [ "$WIKI_NAME" = global ]; then
    wiki=""
    WIKI_LINE="left out, because the shared wiki isn't sent"
  fi
  [ -n "$wiki" ] || return 0
  WIKI_PAGES="$(copy_wiki "$wiki" "$WORK/repo-wiki")" || die "couldn't copy the $WIKI_NAME wiki"
  if [ "$WIKI_PAGES" -gt 0 ]; then
    WIKI_LINE="$WIKI_NAME, compiled pages: $WIKI_PAGES, start at repo-wiki/index.md in the archive"
    WIKI_PART="repo-wiki"
  else
    WIKI_LINE="$WIKI_NAME has no pages yet"
  fi
}

# scratch_fetch <clone> <scratch repository> <ref in the clone> <ref to make>: copies a ref into
# a scratch repository. A partial clone can't hand over files it never downloaded, so that one
# comes from origin itself.
scratch_fetch() {
  local root="$1" scratch="$2" src="$3" dst="$4" url remote
  if [ -z "$(git -C "$root" config --get remote.origin.partialclonefilter 2>/dev/null)" ]; then
    git -C "$scratch" fetch -q "$root" "+$src:$dst"
    return $?
  fi
  url="$(git -C "$root" config --get remote.origin.url)"
  case "$src" in
    refs/remotes/origin/merge-requests/*) remote="refs/merge-requests/${src##*/}/head" ;;
    refs/remotes/origin/*) remote="refs/heads/${src#refs/remotes/origin/}" ;;
    *) echo "$root is a partial clone, so it can't send the local branch $src." >&2; return 1 ;;
  esac
  GIT_TERMINAL_PROMPT=0 git -C "$scratch" fetch -q "$url" "+$remote:$dst"
}

# Scans have reached Cowork at up to 50 MB. Past that, nobody knows, so say so.
size_warning() {
  [ "$1" -le 52428800 ] || echo "That's over 50 MB, the largest size tried with Cowork. If it can't read it, try without the wiki or with fewer repositories."
}

list_tools() {
  local t
  for t in go git buf protoc python3 node glab; do
    command -v "$t" >/dev/null 2>&1 || continue
    if [ "$t" = go ]; then
      echo "  go: $(go version 2>&1 | head -n 1)"
    else
      echo "  $t: $("$t" --version 2>&1 | head -n 1)"
    fi
  done
}

cmd_scan() {
  local dir="." root name branch commit size hash dest dirty=no no_wiki="" want=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -h | --help) usage; return 0 ;;
      --no-wiki) no_wiki=1; shift ;;
      --branch)
        [ -n "${2:-}" ] || die "--branch needs a branch name"
        want="$2"
        shift 2
        ;;
      -*) die "relay scan: unknown option $1. Try $WIKI_CMD relay --help" ;;
      *) dir="$1"; shift ;;
    esac
  done
  root="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || die "not a git repository: $dir"
  name="$(basename "$root" | tr -c 'A-Za-z0-9._\n-' '-')"
  [ -n "$name" ] || die "can't name a scan after $root"
  if [ -n "$want" ]; then
    find_branch "$root" "$want"
    commit="$(git -C "$root" rev-parse --verify -q "$SCAN_REF")" || die "can't read $want"
    branch="$want"
  else
    commit="$(git -C "$root" rev-parse --verify -q HEAD)" || die "$root has no commits yet"
    branch="$(git -C "$root" symbolic-ref -q --short HEAD)" || branch=""
  fi

  WORK="$(mktemp -d "${TMPDIR:-/tmp}/llm-wiki-relay.XXXXXX")" || die "can't make a scratch folder"
  trap cleanup EXIT
  if [ -n "$want" ]; then
    # A scratch repository, so the clone gets the branch under its own name, without moving
    # any branch in the real one.
    git init -q --bare "$WORK/branch.git" || die "git couldn't make a scratch repository"
    scratch_fetch "$root" "$WORK/branch.git" "$SCAN_REF" "refs/heads/$want" || die "git couldn't read $want from $root"
    git -C "$WORK/branch.git" symbolic-ref HEAD "refs/heads/$want"
    git -C "$WORK/branch.git" bundle create -q "$WORK/repo.bundle" HEAD "refs/heads/$want" || die "git couldn't bundle $want"
    : >"$WORK/uncommitted.patch"
  elif [ -n "$branch" ]; then
    git -C "$root" bundle create -q "$WORK/repo.bundle" HEAD "refs/heads/$branch" || die "git couldn't bundle $root"
  else
    git -C "$root" bundle create -q "$WORK/repo.bundle" HEAD || die "git couldn't bundle $root"
  fi
  if [ -z "$want" ]; then
    git -C "$root" diff HEAD --binary >"$WORK/uncommitted.patch" || die "git couldn't read the uncommitted changes"
    [ -s "$WORK/uncommitted.patch" ] && dirty=yes
  fi

  collect_wiki "$(basename "$root")" "$no_wiki"
  {
    echo "LLM-WIKI RELAY SCAN"
    echo "repository: $name"
    echo "path: $root"
    echo "branch: ${branch:-detached}"
    [ -z "$want" ] || echo "source: $SCAN_SOURCE"
    echo "commit: $commit"
    echo "taken: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "wiki: $WIKI_LINE"
    if [ "$dirty" = yes ]; then
      echo "uncommitted changes: yes, in uncommitted.patch"
    else
      echo "uncommitted changes: no, uncommitted.patch is empty"
    fi
    if [ -z "$want" ]; then
      echo "status (untracked files, marked ??, are not in the archive):"
      git -C "$root" status --short | head -n 200 | sed 's/^/  /'
    fi
    echo "tools:"
    list_tools
  } >"$WORK/scan.txt"
  # COPYFILE_DISABLE keeps macOS's tar from adding ._ files.
  make_archive "$WORK/$name.tar.gz" -C "$WORK" repo.bundle uncommitted.patch scan.txt ${WIKI_PART:+"$WIKI_PART"} || die "tar couldn't make the archive"
  hash="$(sha256_of "$WORK/$name.tar.gz")"
  size="$(wc -c <"$WORK/$name.tar.gz" | tr -d ' ')"
  {
    cat "$WORK/scan.txt"
    echo "archive: $name.tar.gz"
    echo "archive sha256: $hash"
    echo "archive bytes: $size"
  } >"$WORK/$name.txt"

  dest="$COWORK/relay/scans"
  mkdir -p "$dest" || die "can't create $dest"
  # The note goes last, so its hash never describes an archive that isn't there yet.
  cp "$WORK/$name.tar.gz" "$dest/" || die "couldn't copy the archive to $dest"
  cp "$WORK/$name.txt" "$dest/" || die "couldn't copy the note to $dest"
  if [ -n "$want" ]; then
    echo "Scanned $name: $want at $commit, from $SCAN_SOURCE, $size bytes, uncommitted changes left out"
  else
    echo "Scanned $name: ${branch:-detached HEAD} at $commit, $size bytes, uncommitted changes: $dirty"
  fi
  [ -z "$WIKI_PART" ] || echo "Included the $WIKI_NAME wiki (compiled pages: $WIKI_PAGES, no raw notes). Add --no-wiki to leave it out."
  size_warning "$size"
  echo "Sent to OneDrive: Documents/Cowork/relay/scans/$name.txt and $name.tar.gz"
  echo "Now tell Cowork: read Documents/Cowork/relay/scans/$name.txt"
}

# ---- also --------------------------------------------------------------------

default_branch() {
  local d
  d="$(git -C "$1" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)"
  if [ -n "$d" ]; then
    printf '%s' "${d#origin/}"
  elif git -C "$1" rev-parse --verify -q refs/remotes/origin/master >/dev/null || git -C "$1" rev-parse --verify -q refs/heads/master >/dev/null; then
    printf master
  else
    printf main
  fi
}

# send_also <PATH[@BRANCH]>: another repository for Cowork, or one folder of it, as a plain scan
# of its own. Prints the note's place in OneDrive on the last line.
send_also() {
  local spec="$1" path branch="" root sub name ref commit size hash dest t
  path="${spec%@*}"
  [ "$path" = "$spec" ] || branch="${spec##*@}"
  # shellcheck disable=SC2088
  case "$path" in "~/"*) path="$HOME/${path#"~/"}" ;; esac
  root="$(git -C "$path" rev-parse --show-toplevel 2>/dev/null)" || die "--also: not in a git repository: $path"
  sub="$(git -C "$path" rev-parse --show-prefix)"
  [ -n "$branch" ] || branch="$(default_branch "$root")"
  if [ -z "$sub" ]; then
    (cmd_scan "$root" --branch "$branch" --no-wiki) >&2 || die "--also: couldn't scan $path"
    echo "Documents/Cowork/relay/scans/$(basename "$root" | tr -c 'A-Za-z0-9._\n-' '-').txt"
    return 0
  fi
  find_branch "$root" "$branch"
  ref="$SCAN_REF"
  commit="$(git -C "$root" rev-parse --verify -q "$ref")" || die "--also: can't read $branch"
  sub="${sub%/}"
  name="$(basename "$root")-$sub"
  name="$(printf '%s' "$name" | tr -c 'A-Za-z0-9._-' '-')"
  t="$(mktemp -d "${TMPDIR:-/tmp}/llm-wiki-relay.XXXXXX")" || die "can't make a scratch folder"
  git -C "$root" archive --format=tar.gz -o "$t/$name.tar.gz" "$commit" -- "$sub" || { rm -rf "$t"; die "--also: couldn't pack $sub"; }
  hash="$(sha256_of "$t/$name.tar.gz")"
  size="$(wc -c <"$t/$name.tar.gz" | tr -d ' ')"
  {
    echo "LLM-WIKI RELAY FOLDER"
    echo "repository: $(basename "$root")"
    echo "folder: $sub"
    echo "branch: $branch"
    echo "source: $SCAN_SOURCE"
    echo "commit: $commit"
    echo "taken: $(now)"
    echo "archive: $name.tar.gz, plain files with no git history"
    echo "archive sha256: $hash"
    echo "archive bytes: $size"
  } >"$t/$name.txt"
  dest="$COWORK/relay/scans"
  mkdir -p "$dest" && cp "$t/$name.tar.gz" "$dest/" && cp "$t/$name.txt" "$dest/" || { rm -rf "$t"; die "--also: couldn't copy to $dest"; }
  rm -rf "$t"
  echo "Scanned the $sub folder of $(basename "$root"): $branch at $commit, from $SCAN_SOURCE, $size bytes" >&2
  echo "Documents/Cowork/relay/scans/$name.txt"
}

# ---- mr ----------------------------------------------------------------------

# json_get <file> <dotted.key>: one value on one line, or nothing. Lists use their first item.
json_get() {
  python3 - "$1" "$2" <<'PY' 2>/dev/null
import json, sys
v = json.load(open(sys.argv[1]))
for k in sys.argv[2].split("."):
    if isinstance(v, list):
        v = v[0] if v else {}
    v = v.get(k) if isinstance(v, dict) else None
if v is not None:
    print(" ".join(str(v).split()))
PY
}

ticket_of() {
  python3 - "$1" <<'PY' 2>/dev/null
import json, re, sys
d = json.load(open(sys.argv[1]))
for f in ("title", "source_branch", "description"):
    m = re.search(r"[A-Z]+-[0-9]+", str(d.get(f) or ""))
    if m:
        print(m.group(0))
        break
PY
}

# MRs the description links, such as "copy of !12", because a review needs their discussions too.
related_iids() {
  python3 - "$1" "$2" <<'PY' 2>/dev/null
import json, re, sys
d = json.load(open(sys.argv[1]))
seen = []
for n in re.findall(r"(?<![\w/])!([0-9]+)", str(d.get("description") or "")):
    if n != sys.argv[2] and n not in seen:
        seen.append(n)
print("\n".join(seen[:5]))
PY
}

glab_call() {
  if [ "$MR_HOST" = gitlab.com ]; then
    glab "$@" </dev/null
  else
    GITLAB_HOST="$MR_HOST" glab "$@" </dev/null
  fi
}

# glab can start its errors with a blank line.
glab_error() { grep -v '^[[:space:]]*$' "$WORK/glab.err" | head -n 1 | sed 's/^[[:space:]]*//'; }

# parse_mr <url>: sets MR_HOST, MR_PROJECT and MR_IID.
parse_mr() {
  local rest="${1#https://}"
  rest="${rest#http://}"
  rest="${rest%%[?#]*}"
  rest="${rest%/}"
  MR_HOST="${rest%%/*}"
  rest="${rest#*/}"
  MR_PROJECT="${rest%%/-/merge_requests/*}"
  MR_IID="${rest##*/-/merge_requests/}"
  MR_IID="${MR_IID%%/*}"
  case "$MR_IID" in '' | *[!0-9]*) die "that doesn't look like a merge request's URL: $1" ;; esac
  case "$MR_PROJECT" in '' | */-/* | *[!A-Za-z0-9._/-]*) die "that doesn't look like a merge request's URL: $1" ;; esac
  case "$MR_HOST" in '' | *[!A-Za-z0-9.:-]*) die "that doesn't look like a merge request's URL: $1" ;; esac
}

# True if this checkout's origin is that project on that host, however the URL is written.
is_clone_of() {
  local u
  # Not remote get-url, which rewrites the URL if the user has an insteadOf for it.
  u="$(git -C "$1" config --get remote.origin.url 2>/dev/null)" || return 1
  u="${u%.git}"
  u="${u%/}"
  case "$u" in
    *://*) u="${u#*://}"; u="${u#*@}" ;;
    *@*:*) u="${u#*@}"; u="${u%%:*}/${u#*:}" ;;
  esac
  [ "$u" = "$MR_HOST/$MR_PROJECT" ]
}

find_clone() {
  local root d here
  here="$(git rev-parse --show-toplevel 2>/dev/null)" || here=""
  if [ -n "$here" ] && is_clone_of "$here"; then
    printf '%s' "$here"
    return 0
  fi
  while IFS= read -r root; do
    [ -d "$root" ] || continue
    while IFS= read -r d; do
      if is_clone_of "${d%/.git}"; then
        printf '%s' "${d%/.git}"
        return 0
      fi
    done < <(find "$root" -maxdepth 7 \( -name node_modules -o -name vendor -o -name .terraform \) -prune -o -type d -name .git -print -prune 2>/dev/null)
  done < <(printf '%s\n' "$CLONES_DIRS" | tr ':' '\n')
  return 1
}

# The first part or two of a module's path say whose it is.
module_prefix() {
  case "$1" in
    github.com/* | gitlab.com/* | bitbucket.org/*) printf '%s' "$1" | cut -d/ -f1-2 ;;
    *) printf '%s' "${1%%/*}" ;;
  esac
}

# collect_modules <clone> <commit> <own prefixes>: the libraries the MR's go.mod files pin, from
# the Go module cache, so Cowork reads the versions this MR builds against. Sets MODULES_LINE.
collect_modules() {
  local clone="$1" commit="$2" prefixes="$3" f mod ver p own json dir wanted got=0 bad=0
  MODULES_LINE="no go.mod in this repository"
  MODULES_PART=""
  wanted="$WORK/modules.wanted"
  : >"$wanted"
  while IFS= read -r f; do
    git -C "$clone" show "$commit:$f" >"$WORK/go.mod.one" 2>/dev/null || continue
    MODULES_LINE=""
    own="$prefixes"
    if [ -z "$own" ]; then
      own="$(module_prefix "$(sed -n 's/^module[[:space:]]*//p' "$WORK/go.mod.one" | head -n 1 | tr -d '"')")"
    fi
    awk '/^require[[:space:]]*\(/ { b = 1; next } b && /^\)/ { b = 0; next }
         b && NF >= 2 { print $1, $2 } /^require[[:space:]]+[^(]/ { print $2, $3 }' "$WORK/go.mod.one" |
      while read -r mod ver; do
        for p in $own; do
          case "$mod" in "$p" | "$p"/*) echo "$mod $ver" >>"$wanted" ;; esac
        done
      done
  done < <(git -C "$clone" ls-tree -r --name-only "$commit" | grep -E '(^|/)go\.mod$' | grep -vE '(^|/)vendor/')
  [ -n "$MODULES_LINE" ] || MODULES_LINE="none of its dependencies are yours"
  [ -s "$wanted" ] || return 0
  if ! command -v go >/dev/null 2>&1; then
    MODULES_LINE="left out, because go isn't on this machine"
    return 0
  fi
  mkdir -p "$WORK/go-modules"
  while read -r mod ver; do
    [ -n "$mod" ] || continue
    json="$(cd "$WORK" && GOWORK=off GOFLAGS=-mod=mod go mod download -json "$mod@$ver" 2>/dev/null)"
    printf '%s' "$json" >"$WORK/module.json"
    dir="$(json_get "$WORK/module.json" Dir)"
    if [ -n "$dir" ] && [ -d "$dir" ] && mkdir -p "$WORK/go-modules/$mod@$ver" && cp -R "$dir/." "$WORK/go-modules/$mod@$ver/"; then
      echo "$mod $ver: in go-modules/$mod@$ver" >>"$WORK/go-modules/index.txt"
      got=$((got + 1))
    else
      echo "$mod $ver: couldn't be downloaded here" >>"$WORK/go-modules/index.txt"
      bad=$((bad + 1))
    fi
  done < <(LC_ALL=C sort -u "$wanted")
  # The module cache is read-only, and the scratch folder has to be removable.
  chmod -R u+w "$WORK/go-modules"
  MODULES_LINE="$got included, $bad couldn't be downloaded, listed in go-modules/index.txt"
  MODULES_PART=go-modules
}

# want_checks <mode> <clone> <commit> <author>: whether to run this MR's checks. Sets CHECKS_LINE
# when they won't run. Asks on fd 3, because the caller's stdin is the list of URLs.
want_checks() {
  local mode="$1" clone="$2" commit="$3" author="$4" key
  if ! git -C "$clone" ls-tree -r --name-only "$commit" | grep -qE '(^|/)go\.mod$'; then
    CHECKS_LINE="not run, because this repository has no go.mod"
    return 1
  fi
  if ! command -v go >/dev/null 2>&1; then
    CHECKS_LINE="not run, because go isn't on this machine"
    return 1
  fi
  case "$mode" in
    yes) return 0 ;;
    no)
      CHECKS_LINE="not run, because the user chose not to"
      return 1
      ;;
  esac
  if ! [ -t 3 ] && [ -z "${LLM_WIKI_TEST_TTY:-}" ]; then
    CHECKS_LINE="not run, because there was no terminal to ask at"
    return 1
  fi
  echo "Run go build, vet, test and mod tidy on a temporary copy of !$MR_IID at $commit, by ${author:-an unknown author}?"
  echo "This runs that branch's code on this Mac, and sends the output to OneDrive."
  while :; do
    printf '[y]es, [n]o: '
    IFS= read -r -n 1 key <&3 || { echo; key=n; }
    [ -z "$key" ] || echo
    case "$key" in
      y | Y) return 0 ;;
      n | N)
        CHECKS_LINE="not run, because the user chose not to"
        return 1
        ;;
    esac
  done
}

# run_check <folder> <label> <output file> <command...>: one check, under a time limit.
run_check() {
  local dir="$1" label="$2" out="$3" start="$SECONDS" rc result
  shift 3
  printf '%s: ' "$label"
  (cd "$dir" && limited "$CHECK_LIMIT" "$@") >"$out" 2>&1
  rc=$?
  CHECKS_RUN=$((CHECKS_RUN + 1))
  case "$rc" in
    0) result=passed ;;
    124)
      result="stopped after ${CHECK_LIMIT}s"
      CHECKS_BAD=$((CHECKS_BAD + 1))
      ;;
    *)
      if grep -q 'flag provided but not defined: -diff' "$out"; then
        result="skipped, because this Go has no mod tidy -diff"
        CHECKS_RUN=$((CHECKS_RUN - 1))
      else
        result="FAILED, exit $rc"
        CHECKS_BAD=$((CHECKS_BAD + 1))
      fi
      ;;
  esac
  if [ "$(wc -c <"$out")" -gt 1000000 ]; then
    tail -c 1000000 "$out" >"$out.end"
    mv "$out.end" "$out"
  fi
  echo "$result ($((SECONDS - start))s)"
  echo "$label: $result ($((SECONDS - start))s)" >>"$WORK/mr/checks/summary.txt"
}

# run_checks <commit>: go checks on a clone of the bundle, so the user's clone stays out of it and
# files they haven't committed can't change a result. Sets CHECKS_LINE.
run_checks() {
  local commit="$1" tree="$WORK/checkout" f d slug label
  CHECKS_RUN=0
  CHECKS_BAD=0
  if ! git clone -q "$WORK/repo.bundle" "$tree" 2>/dev/null || ! git -C "$tree" checkout -q --detach "$commit" 2>/dev/null; then
    CHECKS_LINE="not run, because git couldn't make a temporary copy"
    echo "Checks $CHECKS_LINE."
    return 0
  fi
  mkdir -p "$WORK/mr/checks"
  {
    echo "commit: $commit"
    echo "ran on: $(uname -sm), $(go version 2>&1 | head -n 1)"
  } >"$WORK/mr/checks/summary.txt"
  while IFS= read -r f; do
    d="$(dirname "$f")"
    slug="$(printf '%s' "$d" | tr -c 'A-Za-z0-9._-' '-')"
    [ "$d" != . ] || slug=root
    label=""
    [ "$d" = . ] || label="$d: "
    run_check "$tree/$d" "${label}go build" "$WORK/mr/checks/$slug-go-build.txt" go build ./...
    run_check "$tree/$d" "${label}go vet" "$WORK/mr/checks/$slug-go-vet.txt" go vet ./...
    run_check "$tree/$d" "${label}go test" "$WORK/mr/checks/$slug-go-test.txt" go test ./...
    run_check "$tree/$d" "${label}go mod tidy -diff" "$WORK/mr/checks/$slug-go-mod-tidy.txt" go mod tidy -diff
  done < <(git -C "$tree" ls-files | grep -E '(^|/)go\.mod$' | grep -vE '(^|/)(vendor|testdata)/')
  # A build or test can leave read-only files, and the scratch folder has to be removable.
  chmod -R u+w "$tree" 2>/dev/null
  rm -rf "$tree"
  CHECKS_LINE="$CHECKS_RUN run, $CHECKS_BAD failed or stopped, in mr/checks/summary.txt"
}

# pack_mr <url> <repo override> <no-wiki flag> <go prefixes> <also notes> <checks mode>: one MR, in OneDrive.
pack_mr() {
  local url="$1" repo_arg="$2" no_wiki="$3" prefixes="$4" also_notes="$5" checks_mode="$6" clone repo name ticket source target head base start commit page out n hash size dest review existing=none
  parse_mr "$url"
  repo="${MR_PROJECT##*/}"
  name="$(printf '%s-%s' "$repo" "$MR_IID" | tr -c 'A-Za-z0-9._-' '-')"
  if [ -n "$repo_arg" ]; then
    clone="$(git -C "$repo_arg" rev-parse --show-toplevel 2>/dev/null)" || die "--repo: not a git repository: $repo_arg"
  else
    clone="$(find_clone)" || die "no clone of $MR_PROJECT under $CLONES_DIRS. Clone it, name it with --repo PATH, or change where to look with $WIKI_CMD setup copilot-cowork --clones DIR"
  fi

  WORK="$(mktemp -d "${TMPDIR:-/tmp}/llm-wiki-relay.XXXXXX")" || die "can't make a scratch folder"
  trap cleanup EXIT
  mkdir -p "$WORK/mr"
  glab_call mr view "$MR_IID" -R "$MR_PROJECT" -F json >"$WORK/mr/view.json" 2>"$WORK/glab.err" ||
    die "glab couldn't read $url: $(glab_error). Check: glab auth status"
  glab_call mr diff "$MR_IID" -R "$MR_PROJECT" --raw >"$WORK/mr/diff.patch" 2>"$WORK/glab.err" ||
    die "glab couldn't read that merge request's diff: $(glab_error)"
  glab_call api "projects/:fullpath/merge_requests/$MR_IID/versions" --repo "$MR_PROJECT" >"$WORK/mr/versions.json" 2>"$WORK/glab.err" ||
    die "glab couldn't read that merge request's versions: $(glab_error)"
  # Page through, because a long review can have more than one page of discussions.
  page=1
  while [ "$page" -le 20 ]; do
    out="$WORK/mr/discussions-$page.json"
    glab_call api "projects/:fullpath/merge_requests/$MR_IID/discussions?per_page=100&page=$page" --repo "$MR_PROJECT" >"$out" 2>"$WORK/glab.err" ||
      die "glab couldn't read that merge request's discussions: $(glab_error)"
    if [ "$(tr -d '[:space:]' <"$out")" = "[]" ]; then
      [ "$page" -eq 1 ] || rm -f "$out"
      break
    fi
    page=$((page + 1))
  done
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    glab_call api "projects/:fullpath/merge_requests/$n/discussions?per_page=100" --repo "$MR_PROJECT" >"$WORK/mr/related-$n-discussions.json" 2>/dev/null ||
      rm -f "$WORK/mr/related-$n-discussions.json"
  done < <(related_iids "$WORK/mr/view.json" "$MR_IID")

  source="$(json_get "$WORK/mr/view.json" source_branch)"
  target="$(json_get "$WORK/mr/view.json" target_branch)"
  head="$(json_get "$WORK/mr/versions.json" head_commit_sha)"
  base="$(json_get "$WORK/mr/versions.json" base_commit_sha)"
  start="$(json_get "$WORK/mr/versions.json" start_commit_sha)"
  [ -n "$source" ] && [ -n "$target" ] || die "glab's answer about $url had no branch names"
  git check-ref-format --branch "$source" >/dev/null 2>&1 || die "not a branch name: $source"
  git check-ref-format --branch "$target" >/dev/null 2>&1 || die "not a branch name: $target"
  ticket="$(ticket_of "$WORK/mr/view.json")"
  [ -n "$ticket" ] || ticket=no-ticket
  review="$ticket/$name.md"

  # Only fetches in the clone, which can hold uncommitted work. The merge request's own ref
  # works for forks too, where origin has no branch of that name.
  GIT_TERMINAL_PROMPT=0 git -C "$clone" fetch -q origin "+refs/heads/$target:refs/remotes/origin/$target" 2>/dev/null ||
    echo "Couldn't fetch $target from origin, so it's as of your last fetch." >&2
  if GIT_TERMINAL_PROMPT=0 git -C "$clone" fetch -q origin "+refs/merge-requests/$MR_IID/head:refs/remotes/origin/merge-requests/$MR_IID" 2>/dev/null; then
    SCAN_REF="refs/remotes/origin/merge-requests/$MR_IID"
  else
    GIT_TERMINAL_PROMPT=0 git -C "$clone" fetch -q origin "+refs/heads/$source:refs/remotes/origin/$source" 2>/dev/null ||
      echo "Couldn't fetch $source from origin, so it's as of your last fetch." >&2
    SCAN_REF="refs/remotes/origin/$source"
  fi
  commit="$(git -C "$clone" rev-parse --verify -q "$SCAN_REF")" || die "can't find $source in $clone, on origin or as a merge request"
  git -C "$clone" rev-parse --verify -q "refs/remotes/origin/$target" >/dev/null || die "can't find $target in $clone"

  git init -q --bare "$WORK/branch.git" || die "git couldn't make a scratch repository"
  scratch_fetch "$clone" "$WORK/branch.git" "$SCAN_REF" "refs/heads/$source" || die "git couldn't read $source from $clone"
  scratch_fetch "$clone" "$WORK/branch.git" "refs/remotes/origin/$target" "refs/heads/$target" || die "git couldn't read $target from $clone"
  git -C "$WORK/branch.git" symbolic-ref HEAD "refs/heads/$source"
  git -C "$WORK/branch.git" bundle create -q "$WORK/repo.bundle" HEAD "refs/heads/$source" "refs/heads/$target" || die "git couldn't bundle $source and $target"
  rm -rf "$WORK/branch.git"

  if [ -f "$REVIEWS_DIR/$review" ]; then
    cp "$REVIEWS_DIR/$review" "$WORK/mr/existing-review.md" || die "couldn't read $REVIEWS_DIR/$review"
    existing="yes, in mr/existing-review.md. Keep the user's edits to it"
  fi
  collect_modules "$clone" "$commit" "$prefixes"
  collect_wiki "$repo" "$no_wiki"
  if want_checks "$checks_mode" "$clone" "$commit" "$(json_get "$WORK/mr/view.json" author.name)"; then
    run_checks "$commit"
  fi

  make_archive "$WORK/$name.tar.gz" -C "$WORK" repo.bundle mr ${MODULES_PART:+"$MODULES_PART"} ${WIKI_PART:+"$WIKI_PART"} || die "tar couldn't make the archive"
  hash="$(sha256_of "$WORK/$name.tar.gz")"
  size="$(wc -c <"$WORK/$name.tar.gz" | tr -d ' ')"
  {
    echo "LLM-WIKI RELAY MERGE REQUEST"
    echo "url: $url"
    echo "project: $MR_PROJECT"
    echo "iid: $MR_IID"
    echo "title: $(json_get "$WORK/mr/view.json" title)"
    echo "author: $(json_get "$WORK/mr/view.json" author.name)"
    echo "ticket: $ticket"
    echo "source branch: $source"
    echo "target branch: $target"
    echo "head: ${head:-unknown}"
    echo "base: ${base:-unknown}"
    echo "start: ${start:-unknown}"
    echo "commit: $commit"
    [ -z "$head" ] || [ "$head" = "$commit" ] || echo "warning: the branch in the archive is at $commit, but GitLab says the merge request's head is $head"
    echo "taken: $(now)"
    echo "wiki: $WIKI_LINE"
    echo "go modules: $MODULES_LINE"
    echo "changed files: $(grep -c '^diff --git' "$WORK/mr/diff.patch")"
    echo "checks: $CHECKS_LINE"
    echo "earlier review: $existing"
    echo "review goes in the deliverable at: reviews/$review"
    if [ -n "$also_notes" ]; then
      echo "other repositories, each with a note like this one:"
      printf '%s\n' "$also_notes" | sed 's/^/  /'
    fi
    echo "tools on this machine:"
    list_tools
    echo "archive: $name.tar.gz"
    echo "archive sha256: $hash"
    echo "archive bytes: $size"
  } >"$WORK/$name.txt"
  dest="$COWORK/relay/mrs"
  mkdir -p "$dest" || die "can't create $dest"
  cp "$WORK/$name.tar.gz" "$dest/" || die "couldn't copy the archive to $dest"
  cp "$WORK/$name.txt" "$dest/" || die "couldn't copy the note to $dest"
  echo "Packed $MR_PROJECT !$MR_IID: $source at $commit, against $target, $size bytes"
  [ -z "$WIKI_PART" ] || echo "Included the $WIKI_NAME wiki (compiled pages: $WIKI_PAGES, no raw notes). Add --no-wiki to leave it out."
  [ -z "$MODULES_PART" ] || echo "Go modules: $MODULES_LINE"
  echo "Checks: $CHECKS_LINE"
  [ "$existing" = none ] || echo "Included your earlier review, $REVIEWS_DIR/$review"
  [ -z "$head" ] || [ "$head" = "$commit" ] || echo "Warning: the branch here is at $commit, but GitLab says the merge request's head is $head."
  size_warning "$size"
  echo "Sent to OneDrive: Documents/Cowork/relay/mrs/$name.txt and $name.tar.gz"
}

cmd_mr() {
  local urls="" also="" also_notes="" repo_arg="" no_wiki="" prefixes="" checks="" url spec note prompt names=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --also)
        [ -n "${2:-}" ] || die "--also needs a path"
        also="$also$2
"
        shift 2
        ;;
      --repo)
        [ -n "${2:-}" ] || die "--repo needs a path"
        repo_arg="$2"
        shift 2
        ;;
      --go-prefix)
        [ -n "${2:-}" ] || die "--go-prefix needs a module prefix"
        prefixes="$prefixes $2"
        shift 2
        ;;
      --checks) checks=yes; shift ;;
      --no-checks) checks=no; shift ;;
      --no-wiki) no_wiki=1; shift ;;
      -h | --help) usage; return 0 ;;
      -*) die "relay mr: unknown option $1. Try $WIKI_CMD relay --help" ;;
      *)
        urls="$urls$1
"
        shift
        ;;
    esac
  done
  [ -n "$urls" ] || die "relay mr needs a merge request's URL"
  command -v glab >/dev/null 2>&1 || die "relay mr needs glab"
  command -v python3 >/dev/null 2>&1 || die "relay mr needs python3"
  while IFS= read -r url; do
    [ -n "$url" ] || continue
    parse_mr "$url"
    names="$names$(printf '%s-%s' "${MR_PROJECT##*/}" "$MR_IID" | tr -c 'A-Za-z0-9._-' '-')
"
  done <<EOF
$urls
EOF
  while IFS= read -r spec; do
    [ -n "$spec" ] || continue
    note="$(send_also "$spec")" || exit 1
    also_notes="$also_notes$note
"
  done <<EOF
$also
EOF
  also_notes="${also_notes%
}"
  exec 3<&0
  while IFS= read -r url; do
    [ -n "$url" ] || continue
    (pack_mr "$url" "$repo_arg" "$no_wiki" "$prefixes" "$also_notes" "$checks") || exit 1
  done <<EOF
$urls
EOF
  prompt="Use remote-pair-run to review this merge request, following its section on merge requests. With no attachment, read these notes from my OneDrive, and get the archives they name:"
  while IFS= read -r note; do
    [ -n "$note" ] || continue
    prompt="$prompt
- Documents/Cowork/relay/mrs/$note.txt"
  done <<EOF
$names
EOF
  prompt="$prompt
If I have a skill for reviewing merge requests, follow all of it for the review and the file it writes. Finish with a verdict: are these changes solid, and what has to change before this merges? Say what you didn't cover. When a finding depends on running the code, or you need another repository or config, ask me, with one line on why."
  echo
  if command -v pbcopy >/dev/null 2>&1 && printf '%s\n' "$prompt" | pbcopy 2>/dev/null; then
    echo "Paste this into Cowork. It's on your clipboard:"
  else
    echo "Paste this into Cowork:"
  fi
  echo
  printf '%s\n' "$prompt"
}

# ---- review ------------------------------------------------------------------

# Cowork names the files, so each has to be reviews/<ticket>/<name>.md, and nothing else.
review_files() {
  local p t f
  while IFS= read -r p; do
    case "$p" in
      reviews/*)
        t="${p#reviews/}"
        f="${t#*/}"
        t="${t%%/*}"
        case "$t" in '' | .* | *[!A-Za-z0-9._-]*) die "a review can't go at $p" ;; esac
        case "$f" in '' | .* | */* | *[!A-Za-z0-9._-]*) die "a review can't go at $p" ;; *.md) ;; *) die "a review can't go at $p" ;; esac
        echo "$t/$f"
        ;;
    esac
  done < <(manifest_paths "$1")
}

# A review of an old head can still be worth keeping, so this warns and goes on.
warn_if_moved() {
  local f="$1" note old_sha now_sha
  note="$COWORK/relay/mrs/${f##*/}"
  note="${note%.md}.txt"
  [ -f "$note" ] && command -v glab >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 || return 0
  old_sha="$(sed -n 's/^commit: //p' "$note" 2>/dev/null | head -n 1)"
  parse_mr "$(sed -n 's/^url: //p' "$note" 2>/dev/null | head -n 1)" 2>/dev/null || return 0
  glab_call mr view "$MR_IID" -R "$MR_PROJECT" -F json >"$WORK/now.json" 2>/dev/null || return 0
  now_sha="$(json_get "$WORK/now.json" sha)"
  [ -z "$now_sha" ] || [ -z "$old_sha" ] || [ "$now_sha" = "$old_sha" ] ||
    echo "Warning: ${f##*/} reviews $old_sha, but the merge request is now at $now_sha."
}

# What Cowork says it skipped has to be seen before saving. It comes from the cloud, so control
# characters don't reach the terminal.
show_coverage() {
  local file="$1" name="$2"
  if ! grep -qE '^##+ Coverage' "$file"; then
    echo "Warning: $name has no Coverage section, so you can't tell what Cowork skipped. Ask it to add one."
    return 0
  fi
  echo "What $name says it covered:"
  awk '/^##+ Coverage/ { on = 1; next } on && /^#/ { exit } on' "$file" | sed '/^[[:space:]]*$/d' | head -n 30 | LC_ALL=C tr -d '\000-\010\013-\037\177' | sed 's/^/  /'
}

cmd_review() {
  local named="" where="" expect="" copy version a task f files dest
  while [ $# -gt 0 ]; do
    case "$1" in
      --expect)
        [ -n "${2:-}" ] || die "--expect needs a version"
        expect="$2"
        shift 2
        ;;
      -h | --help) usage; return 0 ;;
      -*) die "relay review: unknown option $1. Try $WIKI_CMD relay --help" ;;
      *)
        [ -z "$where" ] || die "relay review takes one deliverable"
        where="$1"
        shift
        ;;
    esac
  done
  [ -n "$where" ] || die "relay review needs a deliverable, as TASK-FOLDER/DELIVERABLE"
  named="$(deliverable_path "$where")" || exit 1
  needs_terminal review
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/llm-wiki-relay.XXXXXX")" || die "can't make a scratch folder"
  trap cleanup EXIT
  copy="$WORK/deliverable"
  RUNLIB_EXPECT="$expect"
  RUNLIB_NEEDS=""
  wait_for_deliverable "$named" "$copy" || return 1
  version="$(_runlib_manifest_version "$copy/manifest.txt")"
  a="${SRC%/*}"
  task="$(basename "${a%/*}")"
  files="$(review_files "$copy")" || exit 1
  [ -n "$files" ] || die "that deliverable has nothing under reviews/"
  echo
  echo "Deliverable: $task/$(basename "$SRC")"
  echo "Version:     $version"
  echo "Saving to:   $REVIEWS_DIR"
  while IFS= read -r f; do
    if [ -f "$REVIEWS_DIR/$f" ]; then
      echo "  $f ($(wc -c <"$copy/reviews/$f" | tr -d ' ') bytes, replaces yours, which is kept as ${f##*/}.previous)"
    else
      echo "  $f ($(wc -c <"$copy/reviews/$f" | tr -d ' ') bytes, new)"
    fi
    warn_if_moved "$f"
    show_coverage "$copy/reviews/$f" "${f##*/}"
  done <<EOF
$files
EOF
  echo
  if ! ask_to_run "$copy" "Save it?"; then
    echo "Nothing was saved."
    return 1
  fi
  while IFS= read -r f; do
    dest="$REVIEWS_DIR/$f"
    mkdir -p "$(dirname "$dest")" || die "can't create $(dirname "$dest")"
    if [ -f "$dest" ] && ! cmp -s "$dest" "$copy/reviews/$f"; then
      cp "$dest" "$dest.previous" || die "couldn't keep your copy of $dest, so nothing replaced it"
    fi
    cp "$copy/reviews/$f" "$dest" || die "couldn't save $dest"
    echo "Saved: $dest"
    [ ! -f "$dest.previous" ] || echo "Your earlier copy: $dest.previous"
  done <<EOF
$files
EOF
}

# ---- apply -------------------------------------------------------------------

cmd_apply() {
  local named="" where="" expect="" repo_arg="" root copy version a task p patches="" done_list="" report key
  while [ $# -gt 0 ]; do
    case "$1" in
      --expect)
        [ -n "${2:-}" ] || die "--expect needs a version"
        expect="$2"
        shift 2
        ;;
      --repo)
        [ -n "${2:-}" ] || die "--repo needs a path"
        repo_arg="$2"
        shift 2
        ;;
      -h | --help) usage; return 0 ;;
      -*) die "relay apply: unknown option $1. Try $WIKI_CMD relay --help" ;;
      *)
        [ -z "$where" ] || die "relay apply takes one deliverable"
        where="$1"
        shift
        ;;
    esac
  done
  [ -n "$where" ] || die "relay apply needs a deliverable, as TASK-FOLDER/DELIVERABLE"
  [ -n "$repo_arg" ] || die "relay apply needs --repo PATH, the repository to change"
  root="$(git -C "$repo_arg" rev-parse --show-toplevel 2>/dev/null)" || die "--repo: not a git repository: $repo_arg"
  named="$(deliverable_path "$where")" || exit 1
  needs_terminal apply
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/llm-wiki-relay.XXXXXX")" || die "can't make a scratch folder"
  trap cleanup EXIT
  copy="$WORK/deliverable"
  RUNLIB_EXPECT="$expect"
  RUNLIB_NEEDS=""
  wait_for_deliverable "$named" "$copy" || return 1
  version="$(_runlib_manifest_version "$copy/manifest.txt")"
  a="${SRC%/*}"
  task="$(basename "${a%/*}")"
  while IFS= read -r p; do
    case "$p" in *.patch) patches="$patches$p
" ;; esac
  done < <(manifest_paths "$copy")
  [ -n "$patches" ] || die "that deliverable has no patches"
  echo
  echo "Deliverable: $task/$(basename "$SRC")"
  echo "Version:     $version"
  echo "Repository:  $root, on $(git -C "$root" symbolic-ref -q --short HEAD || echo 'a detached HEAD')"
  echo "Patches:"
  printf '%s' "$patches" | sed 's/^/  /'
  # A patch that never passed a run can still be what someone wants, but they should know.
  report=""
  for key in "$COWORK/relay/$task/reports"/*-v"$version"-*.txt; do
    [ -f "$key" ] && report="$key"
  done
  if [ -z "$report" ]; then
    echo "Warning: there's no report from a run of version $version."
  elif ! tail -n 1 "$report" | grep -q ' RUN: PASS$'; then
    echo "Warning: the last run of version $version didn't pass."
  fi
  echo
  if ! ask_to_run "$copy" "Apply it, uncommitted?"; then
    echo "Nothing changed."
    return 1
  fi
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if git -C "$root" apply "$copy/$p"; then
      done_list="$p
$done_list"
    else
      echo "$p doesn't apply, so I'm undoing the rest and leaving the repository as it was." >&2
      while IFS= read -r a; do
        [ -n "$a" ] || continue
        git -C "$root" apply -R "$copy/$a" || echo "Couldn't undo $a. Check the repository with git status." >&2
      done <<EOF
$done_list
EOF
      return 1
    fi
  done <<EOF
$patches
EOF
  echo "Applied, and nothing is committed. Look it over with: git -C $root diff"
  git -C "$root" status --short
}

case "${1:-}" in
  run) shift; cmd_run "$@"; exit $? ;;
  scan) shift; cmd_scan "$@"; exit $? ;;
  mr) shift; cmd_mr "$@"; exit $? ;;
  review) shift; cmd_review "$@"; exit $? ;;
  apply) shift; cmd_apply "$@"; exit $? ;;
  "" | -h | --help) usage ;;
  *) usage >&2; exit 2 ;;
esac
