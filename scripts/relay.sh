#!/usr/bin/env bash
# wiki relay: the Mac's side of the remote pair-run loop with Microsoft Copilot Cowork.
#
#   relay run    Wait for a deliverable, copy it out of OneDrive, and run the copy on a keypress.
#   relay scan   Put a repository in OneDrive for Cowork to read, in place of an attached scan.
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
REPORTS="${RUNLIB_REPORT_DIR:-$HOME/pair-run-reports}"
WORK=""

cleanup() { [ -z "$WORK" ] || rm -rf "$WORK"; }

usage() {
  cat <<EOF
Usage: $WIKI_CMD relay [--dir ONEDRIVE_FOLDER] run [TASK-FOLDER/DELIVERABLE] [--expect VERSION] [--no-install]
       $WIKI_CMD relay [--dir ONEDRIVE_FOLDER] scan [REPOSITORY]

  run    Waits until a deliverable from Copilot Cowork matches its manifest, copies it to a
         local folder, shows you what's there, and runs the copy when you press y. If it gives up, it says what this Mac sees. The report
         goes to Documents/Cowork/relay/<task-folder>/reports in OneDrive, only if a run
         happened. Then tell Cowork "done". With no deliverable named, it uses the newest.
  scan   Puts the repository's current branch and uncommitted changes in OneDrive, at
         Documents/Cowork/relay/scans, with a note of the commit and tool versions. Untracked
         files stay out. Defaults to the repository you're in.
EOF
}

# ---- run ---------------------------------------------------------------------

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

# macOS decides this per terminal app: iTerm was refused for over an hour while Apple's
# Terminal read the same files at once. So say it the moment it shows, not after the wait.
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
      [ "$p" = runlib.sh ] && continue
      printf '\n===== %s =====\n' "$p"
      cat "$copy/$p"
    done < <(manifest_paths "$copy")
  } | ${PAGER:-less}
}

# Nothing from the cloud runs until someone says so here.
ask_to_run() {
  local copy="$1" key
  while :; do
    printf 'Run it? [y]es, [v]iew the files, [n]o: '
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
    case "$where" in
      */*/* | /* | */ | ..* | */..) die "name a deliverable as TASK-FOLDER/DELIVERABLE: $where" ;;
      */*) named="$COWORK/Tasks/${where%%/*}/output/${where#*/}" ;;
      *) die "name a deliverable as TASK-FOLDER/DELIVERABLE: $where" ;;
    esac
  fi
  [ -t 0 ] || [ -n "${LLM_WIKI_TEST_TTY:-}" ] || die "relay run asks before it runs anything, so it needs a terminal. Agents: tell the user to run it."

  WORK="$(mktemp -d "${TMPDIR:-/tmp}/llm-wiki-relay.XXXXXX")" || die "can't make a scratch folder"
  trap cleanup EXIT
  copy="$WORK/deliverable"
  RUNLIB_EXPECT="$expect"
  echo "Relay run started at $(now)."
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
  echo "Relay run ended at $(now)."
  return "$rc"
}

# ---- scan --------------------------------------------------------------------

cmd_scan() {
  local dir="." root name branch commit t size hash dest dirty=no
  while [ $# -gt 0 ]; do
    case "$1" in
      -h | --help) usage; return 0 ;;
      -*) die "relay scan: unknown option $1. Try $WIKI_CMD relay --help" ;;
      *) dir="$1"; shift ;;
    esac
  done
  root="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || die "not a git repository: $dir"
  commit="$(git -C "$root" rev-parse --verify -q HEAD)" || die "$root has no commits yet"
  name="$(basename "$root" | tr -c 'A-Za-z0-9._\n-' '-')"
  [ -n "$name" ] || die "can't name a scan after $root"
  branch="$(git -C "$root" symbolic-ref -q --short HEAD)" || branch=""

  WORK="$(mktemp -d "${TMPDIR:-/tmp}/llm-wiki-relay.XXXXXX")" || die "can't make a scratch folder"
  trap cleanup EXIT
  if [ -n "$branch" ]; then
    git -C "$root" bundle create -q "$WORK/repo.bundle" HEAD "refs/heads/$branch" || die "git couldn't bundle $root"
  else
    git -C "$root" bundle create -q "$WORK/repo.bundle" HEAD || die "git couldn't bundle $root"
  fi
  git -C "$root" diff HEAD --binary >"$WORK/uncommitted.patch" || die "git couldn't read the uncommitted changes"
  [ -s "$WORK/uncommitted.patch" ] && dirty=yes
  {
    echo "LLM-WIKI RELAY SCAN"
    echo "repository: $name"
    echo "path: $root"
    echo "branch: ${branch:-detached}"
    echo "commit: $commit"
    echo "taken: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    if [ "$dirty" = yes ]; then
      echo "uncommitted changes: yes, in uncommitted.patch"
    else
      echo "uncommitted changes: no, uncommitted.patch is empty"
    fi
    echo "status (untracked files, marked ??, are not in the archive):"
    git -C "$root" status --short | head -n 200 | sed 's/^/  /'
    echo "tools:"
    for t in go git buf protoc python3 node; do
      command -v "$t" >/dev/null 2>&1 || continue
      if [ "$t" = go ]; then
        echo "  go: $(go version 2>&1 | head -n 1)"
      else
        echo "  $t: $("$t" --version 2>&1 | head -n 1)"
      fi
    done
  } >"$WORK/scan.txt"
  # COPYFILE_DISABLE keeps macOS's tar from adding ._ files.
  COPYFILE_DISABLE=1 tar -czf "$WORK/$name.tar.gz" -C "$WORK" repo.bundle uncommitted.patch scan.txt || die "tar couldn't make the archive"
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
  echo "Scanned $name: ${branch:-detached HEAD} at $commit, $size bytes, uncommitted changes: $dirty"
  echo "Sent to OneDrive: Documents/Cowork/relay/scans/$name.txt and $name.tar.gz"
  echo "Now tell Cowork: read Documents/Cowork/relay/scans/$name.txt"
}

case "${1:-}" in
  run) shift; cmd_run "$@"; exit $? ;;
  scan) shift; cmd_scan "$@"; exit $? ;;
  "" | -h | --help) usage ;;
  *) usage >&2; exit 2 ;;
esac
