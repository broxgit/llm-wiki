#!/usr/bin/env bash
# Smoke tests for wiki.sh, the plugin's session hook, and the secret scan.
# Everything runs in a temp folder with its own HOME, so real wikis and settings are
# never touched. Works with the bash that ships on macOS (3.2) and on Linux.
#
#   tests/smoke.sh              the whole suite
#   tests/smoke.sh --part <n>   one part of it, as CI runs it: one job per part
#   tests/smoke.sh --list       which part each section is in
#
# SMOKE_TIMES=1 prints how long each section took, for balancing the parts.
# tests/smoke-parts.sh checks that the parts add up to the whole suite.
# The secret-scan tests run only when gitleaks is installed. CI installs it.
set -u

# Each section is in one part. A section also names the earlier sections whose state
# it uses, such as a wiki they made. A part runs its own sections and, without
# counting their checks, the ones they use from other parts, in the suite's order.
# Keep the parts' times close: CI waits for the slowest. docs/maintaining.md has more.
#
# part | section | uses
# Read, not $(cat <<...): bash 3.2 can't parse a quote inside a here-document in $( ).
read -r -d '' PARTS <<'TABLE' || true
1 | Collection |
1 | What a new wiki gets | Collection
1 | Upgrade | Collection
1 | Two clones merge index.md and log.md | Collection
1 | Secret scan | Collection
1 | Session hook | Collection
1 | Links and plugin mode | Collection
1 | Seed | Collection
1 | Pending and bulk compile | Seed, Session hook
1 | Team skills | Seed, Session hook
4 | Tips | Team skills, Session hook
3 | Tab completion | Collection
1 | Weekly report | Seed, Session hook
3 | Bookkeeping commands | Collection
3 | Background compile | Session hook
3 | Reminders | Two clones merge index.md and log.md, Session hook
3 | Index and lint | Collection
3 | Setup fit | Session hook
3 | Harvest Claude Code memory | Session hook
3 | Setup fixes | Collection
3 | Stats | Collection
3 | Plugin updates reach the wiki command | Session hook
2 | Journal and standup | Collection
2 | Commit distance | Journal and standup
2 | Dependency map | Journal and standup
3 | Sync takes turns | Two clones merge index.md and log.md, Seed
3 | Session start in one call | Two clones merge index.md and log.md
3 | A folder of clones | Collection
3 | Patterns for where a session is | Collection
3 | A remote the branch doesn't track | Two clones merge index.md and log.md
4 | Antigravity plugin | Session hook, Team skills
4 | Codex plugin | Session hook, Team skills
4 | Cursor | Session hook, Team skills
4 | Feedback on llm-wiki | Session hook
4 | MCP server | Two clones merge index.md and log.md
4 | Compiled without summary pages (v24) | Collection
4 | Claude Code permissions |
4 | Collections | Session hook
2 | Bash 3.2 safety |
2 | Missing flag values | Collection
3 | Update | Two clones merge index.md and log.md
2 | News |
2 | Terminal style |
2 | What moved to llm-relay |
2 | Extensions | Collection
2 | Jira extension | Collection
2 | Confluence extension | Collection
2 | Extension events | Collection
2 | Content as data | Collection
3 | Tour |
4 | The released helper | Session hook
TABLE
PART=""
case "${1:-}" in
  "") ;;
  --part) PART="${2:-}" ;;
  --list) printf '%s\n' "$PARTS" | awk -F ' *[|] *' 'NF >= 2 { print $1 "\t" $2 }'; exit 0 ;;
  *) printf 'usage: tests/smoke.sh [--part <n> | --list]\n' >&2; exit 2 ;;
esac
# Each section's mode in this run: run, setup or skip. A use must name an earlier section.
PLAN="$(printf '%s\n' "$PARTS" | awk -F ' *[|] *' -v part="$PART" '
  function use(s,   i, k, a) {
    k = split(uses[s], a, / *, */)
    for (i = 1; i <= k; i++) if (!(a[i] in mode)) { mode[a[i]] = "setup"; use(a[i]) }
  }
  NF >= 2 { n++; name[n] = $2; p[$2] = $1; uses[$2] = $3; at[$2] = n; if ($1 == part) found = 1 }
  END {
    if (part != "" && !found) { print "no part " part " in the table at the top of tests/smoke.sh" > "/dev/stderr"; exit 2 }
    for (i = 1; i <= n; i++) {
      k = split(uses[name[i]], a, / *, */)
      for (j = 1; j <= k; j++) if (!(a[j] in at) || at[a[j]] >= i) { print name[i] " uses \"" a[j] "\", which isn'"'"'t a section before it" > "/dev/stderr"; exit 2 }
    }
    for (i = 1; i <= n; i++) if (part == "" || p[name[i]] == part) { mode[name[i]] = "run"; use(name[i]) }
    for (i = 1; i <= n; i++) print (name[i] in mode ? mode[name[i]] : "skip") "\t" name[i]
  }')" || exit 2

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
W="$REPO/wiki.sh"
T="$(mktemp -d)"
T="$(cd "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT

export HOME="$T/home"
# Settings and state live under $HOME. GitHub's Linux runners set XDG_CONFIG_HOME to
# the runner's own folder, which a part would otherwise read.
unset XDG_CONFIG_HOME XDG_STATE_HOME XDG_DATA_HOME XDG_CACHE_HOME
export WIKIS_DIR="$T/wikis"
# Nothing here may depend on a terminal: style is off unless a test turns it on.
export LLM_WIKI_STYLE=off
# The fixtures are dated with `date -u`, and the report's range ends on the journal's
# day, which is the local date, or the day before until day_starts. One clock for both:
# UTC here, and day_starts 00:00 once the collection exists. Without it the report
# checks failed from midnight to 04:00 UTC in CI, and in the evening on a Mac.
export TZ=UTC
# Released helpers come from a folder here, never the network.
export LLM_WIKI_HELPER_BASE="file://$T/release"
mkdir -p "$HOME" "$T/bin"
git config --global user.email smoke@example.com
git config --global user.name "Smoke Test"
git config --global init.defaultBranch main

# The news is read, so a first run's line doesn't appear in every status below.
"$REPO/wiki.sh" news >/dev/null
TV="$(sed -n 's/^Handbook version \([0-9][0-9]*\).*/\1/p' "$REPO/template/AGENTS.md" | head -n 1)"
pass=0
fail=0
skip=0

# A section run only to set up a part counts its failures, not its passes.
section_mode=run
ok() { [ "$section_mode" = setup ] || { pass=$((pass + 1)); printf 'ok    %s\n' "$1"; }; }
bad() {
  fail=$((fail + 1))
  if [ "$section_mode" = setup ]; then printf 'FAIL  %s (while setting up this part)\n' "$1"; else printf 'FAIL  %s\n' "$1"; fi
  [ -z "${2:-}" ] || printf '%s\n' "$2" | head -n 15 | sed 's/^/        /'
}
skipped() { [ "$section_mode" = setup ] || { skip=$((skip + 1)); printf 'skip  %s\n' "$1"; }; }
clock() { perl -MTime::HiRes=time -e 'printf "%.1f", time'; }
# section_time: how long the section that just ended took, with SMOKE_TIMES=1.
section_time() { [ -z "${SMOKE_TIMES:-}" ] || [ -z "${section_start:-}" ] || awk -v a="$section_start" -v b="$(clock)" -v s="$1" 'BEGIN { printf "time  %5.1fs  %s\n", b - a, s }'; }
# section <name>: starts a section, and fails when this run skips it.
section() {
  section_time "${section_name:-}"
  section_name="$1"
  [ -z "${SMOKE_TIMES:-}" ] || section_start="$(clock)"
  section_mode="$(printf '%s\n' "$PLAN" | awk -F '\t' -v s="$1" '$2 == s { print $1; exit }')"
  case "$section_mode" in
    run) printf '\n# %s\n' "$1" ;;
    setup) printf '\n# %s, to set up this part\n' "$1" ;;
    skip) return 1 ;;
    *)
      section_mode=run
      printf '\n# %s\n' "$1"
      bad "the section has a part in the table at the top of tests/smoke.sh"
      [ -z "$PART" ] || return 1
      ;;
  esac
}

# check <name> <command...>: the command succeeds.
check() {
  local name="$1" out
  shift
  if out="$("$@" 2>&1)"; then ok "$name"; else bad "$name" "$out"; fi
}
# refuse <name> <command...>: the command fails.
refuse() {
  local name="$1" out
  shift
  if out="$("$@" 2>&1)"; then bad "$name (it succeeded)" "$out"; else ok "$name"; fi
}
# expect <name> <text> <command...>: the output contains text, whatever the exit code.
expect() {
  local name="$1" want="$2" out
  shift 2
  out="$("$@" 2>&1)"
  case "$out" in *"$want"*) ok "$name" ;; *) bad "$name (no \"$want\")" "$out" ;; esac
}
# lacks <name> <text> <command...>: the output doesn't contain text.
lacks() {
  local name="$1" unwanted="$2" out
  shift 2
  out="$("$@" 2>&1)"
  case "$out" in *"$unwanted"*) bad "$name (has \"$unwanted\")" "$out" ;; *) ok "$name" ;; esac
}
set_version() { sed "s/^Handbook version [0-9]*\./Handbook version $2./" "$1" > "$1.tmp" && mv "$1.tmp" "$1"; }
# hook <project dir> [stdin json]
hook() { printf '%s' "${2:-}" | CLAUDE_PLUGIN_ROOT="$REPO" CLAUDE_PLUGIN_DATA="$T/data" CLAUDE_PROJECT_DIR="$1" bash "$REPO/hooks/session-start.sh"; }
# context <json>: the additionalContext from hook output, or a parse error.
context() {
  python3 -c 'import json, sys
d = json.load(sys.stdin)["hookSpecificOutput"]
assert d["hookEventName"] == "SessionStart"
print(d["additionalContext"])'
}
mkskill() { mkdir -p "$1" && printf -- '---\nname: %s\ndescription: %s\n---\n\nSteps.\n' "${1##*/}" "$2" > "$1/SKILL.md"; }
# setup wants a terminal for its questions. The tests answer through a pipe.
in_tty() { LLM_WIKI_TEST_TTY=1 "$@"; }
# build_helper: the compiled helper, in $T/bin/llm-wiki, two stand-ins for a helper
# gone wrong, one built for another protocol and one that fails, and a spy on a good one.
build_helper() {
  (cd "$REPO" && go build -o "$T/bin/llm-wiki" ./cmd/llm-wiki) || return 1
  printf '#!/bin/sh\n[ "$1" = protocol ] && { echo 0; exit 0; }\necho "STALE TABLE"\n' > "$T/bin/stale-helper"
  printf '#!/bin/sh\n[ "$1" = protocol ] && { sed -n "s/^GO_PROTOCOL=//p" "%s"; exit 0; }\nexit 1\n' "$W" > "$T/bin/broken-helper"
  # And one that works, and notes each command it was run for in $T/helper-ran.
  printf '#!/bin/sh\necho "$1" >> "%s"\nexec "%s" "$@"\n' "$T/helper-ran" "$T/bin/llm-wiki" > "$T/bin/spy-helper"
  chmod +x "$T/bin/stale-helper" "$T/bin/broken-helper" "$T/bin/spy-helper"
}

if section "Collection"; then
expect "init --git makes the first commit" "first commit made" "$W" init --git
check "and a new collection ignores what Obsidian writes" bash -c "grep -qxF .obsidian/ '$WIKIS_DIR/.gitignore' && grep -qxF .trash/ '$WIKIS_DIR/.gitignore'"
"$W" journal set day_starts 00:00 >/dev/null
check "the collection is a git repo" git -C "$WIKIS_DIR" rev-parse --is-inside-work-tree
check "the shared wiki starts with a conventions page" grep -q '^## For agents' "$WIKIS_DIR/global/wiki/conventions.md"
check "the shared index lists it" grep -q 'wiki/conventions.md' "$WIKIS_DIR/global/index.md"
expect "new creates a wiki" "created:" "$W" new demo
refuse "new refuses a name with a space" "$W" new "My Repo"
refuse "new refuses a wiki inside the template repo" "$W" new "$REPO/template/inside"
mkdir -p "$T/sub"
check "new resolves .. in a path" bash -c "cd '$T/sub' && '$W' new ../rel && test -f '$T/rel/AGENTS.md'"
expect "cover lists repositories" "covers:  api" "$W" cover demo api web
expect "which finds a covered repository" "demo" "$W" which web
refuse "which fails for an unknown repository" "$W" which nothing
printf -- '- [Deploy flow](wiki/howto/deploy.md): blue-green behind the canary gate\n' >> "$WIKIS_DIR/demo/index.md"
expect "find searches indexes" "Deploy flow" "$W" find canary
expect "find takes several words as one phrase" "Deploy flow" "$W" find blue-green behind
refuse "a command with one target still refuses a second" "$W" which web api
expect "find skips index headings" "no mentions" "$W" find Index
mkdir -p "$T/ro-config/llm-wiki" && chmod 555 "$T/ro-config/llm-wiki"
expect "find works when its usage record can't be written, as in a read-only sandbox" "Deploy flow" env XDG_CONFIG_HOME="$T/ro-config" "$W" find canary
chmod 755 "$T/ro-config/llm-wiki"
mkdir -p "$WIKIS_DIR/demo/wiki/howto" && printf -- '---\ntitle: Deploy\nsummary: How deploys run.\n---\n\nSet DEPLOY_TOKEN_FILE before the run.\n' > "$WIKIS_DIR/demo/wiki/howto/deploy.md"
expect "find also searches page text" "wiki/howto/deploy.md: Set DEPLOY_TOKEN_FILE" "$W" find deploy_token_file
out="$("$W" find canary 2>&1)"
case "$out" in *"also in pages"*"deploy.md"*) bad "find doesn't repeat a page its index line already showed" "$out" ;; *) ok "find doesn't repeat a page its index line already showed" ;; esac
expect "claude --print prints the line" "knowledge wikis live in" "$W" claude --print
check "claude --print writes nothing" test ! -e "$HOME/.claude/CLAUDE.md"
expect "the line says what wiki.sh means, for agents without the hook" "Wherever their handbooks say \`wiki.sh\`, run" "$W" claude --print
fi

if section "What a new wiki gets"; then
for f in .gitattributes .gitignore patterns.md open.md links.md repos.md rules/peers.md rules/compile.md rules/open.md; do
  check "demo has $f" test -f "$WIKIS_DIR/demo/$f"
done
expect "index.md merges by union" "merge: union" git -C "$WIKIS_DIR" check-attr merge -- demo/index.md
expect "log.md merges by union" "merge: union" git -C "$WIKIS_DIR" check-attr merge -- demo/log.md
check "delegation.md is git-ignored" git -C "$WIKIS_DIR" check-ignore -q delegation.md
check "the secret-scan hook is installed" grep -q "llm-wiki secret scan" "$WIKIS_DIR/.git/hooks/pre-commit"
fi

if section "Upgrade"; then
set_version "$WIKIS_DIR/demo/AGENTS.md" 12
rm -f "$WIKIS_DIR/demo/patterns.md" "$WIKIS_DIR/demo/.gitattributes" "$WIKIS_DIR/demo/open.md" "$WIKIS_DIR/demo/rules/open.md"
out="$("$W" upgrade demo 2>&1)"
case "$out" in *"handbook: v12 -> v$TV"*) ok "upgrade moves the handbook to v$TV" ;; *) bad "upgrade moves the handbook to v$TV" "$out" ;; esac
case "$out" in *"What's new since v12"*) ok "upgrade prints the changelog" ;; *) bad "upgrade prints the changelog" "$out" ;; esac
check "upgrade restores patterns.md" test -f "$WIKIS_DIR/demo/patterns.md"
check "upgrade gives an old wiki open.md and rules/open.md" test -f "$WIKIS_DIR/demo/open.md" -a -f "$WIKIS_DIR/demo/rules/open.md"
rm "$WIKIS_DIR/global/wiki/conventions.md"
"$W" upgrade --all >/dev/null 2>&1
check "upgrade recreates a missing conventions page" test -f "$WIKIS_DIR/global/wiki/conventions.md"
check "without listing it twice" test "$(grep -c 'wiki/conventions.md' "$WIKIS_DIR/global/index.md")" -eq 1
check "upgrade restores .gitattributes" test -f "$WIKIS_DIR/demo/.gitattributes"
case "$out" in *"Committed the upgrade"*) ok "upgrade commits its own changes" ;; *) bad "upgrade commits its own changes" "$out" ;; esac
check "a wiki's rules/delegation.md isn't git-ignored" bash -c "! git -C '$WIKIS_DIR' check-ignore -q demo/rules/delegation.md"
set_version "$WIKIS_DIR/demo/AGENTS.md" 999
expect "status flags a wiki ahead of the template" "ahead of your template" "$W" status
expect "upgrade leaves a newer wiki alone" "newer than your template" "$W" upgrade demo
check "the newer handbook is untouched" grep -q "Handbook version 999" "$WIKIS_DIR/demo/AGENTS.md"
set_version "$WIKIS_DIR/demo/AGENTS.md" "$TV"
lacks "status is quiet once current" "behind template" "$W" status
fi

if section "Two clones merge index.md and log.md"; then
git -C "$WIKIS_DIR" add -A >/dev/null 2>&1
git -C "$WIKIS_DIR" commit -qm "smoke: setup" >/dev/null 2>&1
git init -q --bare "$T/remote.git"
git -C "$WIKIS_DIR" remote add origin "$T/remote.git"
check "push to a remote" git -C "$WIKIS_DIR" push -q -u origin HEAD
git clone -q "$T/remote.git" "$T/clone2"
printf -- '- [Alpha](wiki/alpha.md): from one\n' >> "$WIKIS_DIR/demo/index.md"
printf '\n## 2026-01-01 ingest: Alpha\n- created: wiki/alpha.md\n' >> "$WIKIS_DIR/demo/log.md"
git -C "$WIKIS_DIR" commit -qam "demo: ingest Alpha" && git -C "$WIKIS_DIR" push -q
printf -- '- [Beta](wiki/beta.md): from two\n' >> "$T/clone2/demo/index.md"
printf '\n## 2026-01-01 ingest: Beta\n- created: wiki/beta.md\n' >> "$T/clone2/demo/log.md"
git -C "$T/clone2" commit -qam "demo: ingest Beta"
check "pull merges without a conflict" git -C "$T/clone2" pull -q --no-rebase --no-edit
check "index.md keeps both lines" bash -c "grep -q Alpha '$T/clone2/demo/index.md' && grep -q Beta '$T/clone2/demo/index.md'"
check "log.md keeps both entries" bash -c "grep -q 'ingest: Alpha' '$T/clone2/demo/log.md' && grep -q 'ingest: Beta' '$T/clone2/demo/log.md'"
fi

if section "Secret scan"; then
if command -v gitleaks >/dev/null 2>&1; then
  # Built at runtime so this file never holds a token-shaped string.
  token="ghp_$(printf 'a1B2c3D4e5F6g7H8i9J0k1L2m3N4o5P6q7R8')"
  printf 'Captured: 2026-01-01\n\nDeploy token: %s\n' "$token" > "$WIKIS_DIR/demo/raw/leak.md"
  git -C "$WIKIS_DIR" add demo/raw/leak.md
  expect "a commit holding a token is refused" "commit refused" git -C "$WIKIS_DIR" commit -qm leak
  check "the refused commit didn't land" bash -c "! git -C '$WIKIS_DIR' log --oneline -1 | grep -q leak"
  printf 'Captured: 2026-01-01\n\nDeploy token: [REDACTED]\n' > "$WIKIS_DIR/demo/raw/leak.md"
  git -C "$WIKIS_DIR" add demo/raw/leak.md
  check "the redacted commit goes through" git -C "$WIKIS_DIR" commit -qm redacted
else
  skipped "secret scan (gitleaks isn't installed)"
fi
fi

if section "Session hook"; then
mkdir -p "$T/projects/web" && git -C "$T/projects/web" init -q
out="$(hook "$T/projects/web" | context 2>&1)"
case "$out" in *"$WIKIS_DIR/demo/AGENTS.md"*) ok "the hook names the covering wiki's handbook" ;; *) bad "the hook names the covering wiki's handbook" "$out" ;; esac
n="$(printf '%s' "$out" | wc -c | tr -d ' ')"
if [ "$n" -lt 2000 ]; then ok "the hook's context is short ($n chars)"; else bad "the hook's context is short ($n chars, limit 2000)"; fi
expect "outside a repository the hook uses the shared wiki" "$WIKIS_DIR/global" bash -c "$(declare -f hook context); T='$T' REPO='$REPO' WIKIS_DIR='$WIKIS_DIR'; hook '$T' | context"
expect "with no collection the hook says so" "no wiki collection" bash -c "$(declare -f hook context); T='$T' REPO='$REPO'; export WIKIS_DIR='$T/none'; hook '$T' | context"
expect "after compaction the hook asks for a capture" "just compacted" bash -c "$(declare -f hook context); T='$T' REPO='$REPO'; hook '$T/projects/web' '{\"source\":\"compact\"}' | context"
expect "after compaction the capture comes before answering the user" "Before you answer anything, even the user's message" bash -c "$(declare -f hook context); T='$T' REPO='$REPO'; hook '$T/projects/web' '{\"source\":\"compact\"}' | context"
lacks "at startup the hook doesn't" "just compacted" bash -c "$(declare -f hook context); T='$T' REPO='$REPO'; hook '$T/projects/web' '{\"source\":\"startup\"}' | context"
set_version "$WIKIS_DIR/demo/AGENTS.md" 12
expect "when the handbook is behind, the session upgrades after pulling" "First pull the collection if it has a remote" bash -c "$(declare -f hook context); T='$T' REPO='$REPO'; hook '$T/projects/web' | context"
set_version "$WIKIS_DIR/demo/AGENTS.md" "$TV"
lacks "when it's current, nothing about upgrading" "upgrade --all" bash -c "$(declare -f hook context); T='$T' REPO='$REPO'; hook '$T/projects/web' | context"
# The longest context: no wiki for the repository, just compacted, handbook behind.
set_version "$WIKIS_DIR/global/AGENTS.md" 12
mkdir -p "$T/projects/uncovered" && git -C "$T/projects/uncovered" init -q
mkdir -p "$T/projects/uncovered-docs/docs" && printf '# U\n' > "$T/projects/uncovered-docs/README.md" && printf '# G\n' > "$T/projects/uncovered-docs/docs/guide.md"
git -C "$T/projects/uncovered-docs" init -q && git -C "$T/projects/uncovered-docs" add -A && git -C "$T/projects/uncovered-docs" commit -qm init
out="$(hook "$T/projects/uncovered" '{"source":"compact"}' | context 2>&1)"
set_version "$WIKIS_DIR/global/AGENTS.md" "$TV"
case "$out" in *"seed"*) ok "in a repository with no wiki the hook offers seed" ;; *) bad "in a repository with no wiki the hook offers seed" "$out" ;; esac
n="$(printf '%s' "$out" | wc -c | tr -d ' ')"
if [ "$n" -lt 2000 ]; then ok "the hook's longest context is short ($n chars)"; else bad "the hook's longest context is short ($n chars, limit 2000)"; fi
expect "the hook says to keep knowledge in the wiki, not the agent's memory" "not in your own memory" bash -c "$(declare -f hook context); T='$T' REPO='$REPO'; hook '$T/projects/web' | context"
check "the hook writes the wiki command" test -x "$T/data/bin/wiki"
expect "the wiki command runs wiki.sh" "WIKI" "$T/data/bin/wiki" status
expect "the wiki command's messages say wiki" "Run: wiki init" env WIKIS_DIR="$T/none" "$T/data/bin/wiki" status
fi

if section "Links and plugin mode"; then
ln -s "$W" "$T/bin/wk"
expect "a symlinked wiki.sh finds its template" "demo" "$T/bin/wk" which web
expect "a symlinked wiki.sh on the PATH uses its link's name" "Run: wk init" env WIKIS_DIR="$T/none" PATH="$T/bin:$PATH" wk status
expect "run by a path, messages name that path, not ./wiki.sh" "Run: $T/bin/wk init" env WIKIS_DIR="$T/none" PATH="/usr/bin:/bin" "$T/bin/wk" status
expect "run from its own folder, it's ./wiki.sh" "Run: ./wiki.sh init" bash -c "cd '$REPO' && WIKIS_DIR='$T/none' ./wiki.sh status"
P="$HOME/.claude/plugins/cache/llm-wiki/llm-wiki/abc123"
mkdir -p "$P"
(cd "$REPO" && tar cf - --exclude .git --exclude tests .) | (cd "$P" && tar xf -)
expect "from the plugin, claude skips the CLAUDE.md line" "came with the llm-wiki Claude Code plugin" "$P/wiki.sh" claude
expect "from the plugin, claude --print names the stable command" "plugins/data/llm-wiki-llm-wiki/bin/wiki start" "$P/wiki.sh" claude --print
lacks "from the plugin, claude --print never names the versioned folder" "abc123" "$P/wiki.sh" claude --print
check "from the plugin, CLAUDE.md is untouched" test ! -e "$HOME/.claude/CLAUDE.md"
set_version "$WIKIS_DIR/demo/AGENTS.md" 999
out="$("$P/wiki.sh" status 2>&1)"
set_version "$WIKIS_DIR/demo/AGENTS.md" "$TV"
case "$out" in *"claude plugin update llm-wiki@llm-wiki"*) ok "from the plugin, a newer wiki says to update the plugin" ;; *) bad "from the plugin, a newer wiki says to update the plugin" "$out" ;; esac
case "$out" in *"git -C"*) bad "from the plugin, status never says to git pull the plugin's folder" "$out" ;; *) ok "from the plugin, status never says to git pull the plugin's folder" ;; esac
# A newer version is installed, but this old copy still runs: restart, don't update.
P2="$HOME/.claude/plugins/cache/llm-wiki/llm-wiki/def456"
mkdir -p "$P2" && cp "$P/wiki.sh" "$P2/"
printf '{"plugins":{"llm-wiki@llm-wiki":[{"scope":"user","installPath":"%s"}]}}\n' "$P2" > "$HOME/.claude/plugins/installed_plugins.json"
set_version "$WIKIS_DIR/demo/AGENTS.md" 999
out="$("$P/wiki.sh" status 2>&1)"
set_version "$WIKIS_DIR/demo/AGENTS.md" "$TV"
rm "$HOME/.claude/plugins/installed_plugins.json"
case "$out" in *"Claude Code has def456 installed"*"Do: quit and reopen"*) ok "an old copy after an update says to restart Claude" ;; *) bad "an old copy after an update says to restart Claude" "$out" ;; esac
fi

if section "Seed"; then
A="$T/projects/api"
mkdir -p "$A/docs/adr" "$A/node_modules/pkg" "$A/src"
printf '# API\n\nThe billing API.\n' > "$A/README.md"
printf '# Use Postgres\n' > "$A/docs/adr/0001-postgres.md"
printf '# Deploying\n' > "$A/docs/deploy.md"
printf '# Changes\n' > "$A/CHANGELOG.md"
printf '# Not ours\n' > "$A/node_modules/pkg/README.md"
printf '# Code notes\n' > "$A/src/notes.md"
awk 'BEGIN { for (i = 0; i < 3000; i++) print "a long line of filler text for the size cap test" }' > "$A/docs/huge.md"
git -C "$A" init -q && git -C "$A" add README.md docs src CHANGELOG.md && git -C "$A" commit -qm init
expect "a dry run lists what it would copy" "would copy: README.md" "$W" seed "$A" --dry-run
check "a dry run writes nothing" bash -c "! ls '$WIKIS_DIR/demo/raw/' | grep -q seed"
out="$("$W" seed "$A" 2>&1)"
for want in "seeded:  README.md" "seeded:  docs/adr/0001-postgres.md" "seeded:  docs/deploy.md" "docs/huge.md"; do
  case "$out" in *"$want"*) ok "seed: $want" ;; *) bad "seed: $want" "$out" ;; esac
done
case "$out" in *CHANGELOG* | *node_modules* | *notes.md*) bad "seed leaves out changelogs, dependencies and stray notes" "$out" ;; *) ok "seed leaves out changelogs, dependencies and stray notes" ;; esac
check "seed goes into the wiki that covers the repository" bash -c "ls '$WIKIS_DIR/demo/raw/' | grep -q 'seed-01-readme.md'"
check "seed writes a manifest note" bash -c "grep -q 'docs/deploy.md' '$WIKIS_DIR'/demo/raw/*-seed-00-manifest.md"
expect "seeding again copies nothing" "nothing new to seed" "$W" seed "$A"
A2="$T/projects/agents"
mkdir -p "$A2/.claude/skills/release" "$A2/.github/workflows" "$A2/services/api"
for f in CLAUDE.md AGENTS.md .cursorrules .github/copilot-instructions.md .github/workflows/ci.md .claude/skills/release/SKILL.md services/api/CLAUDE.md; do
  printf '# %s\n' "$f" > "$A2/$f"
done
git -C "$A2" init -q && git -C "$A2" add -A && git -C "$A2" commit -qm init
out="$("$W" seed "$A2" 2>&1)"
for want in "seeded:  CLAUDE.md" "seeded:  AGENTS.md" "seeded:  .cursorrules" "seeded:  .github/copilot-instructions.md" "seeded:  .claude/skills/release/SKILL.md" "seeded:  services/api/CLAUDE.md"; do
  case "$out" in *"$want"*) ok "seed takes agent instructions: ${want#seeded:  }" ;; *) bad "seed takes agent instructions: ${want#seeded:  }" "$out" ;; esac
done
case "$out" in *workflows*) bad "seed skips CI workflow files" "$out" ;; *) ok "seed skips CI workflow files" ;; esac
check "a file with no extension is copied as .txt" bash -c "ls '$WIKIS_DIR/agents/raw/' | grep -q 'seed-[0-9]*-cursorrules.txt'"
fi

if section "Pending and bulk compile"; then
expect "pending lists what waits in each wiki" "demo:" "$W" pending
expect "pending <wiki> lists its files" "seed-01-readme.md" "$W" pending demo
out="$("$W" pending demo --show 2>&1)"
case "$out" in *"===== raw/"*"The billing API."*"none left"*) ok "pending --show prints the files in one go" ;; *) bad "pending --show prints the files in one go" "$out" ;; esac
"$W" new bulk >/dev/null
for i in 1 2 3; do awk 'BEGIN { for (i = 0; i < 1200; i++) print "a line of filler for the bulk compile size cap test" }' > "$WIKIS_DIR/bulk/raw/2026-01-0$i-000000-big-$i.md"; done
expect "pending --show stops at its size cap and says more wait" "1 more wait" "$W" pending bulk --show
refuse "pending --show needs a wiki" "$W" pending --show
expect "pending says when nothing waits" "nothing waiting in" "$W" pending global
# A sandbox that blocks listing raw/ must not read as "nothing waiting".
chmod 000 "$WIKIS_DIR/demo/raw"
refuse "pending fails when it can't list raw/" "$W" pending demo
expect "and says what's waiting is unknown" "is unknown" "$W" pending demo
refuse "pending across wikis fails too" "$W" pending
expect "and names the wiki it couldn't read" "demo: unknown" "$W" pending
expect "status shows ? and says why" "can't read raw/" "$W" status
chmod 755 "$WIKIS_DIR/demo/raw"
for i in 01 02 03 04 05 06 07 08 09 10 11; do printf 'Captured: 2026-01-01\n\nNote %s.\n' "$i" > "$WIKIS_DIR/bulk/raw/2026-01-01-0000$i-note-$i.md"; done
"$W" cover bulk bulkrepo >/dev/null
mkdir -p "$T/projects/bulkrepo" && git -C "$T/projects/bulkrepo" init -q
expect "with more than ten waiting, the session does the request first" "more than ten, so do the user's request first" bash -c "$(declare -f hook context); T='$T' REPO='$REPO'; hook '$T/projects/bulkrepo' | context"
lacks "with a few waiting, it compiles first" "more than ten" bash -c "$(declare -f hook context); T='$T' REPO='$REPO'; hook '$T/projects/web' | context"
fi

if section "Team skills"; then
SK="$HOME/.claude/skills"
mkdir -p "$SK/go-expert" && printf -- '---\nname: go-expert\ndescription: mine\n---\n' > "$SK/go-expert/SKILL.md"
expect "with none, skills says how they arrive" "No team skills yet" "$W" skills
mkskill "$WIKIS_DIR/global/skills/bump-proto" "Bump a shared proto everywhere."
mkskill "$WIKIS_DIR/demo/skills/deploy" "Deploy demo."
mkskill "$WIKIS_DIR/agents/skills/deploy" "Deploy agents."
mkskill "$WIKIS_DIR/global/skills/go-expert" "Someone else's go-expert."
expect "skills lists them with descriptions" "Bump a shared proto everywhere." "$W" skills
expect "skills link links a skill" "linked:  bump-proto" "$W" skills link
check "the link points into the wiki" test "$SK/bump-proto" -ef "$WIKIS_DIR/global/skills/bump-proto"
check "two wikis' same-named skills get their wiki's name" bash -c "test -L '$SK/demo-deploy' && test -L '$SK/agents-deploy'"
check "a skill from elsewhere is left alone" bash -c "! test -L '$SK/go-expert' && grep -q mine '$SK/go-expert/SKILL.md'"
expect "skills shows the clash" "clash" "$W" skills
expect "linking again changes nothing" "nothing new to link" "$W" skills link
rm -r "$WIKIS_DIR/agents/skills/deploy"
"$W" skills link >/dev/null
check "a deleted skill's link is removed" test ! -e "$SK/agents-deploy"
check "and the survivor takes its own name" bash -c "test '$SK/deploy' -ef '$WIKIS_DIR/demo/skills/deploy' && ! test -e '$SK/demo-deploy'"
mkskill "$WIKIS_DIR/global/skills/rotate-keys" "Rotate keys."
expect "the session hook links new team skills and says so" "available: rotate-keys" bash -c "$(declare -f hook context); T='$T' REPO='$REPO'; hook '$T/projects/web' | context"
fi

if section "Tips"; then
export XDG_CONFIG_HOME="$T/config"
"$W" new extra-one >/dev/null
"$W" new extra-two >/dev/null
expect "tips names the evidence for a tip" "wikis. \`wiki find" "$W" tips
expect "a skill only on this machine gets a sharing tip" "only on this machine: go-expert" "$W" tips
expect "a repository with docs and no wiki gets a seed tip" "has no wiki yet" "$W" tips --repo "$T/projects/uncovered-docs"
first="$("$W" tips --next | cut -f 1)"
second="$("$W" tips --next | cut -f 1)"
if [ -n "$first" ] && [ -n "$second" ] && [ "$first" != "$second" ]; then ok "a shown tip rests while the next one shows ($first, then $second)"; else bad "a shown tip rests while the next one shows ($first, then $second)"; fi
check "the shown tips are recorded" grep -q "^shown:$first " "$T/config/llm-wiki/tips"
expect "a tip can be muted" "muted" "$W" tips --mute find
lacks "a muted tip never comes up next" "find" bash -c "for i in 1 2 3 4 5 6 7 8; do '$W' tips --next; done"
refuse "muting an unknown tip fails" "$W" tips --mute nonsense
"$W" tips --unmute find >/dev/null
"$W" find canary >/dev/null
lacks "using a feature retires its tip" "wiki find <word>" "$W" tips
rm -f "$T/config/llm-wiki/tips"
expect "status mentions tips" "Run: $W tips" env LLM_WIKI_CMD="$W" "$W" status
out="$(hook "$T/projects/uncovered" '{"source":"startup"}' | context 2>&1)"
case "$out" in *"One tip for the user"*) ok "the session hook passes on one tip" ;; *) bad "the session hook passes on one tip" "$out" ;; esac
n="$(printf '%s' "$out" | wc -c | tr -d ' ')"
if [ "$n" -lt 2000 ]; then ok "with a tip the hook's context is still short ($n chars)"; else bad "with a tip the hook's context is still short ($n chars, limit 2000)"; fi
lacks "no tip right after compaction" "One tip" bash -c "$(declare -f hook context); T='$T' REPO='$REPO'; hook '$T/projects/web' '{\"source\":\"compact\"}' | context"
unset XDG_CONFIG_HOME
fi

if section "Tab completion"; then
expect "the first word completes to commands" "standup" "$W" __complete 1 st
expect "journal set completes setting names" "max_commits" "$W" __complete 3 journal set ""
expect "setup completes the newer sections" "feedback" "$W" __complete 2 setup ""
expect "and chat" "chat" "$W" __complete 2 setup ""
for t in collection collections tools git claude plugin permissions antigravity codex cursor upgrade skills completion delegation feedback chat journal microsoft-copilot; do
  expect "setup completes $t" "$t" "$W" __complete 2 setup ""
  case "$t" in
    antigravity | codex | cursor) ;; # Named only once installed, tested below.
    *) expect "and setup --list names it" " $t " bash -c "'$W' setup --list | grep '^Or a section:' | sed 's/\$/ /'" ;;
  esac
done
expect "a choice setting completes its values" "summary" "$W" __complete 4 journal set format ""
expect "tips --mute completes tip names" "share-skill" "$W" __complete 3 tips --mute ""
expect "upgrade completes wiki names" "demo" "$W" __complete 2 upgrade ""
expect "seed completes directories" "__dirs__" "$W" __complete 2 seed ""
check "the bash script parses" bash -n <("$W" completion bash)
"$W" completion bash > "$T/c.bash"
out="$(bash -c "source '$T/c.bash'; COMP_WORDS=('$W' journal s); COMP_CWORD=2; _llm_wiki; echo \"\${COMPREPLY[*]}\"" 2>&1)"
case "$out" in "show set") ok "bash completion passes each word on (bash 3.2 joins them otherwise)" ;; *) bad "bash completion passes each word on (bash 3.2 joins them otherwise)" "$out" ;; esac
if command -v zsh >/dev/null 2>&1; then
  check "the zsh script parses" zsh -n <("$W" completion zsh)
else
  skipped "zsh completion (zsh isn't installed)"
fi
refuse "completion needs a shell name" "$W" completion fish
fi

if section "Weekly report"; then
mkdir -p "$HOME/.claude/projects/p1"
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
big="$(awk 'BEGIN { for (i = 0; i < 4000; i++) printf "x" }')"
{
  # One reply recorded twice, as Claude Code does for multi-part replies: counted once.
  printf '{"type":"assistant","timestamp":"%s","cwd":"%s","sessionId":"s1","message":{"id":"m1","usage":{"input_tokens":100,"cache_creation_input_tokens":1900,"cache_read_input_tokens":50000,"output_tokens":300},"content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"%s"}}]}}\n' "$now" "$T/projects/web" "$WIKIS_DIR/demo/index.md"
  printf '{"type":"assistant","timestamp":"%s","cwd":"%s","sessionId":"s1","message":{"id":"m1","usage":{"input_tokens":100,"cache_creation_input_tokens":1900,"cache_read_input_tokens":50000,"output_tokens":300},"content":[{"type":"text","text":"ok"}]}}\n' "$now" "$T/projects/web"
  printf '{"type":"user","timestamp":"%s","cwd":"%s","sessionId":"s1","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"%s"}]}}\n' "$now" "$T/projects/web" "$big"
} > "$HOME/.claude/projects/p1/s1.jsonl"
out="$("$W" report 2>&1)"
case "$out" in *"| demo | 1 | 2k | 50k | 300 | 1k |"*) ok "tokens: a covered repository's session counts toward its wiki, each reply once" ;; *) bad "tokens: a covered repository's session counts toward its wiki, each reply once" "$out" ;; esac
case "$out" in *"Wiki use is about 5"[0-9].[0-9]"% of new input: lookups 5"[0-9].[0-9]"%, upkeep 0.0%. Lookups are reads, searches and session starts; upkeep is captures, compiles, lints, syncs and status. New input is what entered a session's context for the first time; cache reads are that context read again on later turns."*) ok "tokens: wiki use is estimated against new input, split into lookups and upkeep" ;; *) bad "tokens: wiki use is estimated against new input, split into lookups and upkeep" "$out" ;; esac
# The compiled helper stands in for the Python above, so it must print the same report.
# A second transcript holds the cases the two could differ on.
{
  printf '{"type":"assistant","timestamp":"%s","cwd":"%s","sessionId":"s2","message":{"id":"m2","usage":{"input_tokens":7,"cache_creation_input_tokens":1200,"cache_read_input_tokens":3000000,"output_tokens":1500},"content":[{"type":"tool_use","id":"t2","name":"Bash","input":{"command":"%s find caf\\u00e9 \\u2603 \\ud83d\\ude00","timeout":0.5,"nested":[1,2.50,{"a":null,"b":true}]}}]}}\n' "$now" "$T/projects/nowhere/deep" "$W"
  printf '{"type":"user","timestamp":"%s","cwd":"%s","sessionId":"s2","message":{"content":[{"type":"tool_result","tool_use_id":"t2","content":[{"type":"text","text":"%s"},{"type":"text","text":"d\\u00e9f"}]}]}}\n' "$now" "$T/projects/nowhere/deep" "$big"
  printf '{"type":"assistant","timestamp":"%s","cwd":"%s","sessionId":"s2","message":{"id":"m1","usage":{"input_tokens":100,"cache_creation_input_tokens":1900,"cache_read_input_tokens":50000,"output_tokens":300},"content":"said twice, in two files"}}\n' "$now" "$T/projects/web"
  printf '{"type":"assistant","timestamp":"%s","cwd":"%s","message":{"usage":{"input_tokens":40,"output_tokens":9},"content":[{"type":"tool_use","id":"t3","name":"mcp__llm-wiki__wiki_read","input":{"wiki":"demo","path":"wiki/x.md"}},{"type":"tool_use","id":"t4","name":"Edit","input":{"file_path":"%s/demo/wiki/a.md","old_string":"x"}},{"type":"tool_use","id":"t5","name":"Read","input":{"file_path":"%s/demo/wiki/a.md"}}]}}\n' "$now" "$T/projects/web" "$WIKIS_DIR" "$WIKIS_DIR"
  printf '{"type":"assistant","timestamp":"%s","cwd":"%s","sessionId":"s3","message":{"usage":{"input_tokens":50,"output_tokens":5}}}\n' "$now" "$WIKIS_DIR"
  printf '{"type":"user","timestamp":"%s","cwd":"%s","sessionId":"s3","message":{"content":[{"type":"tool_result","tool_use_id":"t5","content":"%s"}]}}\n' "$now" "$WIKIS_DIR" "$big"
  printf '{"type":"assistant","timestamp":"2020-01-01T00:00:00Z","cwd":"%s","sessionId":"old","message":{"id":"m9","usage":{"input_tokens":999999,"output_tokens":999999}}}\n' "$T/projects/web"
  printf '{"type":"summary","cwd":"%s","message":{"id":"m8","usage":{"input_tokens":999999,"output_tokens":999999}}}\n' "$T/projects/web"
  printf 'not json at all\n\n'
} > "$HOME/.claude/projects/p1/s2.jsonl"
if command -v go >/dev/null 2>&1; then
  check "the Go helper builds" build_helper
  check "and its own tests pass" go test -C "$REPO" ./cmd/... ./internal/...
  check "it speaks the protocol wiki.sh expects" test "$("$T/bin/llm-wiki" protocol)" = "$(sed -n 's/^GO_PROTOCOL=//p' "$W")"
  py="$(LLM_WIKI_NO_GO=1 "$W" report 2>&1)"
  go="$(LLM_WIKI_GO="$T/bin/llm-wiki" "$W" report 2>&1)"
  case "$py" in *"| demo | 2 | 3k | 3.0M | 2k | 3k |"*"| all | 2 | 3k | 3.0M | 2k | 3k |"*) ok "the Python counts the second transcript's cases" ;; *) bad "the Python counts the second transcript's cases" "$py" ;; esac
  [ "$py" = "$go" ] && ok "the Go helper prints the same report as the Python" || bad "the Go helper prints the same report as the Python" "$(diff <(printf '%s\n' "$py") <(printf '%s\n' "$go"))"
  expect "and the same wiki use" "- demo: pages opened in 1 session(s)" env LLM_WIKI_GO="$T/bin/llm-wiki" "$W" report
  "$W" journal set exclude 'de*' >/dev/null
  [ "$(LLM_WIKI_NO_GO=1 "$W" report 2>&1)" = "$(LLM_WIKI_GO="$T/bin/llm-wiki" "$W" report 2>&1)" ] && ok "with a project excluded too" || bad "with a project excluded too"
  "$W" journal set exclude "" >/dev/null
  [ "$(LLM_WIKI_NO_GO=1 "$W" report --since 2019-12-25 2>&1)" = "$(LLM_WIKI_GO="$T/bin/llm-wiki" "$W" report --since 2019-12-25 2>&1)" ] && ok "and over a longer range" || bad "and over a longer range"
  lacks "a helper built for another protocol is passed over" "STALE TABLE" env LLM_WIKI_GO="$T/bin/stale-helper" "$W" report
  expect "and the Python answers" "| demo | 2 | 3k | 3.0M | 2k | 3k |" env LLM_WIKI_GO="$T/bin/stale-helper" "$W" report
  expect "a helper that fails falls back to the Python" "| demo | 2 | 3k | 3.0M | 2k | 3k |" env LLM_WIKI_GO="$T/bin/broken-helper" "$W" report
  # What a tool call and its result count as, one at a time, in a transcript of their own.
  # The result is 4000 characters against 2000 tokens of new input, so the call's share is
  # about half, in the column for its kind.
  mv "$HOME/.claude/projects" "$HOME/.claude/projects.keep"; mkdir -p "$HOME/.claude/projects/pc"
  cclass() { # <what> <lookup|upkeep|none> <tool name> <input as JSON>
    local want="$2" shape pyc goc
    {
      printf '{"type":"assistant","timestamp":"%s","cwd":"%s","sessionId":"sc","message":{"id":"mc","usage":{"input_tokens":2000,"output_tokens":10},"content":[{"type":"tool_use","id":"tc","name":"%s","input":%s}]}}\n' "$now" "$T/projects/web" "$3" "$4"
      printf '{"type":"user","timestamp":"%s","cwd":"%s","sessionId":"sc","message":{"content":[{"type":"tool_result","tool_use_id":"tc","content":"%s"}]}}\n' "$now" "$T/projects/web" "$big"
    } > "$HOME/.claude/projects/pc/sc.jsonl"
    pyc="$(LLM_WIKI_NO_GO=1 "$W" report 2>&1 | grep '^Wiki use is about' | head -n 1)"
    goc="$(LLM_WIKI_GO="$T/bin/llm-wiki" "$W" report 2>&1 | grep '^Wiki use is about' | head -n 1)"
    case "$want" in
      lookup) shape='Wiki use is about 5[0-9].[0-9]% of new input: lookups 5[0-9].[0-9]%, upkeep 0.0%. Lookups are*' ;;
      upkeep) shape='Wiki use is about 5[0-9].[0-9]% of new input: lookups 0.0%, upkeep 5[0-9].[0-9]%. Lookups are*' ;;
      *) shape='Wiki use is about 0.0% of new input: lookups 0.0%, upkeep 0.0%. Lookups are*' ;;
    esac
    # shellcheck disable=SC2254
    case "$pyc" in $shape) ok "tokens: $1 counts as $want (Python)" ;; *) bad "tokens: $1 counts as $want (Python)" "$pyc" ;; esac
    [ "$pyc" = "$goc" ] && ok "and the Go helper says the same" || bad "tokens: $1, the Go helper says the same" "$pyc"$'\n'"$goc"
  }
  cclass "an MCP wiki_search call" lookup mcp__llm-wiki__wiki_search '{"query":"deploy"}'
  cclass "an MCP wiki_list call" lookup mcp__llm-wiki__wiki_list '{}'
  cclass "an MCP wiki_capture call" upkeep mcp__llm-wiki__wiki_capture '{"wiki":"demo","text":"a decision"}'
  cclass "an MCP wiki_status call" upkeep mcp__llm-wiki__wiki_status '{}'
  cclass "an Edit inside the collection" upkeep Edit '{"file_path":"'"$WIKIS_DIR"'/demo/wiki/a.md","old_string":"x","new_string":"y"}'
  cclass "a MultiEdit inside the collection" upkeep MultiEdit '{"file_path":"'"$WIKIS_DIR"'/demo/wiki/a.md","edits":[]}'
  cclass "a Read inside the collection" lookup Read '{"file_path":"'"$WIKIS_DIR"'/demo/index.md"}'
  cclass "a Read outside it" none Read '{"file_path":"'"$T"'/projects/web/x.ts"}'
  cclass "a wiki.sh sync command" upkeep Bash '{"command":"'"$W"' sync demo"}'
  cclass "a wiki.sh find command" lookup Bash '{"command":"'"$W"' find deploy"}'
  cclass "a command with find and sync" upkeep Bash '{"command":"'"$W"' find deploy && '"$W"' sync demo"}'
  cclass "a plain grep of the collection" lookup Bash '{"command":"grep -r deploy '"$WIKIS_DIR"'/demo"}'
  cclass "a wiki command at the start of the line" upkeep Bash '{"command":"wiki capture x"}'
  cclass "a command that has nothing to do with the wikis" none Bash '{"command":"ls"}'
  rm -rf "$HOME/.claude/projects"; mv "$HOME/.claude/projects.keep" "$HOME/.claude/projects"
  # The Gemini table, on conversations with its edge cases. Each folder is one conversation.
  gconv() { GF="$HOME/.gemini/antigravity/brain/$1/.system_generated/logs/transcript_full.jsonl"; mkdir -p "${GF%/*}"; : > "$GF"; }
  gday="$(date -u +%Y-%m-%dT12:00:00Z)"
  gconv conv-b
  {
    # A step with a time and counts, pointing at the project by file path and by git -C.
    printf '{"created_at":"%s","input_tokens":1500,"cache_read_tokens":20000,"output_tokens":300,"tool_calls":[{"name":"read_file","args":{"Path":"%s/projects/web/x.ts"}},{"name":"run_command","args":{"CommandLine":"git -C %s/projects/web log"}}]}\n' "$gday" "$T" "$T"
    # A read inside a wiki, then the step whose content it pulled in: 4000 characters is 1k.
    printf '{"created_at":"%s","input_tokens":10,"tool_calls":[{"name":"read_file","args":{"Path":"%s/demo/wiki/x.md"}}]}\n' "$gday" "$WIKIS_DIR"
    printf '{"created_at":"%s","content":"%s"}\n' "$gday" "$(head -c 4000 /dev/zero | tr '\0' x)"
    # Not JSON, a blank line, and a step with no time: skipped, and not a step between others.
    printf 'not json\n\n{"input_tokens":999999}\n'
    # Written to a wiki page: not a page opened. A glob in a path: no wiki of that name.
    printf '{"created_at":"%s","tool_calls":[{"name":"write_file","args":{"Path":"%s/global/wiki/y.md"}},{"name":"list_dir","args":{"Path":"%s/*/wiki/"}}]}\n' "$gday" "$WIKIS_DIR" "$WIKIS_DIR"
    # Outside the range: not counted, though its folder still counts toward the project.
    printf '{"created_at":"2020-01-01T12:00:00Z","input_tokens":777777,"tool_calls":[{"args":{"Path":"%s/projects/web/old.ts"}}]}\n' "$T"
    # A time with a fraction and an offset, and null counts.
    printf '{"created_at":"%s.123+00:00","input_tokens":null,"output_tokens":5,"content":null}\n' "${gday%Z}"
  } >> "$GF"
  gconv conv-c
  {
    # No project: the bare name, a missing folder, the collection itself, and a page opened in global.
    printf '{"created_at":"%s","input_tokens":2000,"cache_read_tokens":100,"tool_calls":[{"args":{"Path":"bare.txt"}},{"args":{"Path":"/no/such/folder/x"}},{"args":{"Path":"%s/z"}},{"name":"run_command","args":{"CommandLine":"cat %s/global/wiki/a.md; bash wiki.sh status"}}]}\n' "$gday" "$WIKIS_DIR" "$WIKIS_DIR"
    # Characters, not bytes: a two-byte letter and an emoji as a surrogate pair, 400 of each.
    printf '{"content":"%s"}\n' "$(i=0; while [ $i -lt 400 ]; do printf '\303\251\\ud83d\\ude00'; i=$((i + 1)); done)"
  } >> "$GF"
  # The same totals as conv-c, in a project of its own: the tie goes to the one met first.
  gconv conv-a
  printf '{"created_at":"%s","input_tokens":2000,"cache_read_tokens":100,"tool_calls":[{"args":{"Path":"%s/global/raw/x"}},{"args":{"Path":"%s/global/raw/y"}}]}\n' "$gday" "$WIKIS_DIR" "$WIKIS_DIR" >> "$GF"
  # Tokens of output only, none of input; and none at all, which leaves its project out.
  gconv conv-d
  printf '{"created_at":"%s","output_tokens":40,"tool_calls":[{"args":{"Path":"%s/demo/wiki/z.md"}}]}\n' "$gday" "$WIKIS_DIR" >> "$GF"
  gconv conv-e
  printf '{"created_at":"%s","tool_calls":[{"args":{"Path":"%s/global/z.md"}}]}\n' "$gday" "$WIKIS_DIR" >> "$GF"
  # A file not touched since before the range isn't read, whatever it holds.
  gconv conv-f
  printf '{"created_at":"%s","input_tokens":888888}\n' "$gday" >> "$GF"
  touch -t 201901010000 "$GF"
  py="$(LLM_WIKI_NO_GO=1 "$W" report 2>&1)"
  go="$(LLM_WIKI_GO="$T/bin/llm-wiki" "$W" report 2>&1)"
  gemini="$(printf '%s\n' "$py" | sed -n '/^## Tokens (Gemini/,/^## What the wikis/p')"
  # What the Python printed for this fixture. global and other folders tie: global's conversation is met first.
  case "$gemini" in *"| demo | 2 | 2k | 20k | 345 | 1k |"$'\n'"| global | 2 | 2k | 100 | 0 | 0 |"$'\n'"| other folders | 1 | 2k | 100 | 0 | 400 |"$'\n'"| all | 5 | 6k | 20k | 345 | 1k |"*) ok "the Python counts the Gemini fixture's cases" ;; *) bad "the Python counts the Gemini fixture's cases" "$gemini" ;; esac
  case "$gemini" in *"Wiki use is about "[1-9]*"% of new input: lookups "[1-9]*"%, upkeep "[1-9]*"%. Lookups are reads, searches and session starts; upkeep is captures, compiles, lints, syncs and status."$'\n'"Gemini counts tokens its own way, so these don't add to Claude's."*) ok "the Gemini fixture has both lookups and upkeep, and its own sentence" ;; *) bad "the Gemini fixture has both lookups and upkeep, and its own sentence" "$gemini" ;; esac
  [ "$py" = "$go" ] && ok "the Go helper prints the same Gemini table as the Python" || bad "the Go helper prints the same Gemini table as the Python" "$(diff <(printf '%s\n' "$py") <(printf '%s\n' "$go"))"
  for gs in "--since 2019-12-25" "--since 7d"; do
    # shellcheck disable=SC2086
    [ "$(LLM_WIKI_NO_GO=1 "$W" report $gs 2>&1)" = "$(LLM_WIKI_GO="$T/bin/llm-wiki" "$W" report $gs 2>&1)" ] && ok "and with $gs" || bad "and with $gs"
  done
  "$W" journal set exclude 'oth*, de*,de*' >/dev/null
  [ "$(LLM_WIKI_NO_GO=1 "$W" report 2>&1)" = "$(LLM_WIKI_GO="$T/bin/llm-wiki" "$W" report 2>&1)" ] && ok "and with projects excluded" || bad "and with projects excluded"
  "$W" journal set exclude '*' >/dev/null
  expect "excluding them all says so" "No Gemini conversations in this range." env LLM_WIKI_GO="$T/bin/llm-wiki" "$W" report
  "$W" journal set exclude "" >/dev/null
  expect "a helper that fails falls back to the Python for Gemini too" "| demo | 2 |" env LLM_WIKI_GO="$T/bin/broken-helper" "$W" report
  # A helper that stops halfway leaves nothing behind.
  printf '#!/bin/sh\n[ "$1" = protocol ] && { sed -n "s/^GO_PROTOCOL=//p" "%s"; exit 0; }\n[ "$1" = report-tokens-gemini ] && exit 3\nexec "%s" "$@"\n' "$W" "$T/bin/llm-wiki" > "$T/bin/gemini-broken-helper"
  chmod +x "$T/bin/gemini-broken-helper"
  [ "$(LLM_WIKI_GO="$T/bin/gemini-broken-helper" "$W" report 2>&1)" = "$py" ] && ok "and only the failed table falls back" || bad "and only the failed table falls back"
  # The same, for Gemini: a call in one step, and the step after it, 4000 characters,
  # against 2000 tokens of new input, so half.
  mv "$HOME/.gemini" "$HOME/.gemini.keep"; gconv conv-x
  gclass() { # <what> <lookup|upkeep|none> <tool name> <args as JSON>
    local want="$2" shape pyc goc
    {
      printf '{"created_at":"%s","input_tokens":2000,"tool_calls":[{"name":"%s","args":%s}]}\n' "$gday" "$3" "$4"
      printf '{"created_at":"%s","content":"%s"}\n' "$gday" "$big"
    } > "$GF"
    pyc="$(LLM_WIKI_NO_GO=1 "$W" report 2>&1 | sed -n '/^## Tokens (Gemini/,/^## What the wikis/p' | grep '^Wiki use is about' | head -n 1)"
    goc="$(LLM_WIKI_GO="$T/bin/llm-wiki" "$W" report 2>&1 | sed -n '/^## Tokens (Gemini/,/^## What the wikis/p' | grep '^Wiki use is about' | head -n 1)"
    case "$want" in
      lookup) shape='Wiki use is about 50.0% of new input: lookups 50.0%, upkeep 0.0%. Lookups are*' ;;
      upkeep) shape='Wiki use is about 50.0% of new input: lookups 0.0%, upkeep 50.0%. Lookups are*' ;;
      *) shape='Wiki use is about 0.0% of new input: lookups 0.0%, upkeep 0.0%. Lookups are*' ;;
    esac
    # shellcheck disable=SC2254
    case "$pyc" in $shape) ok "tokens: Gemini's $1 counts as $want (Python)" ;; *) bad "tokens: Gemini's $1 counts as $want (Python)" "$pyc" ;; esac
    [ "$pyc" = "$goc" ] && ok "and the Go helper says the same" || bad "tokens: Gemini's $1, the Go helper says the same" "$pyc"$'\n'"$goc"
  }
  gclass "write_file in the collection" upkeep write_file '{"Path":"'"$WIKIS_DIR"'/demo/wiki/a.md"}'
  gclass "replace_file_content in the collection" upkeep replace_file_content '{"Path":"'"$WIKIS_DIR"'/demo/wiki/a.md"}'
  gclass "a read in the collection" lookup read_file '{"Path":"'"$WIKIS_DIR"'/demo/wiki/a.md"}'
  gclass "a wiki.sh sync command" upkeep run_command '{"CommandLine":"bash wiki.sh sync demo"}'
  gclass "a wiki.sh find command" lookup run_command '{"CommandLine":"bash wiki.sh find deploy"}'
  gclass "a command with find and sync" upkeep run_command '{"CommandLine":"bash wiki.sh find x; bash wiki.sh sync"}'
  gclass "a plain cat of the collection" lookup run_command '{"CommandLine":"cat '"$WIKIS_DIR"'/demo/index.md"}'
  gclass "an MCP wiki_capture call" upkeep mcp_llm-wiki_wiki_capture '{}'
  gclass "a read outside the collection" none read_file '{"Path":"'"$T"'/projects/web/x.ts"}'
  rm -rf "$HOME/.gemini"; mv "$HOME/.gemini.keep" "$HOME/.gemini"
  # Steps the Python must judge: the helper refuses them, and the report is what the Python makes of them.
  gconv conv-odd
  for godd in '[1]' 'null' '{"created_at":5}' '{"created_at":"yesterday"}' '{"created_at":"2026-11-05T12:00:00"}' '{"input_tokens":1.5}' '{"input_tokens":"3"}' '{"input_tokens":NaN}' '{"content":["a"]}' '{"tool_calls":{"a":1}}' '{"tool_calls":[{"args":{"Path":3}}]}' '{"tool_calls":[{"args":{"Path":"~nobody/x"}}]}' '{"created_at":"'"$gday"'","content":"\xff"}'; do
    # shellcheck disable=SC2059
    printf "$(printf '%s' "$godd" | sed 's/%/%%/g')\n" > "$GF"
    if "$T/bin/llm-wiki" report-tokens-gemini "$HOME/.gemini/antigravity/brain" 2019-01-01 2030-01-01 04:00 "$WIKIS_DIR" "" >/dev/null 2>&1; then
      bad "the helper leaves an odd step to the Python: $godd"
    elif [ "$(LLM_WIKI_NO_GO=1 "$W" report 2>&1 | sed -n '/^## Tokens (Gemini/,/^## What the wikis/p')" = "$(LLM_WIKI_GO="$T/bin/llm-wiki" "$W" report 2>&1 | sed -n '/^## Tokens (Gemini/,/^## What the wikis/p')" ]; then
      ok "the helper leaves an odd step to the Python: $godd"
    else
      bad "the report on an odd step matches the Python: $godd"
    fi
  done
  # journal backfill: the helper writes the digest the Python writes. The fixture holds
  # what the Python's digest turns on: noise and machine prompts, a side-session brief,
  # long prompts, ties, more than 14 prompts and 12 files, branches, commits, a session
  # in a stray folder, records the Python skips, and Gemini conversations.
  rm -rf "$HOME/.gemini/antigravity/brain/conv-odd"
  BF="$T/bf-projects"; mkdir -p "$BF/web" "$BF/stray" "$T/bf-stray/demo/sweeps"
  bts() { printf '2026-01-15T15:%02d:00.000Z' "$1"; }
  brec() { printf '{"type":"%s","timestamp":"%s","cwd":"%s","sessionId":"%s","gitBranch":"%s","message":%s}\n' "$1" "$(bts "$2")" "$3" "$4" "$5" "$6"; }
  {
    brec user 1 "$T/projects/web" s1 main '{"role":"user","content":"<system-reminder>ignore\nme</system-reminder>  Fix   the\n\tlogin <command-name>/x</command-name>bug  "}'
    brec user 1 "$T/projects/web" s1 main '{"role":"user","content":[{"type":"text","text":"first part"},{"type":"tool_result","content":"x"},{"type":"text","text":"second part"}]}'
    brec user 2 "$T/projects/web" s1 main '{"role":"user","content":"<task-notification>done</task-notification>"}'
    brec user 2 "$T/projects/web" s1 main '{"role":"user","content":"Caveat: local command"}'
    brec user 3 "$T/projects/web" s1 HEAD '{"role":"user","content":"Background (from the session that started this one): build the thing\nTask: and more"}'
    brec user 4 "$T/projects/web" s1 main "{\"role\":\"user\",\"content\":\"$(i=0; while [ $i -lt 130 ]; do printf 'é '; i=$((i + 1)); done)\"}"
    brec user 5 "$T/projects/web" s1 main '{"role":"user","content":"<command-name>/clear</command-name>"}'
    printf '{"type":"user","timestamp":"%s","cwd":"%s","isSidechain":true,"message":{"content":"a side chain"}}\n' "$(bts 5)" "$T/projects/web"
    printf '{"type":"user","timestamp":"%s","cwd":"%s","isMeta":true,"message":{"content":"meta"}}\n' "$(bts 5)" "$T/projects/web"
    printf '{"type":"summary","timestamp":"%s","cwd":"%s","message":{"content":"a summary"}}\n' "$(bts 5)" "$T/projects/web"
    printf 'not json\n\n{"type":"user","cwd":"%s","message":{"content":"no time"}}\n' "$T/projects/web"
    i=0; while [ $i -lt 16 ]; do brec user $((20 - i % 7)) "$T/projects/web" s2 feature/x "{\"role\":\"user\",\"content\":\"prompt $i\"}"; i=$((i + 1)); done
    brec assistant 6 "$T/projects/web" s1 main '{"role":"assistant","content":[{"type":"text","text":"Working on it."},{"type":"tool_use","name":"Edit","input":{"file_path":"/a/login.ts"}},{"type":"tool_use","name":"Write","input":{"file_path":"/b/login.ts"}},{"type":"tool_use","name":"NotebookEdit","input":{"notebook_path":"/n/nb.ipynb"}},{"type":"tool_use","name":"Read","input":{"file_path":"/r/read.ts"}},{"type":"tool_use","name":"Bash","input":{"command":["git commit -m x"]}}]}'
    brec assistant 7 "$T/projects/web" s1 main '{"role":"assistant","content":[{"type":"text","text":"<system-reminder>only noise</system-reminder>"}]}'
    i=0; while [ $i -lt 14 ]; do brec assistant 8 "$T/projects/web" s2 feature/x "{\"role\":\"assistant\",\"content\":[{\"type\":\"tool_use\",\"name\":\"MultiEdit\",\"input\":{\"file_path\":\"/m/f$i.go\"}}]}"; i=$((i + 1)); done
    brec assistant 9 "$T/projects/web" s2 feature/x '{"role":"assistant","content":"a string, which has no parts"}'
    brec assistant 9 "$T/projects/web" s2 feature/x 'null'
    printf '{"type":"user","timestamp":"%s","message":{"content":"from no folder"}}\n' "$(bts 10)"
    printf '{"type":"user","timestamp":"2020-01-01T12:00:00.000Z","cwd":"%s","sessionId":"old","message":{"content":"long ago"}}\n' "$T/projects/web"
  } > "$BF/web/a.jsonl"
  {
    # A session in a stray folder belongs to the known project most of its records ran in.
    brec user 11 /tmp/bf-scratch s3 "" '{"content":"from a stray folder"}'
    brec user 12 "$T/projects/web" s3 "" '{"content":"from the project"}'
    brec user 12 "$T/bf-stray/demo/sweeps" s3 "" '{"content":"from a scratch folder inside demo"}'
    printf '{"type":"user","timestamp":"%s","cwd":"%s","message":{"content":"with no session id"}}\n' "$(bts 13)" "$T/projects/web"
    brec assistant 14 "$T/projects/web" s3 "" '{"content":[{"type":"text","text":"Done, and committed."},{"type":"tool_use","name":"Bash","input":{"command":"git add -A && git commit -m done"}}]}'
  } > "$BF/stray/b.jsonl"
  gconv conv-bf
  {
    printf '{"type":"USER_INPUT","created_at":"%s","content":"<USER_REQUEST>\\nAdd   a\\ncardio screen\\n</USER_REQUEST>\\n<ADDITIONAL_METADATA>x</ADDITIONAL_METADATA>"}\n' "$(bts 16)"
    printf '{"type":"PLANNER_RESPONSE","created_at":"%s","tool_calls":[{"name":"write_file","args":{"Path":"%s/projects/web/cardio.ts"}},{"name":"run_command","args":{"CommandLine":"bash wiki.sh sync demo"}}]}\n' "$(bts 17)" "$T"
    printf '{"type":"PLANNER_RESPONSE","created_at":"%s","content":"Added the cardio screen."}\n' "$(bts 18)"
  } >> "$GF"
  # In UTC, so the digest's local times are the same on every machine.
  bf() { TZ=UTC "$W" journal backfill --from "$BF" "$@" 2>&1; cat "$WIKIS_DIR/journal/backfill.md" 2>/dev/null; }
  bpy="$(LLM_WIKI_NO_GO=1 bf --since 2026-01-14 --until 2026-01-17)"
  # What the Python wrote for the fixture: proof it covers the cases.
  # What the Python wrote for the fixture, in UTC: proof it covers the cases. Records
  # with no folder or in a stray one go to the session's project.
  for want in "### [demo] 15:01-15:20, 6 session(s), 1 in Gemini, branch feature/x, ran git commit"$'\n'"- 15:01 Fix the login bug"$'\n'"- 15:01 first part"$'\n'"- 15:01 second part"$'\n'"- 15:03 (side session brief) build the thing Task: and more" "- 15:04 é é é" "é é..."$'\n'"- 15:10 from no folder"$'\n'"- 15:11 from a stray folder" "- 15:12 from a scratch folder inside demo"$'\n'"- ... 13 more prompts ..."$'\n'"- 15:19 prompt 8" "- 15:20 prompt 14"$'\n'"- files changed: login.ts, nb.ipynb, f0.go, f1.go, f2.go, f3.go, f4.go, f5.go, f6.go, f7.go, f8.go, f9.go ..."$'\n'"- last reply: Added the cardio screen."; do
    case "$bpy" in *"$want"*) ok "the Python's digest has: ${want%%$'\n'*}" ;; *) bad "the Python's digest has: ${want%%$'\n'*}" "$bpy" ;; esac
  done
  case "$bpy" in *"a side chain"* | *"long ago"* | *"Caveat"* | *"only noise"* | *"read.ts"*) bad "and leaves out what it skips" "$bpy" ;; *) ok "and leaves out what it skips" ;; esac
  for bs in "--since 2026-01-14 --until 2026-01-17" "--since 2019-12-25" "--since 7d" ""; do
    # shellcheck disable=SC2086
    [ "$(LLM_WIKI_NO_GO=1 bf $bs)" = "$(LLM_WIKI_GO="$T/bin/llm-wiki" bf $bs)" ] && ok "the helper writes the same digest as the Python: ${bs:-14d}" || bad "the helper writes the same digest as the Python: ${bs:-14d}" "$(diff <(LLM_WIKI_NO_GO=1 bf $bs) <(LLM_WIKI_GO="$T/bin/llm-wiki" bf $bs))"
  done
  for bx in "de*" "unknown,gemini" "*o*, d?mo"; do
    "$W" journal set exclude "$bx" >/dev/null
    [ "$(LLM_WIKI_NO_GO=1 bf --since 2019-12-25)" = "$(LLM_WIKI_GO="$T/bin/llm-wiki" bf --since 2019-12-25)" ] && ok "and with $bx excluded" || bad "and with $bx excluded"
  done
  "$W" journal set exclude "" >/dev/null
  : > "$T/helper-ran"
  printf '#!/bin/sh\n[ "$1" = protocol ] || echo "$1" >> "%s"\nexec "%s" "$@"\n' "$T/helper-ran" "$T/bin/llm-wiki" > "$T/bin/bf-spy-helper"
  chmod +x "$T/bin/bf-spy-helper"
  LLM_WIKI_NO_GO="" LLM_WIKI_GO="$T/bin/bf-spy-helper" bf >/dev/null
  [ "$(grep -c '^journal-backfill$' "$T/helper-ran")" = 1 ] && ok "wiki.sh runs the helper for backfill" || bad "wiki.sh runs the helper for backfill" "$(cat "$T/helper-ran")"
  [ "$(LLM_WIKI_GO="$T/bin/broken-helper" bf --since 2019-12-25)" = "$(LLM_WIKI_NO_GO=1 bf --since 2019-12-25)" ] && ok "a helper that fails falls back to the Python for backfill" || bad "a helper that fails falls back to the Python for backfill"
  # Records the Python must judge: the helper refuses them and leaves the old digest as
  # it was, and wiki.sh's digest is what the Python makes of them.
  bnow="$(bts 30)"
  for bodd in '[1]' '{"type":"user","timestamp":5}' '{"type":"user","timestamp":"2026-01-15T15:30:00"}' '{"type":"user","timestamp":"'"$bnow"'","cwd":["x"]}' '{"type":"user","timestamp":"'"$bnow"'","x":NaN}' '{"type":"user","timestamp":"'"$bnow"'","message":{"content":"\\ud800"}}' '{"type":"user","timestamp":"'"$bnow"'","message":{"content":"\xff"}}' '{"type":"user","timestamp":"'"$bnow"'","sessionId":5}' '{"type":"user","timestamp":"'"$bnow"'","message":"x"}' '{"type":"user","timestamp":"'"$bnow"'","message":{"content":5}}' '{"type":"assistant","timestamp":"'"$bnow"'","message":{"content":[{"type":"text","text":null}]}}' '{"type":"assistant","timestamp":"'"$bnow"'","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":3}}]}}'; do
    # shellcheck disable=SC2059
    printf "$(printf '%s' "$bodd" | sed 's/%/%%/g')\n" > "$BF/stray/odd.jsonl"
    printf 'old digest\n' > "$WIKIS_DIR/journal/backfill.md"
    if "$T/bin/llm-wiki" journal-backfill "$BF" 2026-01-14 2026-01-17 04:00 "$WIKIS_DIR" "" "$WIKIS_DIR/journal/backfill.md" "$HOME/.gemini/antigravity/brain" >/dev/null 2>&1; then
      bad "the helper leaves an odd record to the Python: $bodd"
    elif [ "$(cat "$WIKIS_DIR/journal/backfill.md")" != "old digest" ] || compgen -G "$WIKIS_DIR/journal/.backfill.md.tmp-*" >/dev/null; then
      bad "and leaves the old digest alone: $bodd" "$(ls -a "$WIKIS_DIR/journal")"
    elif [ "$(LLM_WIKI_NO_GO=1 bf --since 2026-01-14 --until 2026-01-17)" = "$(LLM_WIKI_GO="$T/bin/llm-wiki" bf --since 2026-01-14 --until 2026-01-17)" ]; then
      ok "the helper leaves an odd record to the Python, and the old digest alone: $bodd"
    else
      bad "the digest on an odd record matches the Python: $bodd"
    fi
  done
  rm -rf "$BF" "$T/bf-stray" "$WIKIS_DIR/journal/backfill.md"
  rm -rf "$HOME/.gemini"
else
  skipped "the Go helper against the Python (go isn't installed)"
fi
rm -f "$HOME/.claude/projects/p1/s2.jsonl"
case "$out" in *"## What the wikis gained"*"- demo:"*"note(s) captured"*) ok "report lists what each wiki gained" ;; *) bad "report lists what each wiki gained" "$out" ;; esac
case "$out" in *"Corrections recorded as Feedback lines:"*) ok "report counts recorded corrections" ;; *) bad "report counts recorded corrections" "$out" ;; esac
case "$out" in *"Tokens (Gemini"*) bad "without Antigravity, no Gemini token table" "$out" ;; *) ok "without Antigravity, no Gemini token table" ;; esac
G="$HOME/.gemini/antigravity/brain/convR/.system_generated/logs"; mkdir -p "$G"
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
{
  printf '{"type":"USER_INPUT","created_at":"%s","content":"hi","input_tokens":1500,"cache_read_tokens":20000,"output_tokens":300}\n' "$now"
  printf '{"type":"PLANNER_RESPONSE","created_at":"%s","tool_calls":[{"name":"read_file","args":{"Path":"%s/projects/web/x.ts"}}],"input_tokens":500,"output_tokens":100}\n' "$now" "$T"
} > "$G/transcript_full.jsonl"
out="$("$W" report 2>&1)"
case "$out" in *"## Tokens (Gemini in Antigravity)"*"| demo | 1 | 2k | 20k | 400 |"*"syncs and status."$'\n'"Gemini counts tokens its own way, so these don't add to Claude's."*) ok "report adds a separate Gemini token table, by project" ;; *) bad "report adds a separate Gemini token table, by project" "$out" ;; esac
"$W" journal set exclude demo >/dev/null
out="$("$W" report 2>&1)"
case "$out" in *"| demo | 1 |"*) bad "journal exclude leaves a project out of both token tables" "$out" ;; *) ok "journal exclude leaves a project out of both token tables" ;; esac
"$W" journal set exclude "" >/dev/null
rm -rf "$HOME/.gemini"
for i in 01 02 03 04 05 06 07 08 09 10; do printf 'Captured: %s\n\nA note.\n' "$(date -u +%Y-%m-%d)" > "$WIKIS_DIR/global/raw/$(date -u +%Y-%m-%d)-1200$i-busy-$i.md"; done
expect "a busy week with no corrections becomes a Needs you item" "may have gone to its own memory" "$W" report
printf 'Captured: %s\n\nFeedback: correction | everywhere | Ask before pushing.\n' "$(date -u +%Y-%m-%d)" > "$WIKIS_DIR/global/raw/$(date -u +%Y-%m-%d)-120099-feedback.md"
lacks "and goes away once one is recorded" "may have gone to its own memory" "$W" report
rm -f "$WIKIS_DIR"/global/raw/*-busy-*.md "$WIKIS_DIR"/global/raw/*-120099-feedback.md
# An example of a callout, in a code fence, isn't an open one.
printf 'An example:\n\n```markdown\n> **Conflict:** only an example.\n```\n' > "$WIKIS_DIR/demo/wiki/fenced.md"
lacks "a fenced callout stays out of the report" "only an example" "$W" report
lacks "and the standup" "only an example" "$W" standup --since 7d
lacks "and lint" "open Conflict" "$W" lint demo
printf '\n> **Check:** a real one after the fence.\n' >> "$WIKIS_DIR/demo/wiki/fenced.md"
expect "one after the fence still counts in the report" "a real one after the fence" "$W" report
expect "and the standup" "a real one after the fence" "$W" standup --since 7d
expect "and lint" "open Check" "$W" lint demo
rm -f "$WIKIS_DIR/demo/wiki/fenced.md"
printf '> **Conflict:** raw/a.md says X. raw/b.md says Y. Unresolved.\n' >> "$WIKIS_DIR/demo/wiki/conflict-test.md"
printf '\n## Wrap errors\n- kind: review\n- rule: Wrap errors.\n- status: proposed 2026-10-20\n' >> "$WIKIS_DIR/demo/patterns.md"
out="$("$W" report 2>&1)"
case "$out" in *"## Needs you"*"open **Conflict:**"*) ok "Needs you lists open contradictions" ;; *) bad "Needs you lists open contradictions" "$out" ;; esac
case "$out" in *"waits for an answer: Wrap errors"*) ok "Needs you lists unanswered proposals" ;; *) bad "Needs you lists unanswered proposals" "$out" ;; esac
cp "$WIKIS_DIR/demo/patterns.md" "$T/patterns.bak"
printf '\n## Pin versions\n- kind: correction\n- rule: Pin versions.\n- status: accepted 2026-10-01: a convention\n- seen: 2026-09-20 api raw/a.md\n- seen: 2026-10-05 api raw/b.md\n' >> "$WIKIS_DIR/demo/patterns.md"
expect "patterns flags an accepted fix seen again since" "AGAIN  Pin versions" "$W" patterns
expect "and status says the fix isn't working" "accepted fix(es) not working" "$W" status
expect "and so does the report" "seen again since, so not working" "$W" report
# Every call to action ends with its fix: a command, a request for an agent, or a step.
fixless() { "$W" "$1" 2>&1 | fixes "$2"; }
fixes() { awk -v h="$1" '$0 == h { on = 1; next } on && /^#/ { on = 0 } on && /^- / && !/(Run: |Ask an agent: |Do: )/ { print "no fix: " $0 }'; }
out="$("$W" report 2>&1)"
lacks "every Needs you line in report ends with its fix" "no fix:" fixless report '## Needs you'
case "$out" in *"resolve the conflict in demo's wiki/conflict-test.md: <your decision>"*) ok "a conflict names its page and what to ask" ;; *) bad "a conflict names its page and what to ask" "$out" ;; esac
case "$out" in *"show me the proposed fix 'Wrap errors' in demo"*) ok "a proposal says how to answer it" ;; *) bad "a proposal says how to answer it" "$out" ;; esac
out="$("$W" status 2>&1)"
lacks "every To do line in status ends with its fix" "no fix:" fixless status 'To do:'
case "$out" in *"To do:"*"Ask an agent: \"look again at the patterns marked AGAIN in demo\""*) ok "status gathers the calls to action under To do" ;; *) bad "status gathers the calls to action under To do" "$out" ;; esac
cp "$T/patterns.bak" "$WIKIS_DIR/demo/patterns.md"
printf '\n## Pin versions\n- kind: correction\n- rule: Pin versions.\n- status: accepted 2026-10-01: a convention\n- seen: 2026-09-20 api raw/a.md\n' >> "$WIKIS_DIR/demo/patterns.md"
lacks "an accepted fix not seen since isn't flagged" "AGAIN" "$W" patterns
cp "$T/patterns.bak" "$WIKIS_DIR/demo/patterns.md"
rm -f "$WIKIS_DIR/demo/wiki/conflict-test.md"
# Open items: Waiting: and Due: lines tallied in open.md. Dates come from the clock.
day_off() { date -u -d "$1 days" +%Y-%m-%d 2>/dev/null || date -u -v"$([ "$1" -ge 0 ] && echo "+$1" || echo "$1")"d +%Y-%m-%d; }
SOON="$(day_off 3)"
PAST="$(day_off -3)"
OPEN="$WIKIS_DIR/demo/open.md"
cp "$OPEN" "$T/open.bak"
lacks "status has no open line when nothing is open" "- open: " "$W" status
expect "open says when nothing is open" "Nothing open." "$W" open
expect "open --help describes the command" "Waiting: and Due: lines" "$W" open --help
{
  printf '\n## Confirm the hook fires in Antigravity\n- kind: waiting\n- who: user\n- status: open\n- from: %s raw/a.md\n' "$SOON"
  printf '\n## Read the first week of runs\n- kind: due\n- due: %s\n- status: open\n- from: %s raw/a.md\n' "$SOON" "$SOON"
  printf '\n## Check the retry fix held\n- kind: due\n- due: %s\n- status: open\n- from: %s raw/a.md\n' "$PAST" "$PAST"
  printf '\n## Reply to the vendor\n- kind: waiting\n- who: Dana\n- status: done %s\n- from: %s raw/a.md\n' "$PAST" "$PAST"
} >> "$OPEN"
expect "open lists a waiting entry and who it waits on" "Confirm the hook fires in Antigravity (waiting on user)" "$W" open
expect "and a due entry in the future" "Read the first week of runs (due $SOON)" "$W" open
expect "and marks a due entry in the past overdue" "OVERDUE  Check the retry fix held (due $PAST)" "$W" open
lacks "and leaves a done entry out" "Reply to the vendor" "$W" open
expect "and ends with a count" "3 open in 1 wiki(s), 1 past their date." "$W" open
out="$("$W" open 2>&1)"
case "$out" in *"OVERDUE"*"Confirm the hook"*) ok "an overdue entry comes before the others in its wiki" ;; *) bad "an overdue entry comes before the others in its wiki" "$out" ;; esac
expect "status counts what is open and what is past its date" "- open: 3 item(s) waiting on someone or a date, 1 past its date. Run: " "$W" status
lacks "every To do line in status still ends with its fix" "no fix:" fixless status 'To do:'
lacks "lint has no finding for a well-formed open.md" "open.md entry not understood" "$W" lint demo
printf '\n## No kind here\n- status: open\n\n## Due without a date\n- kind: due\n- due: next week\n- status: open\n' >> "$OPEN"
expect "lint reports an entry with no kind" "No kind here (kind is missing or not waiting or due)" "$W" lint demo
expect "and a due entry with no valid date" "Due without a date (a due entry needs a date as YYYY-MM-DD)" "$W" lint demo
cp "$T/open.bak" "$OPEN"
# Transcripts this shell can't read, as in an agent's sandbox, used to read as a week
# with no sessions.
if [ "$(id -u)" != 0 ]; then
  chmod 000 "$HOME/.claude/projects"
  expect "report says when it can't read the transcripts" "Can't read ~/.claude/projects from this shell" "$W" report
  expect "and so does the old code" "Can't read ~/.claude/projects from this shell" env LLM_WIKI_NO_GO=1 "$W" report
  lacks "instead of a week with no sessions" "No Claude Code sessions in this range" "$W" report
  chmod 755 "$HOME/.claude/projects"
else
  skipped "transcripts that can't be read (root can read anything)"
fi
lacks "a new collection's report isn't due yet" "due" "$W" report --due
touch -t 202001010000 "$WIKIS_DIR/WIKIS.md"
rm -f "$HOME/.config/llm-wiki/tips"
expect "after a week the report is due" "due" "$W" report --due
lacks "and then not again for a week" "due" "$W" report --due
rm -f "$HOME/.config/llm-wiki/tips"
out="$(hook "$T/projects/web" '{"source":"startup"}' | context 2>&1)"
case "$out" in *"weekly wiki report is due"*) ok "the session hook offers the weekly report" ;; *) bad "the session hook offers the weekly report" "$out" ;; esac
case "$out" in *"One tip"*) bad "a week with a report offer has no tip" "$out" ;; *) ok "a week with a report offer has no tip" ;; esac
fi

if section "Bookkeeping commands"; then
out="$("$W" log --help 2>&1)" && case "$out" in *"Usage:"*"--source raw/FILE"*"--corrections N"*"--patterns N"*) ok "log --help lists every option" ;; *) bad "log --help lists every option" "$out" ;; esac || bad "log --help lists every option" "$out"
out="$(printf 'We picked Postgres.\n' | "$W" capture demo "Decided Postgres!" 2>&1)"
case "$out" in *"captured: raw/20"*"-decided-postgres.md"*) ok "capture names a note from the clock and the slug" ;; *) bad "capture names a note from the clock and the slug" "$out" ;; esac
f="$(ls "$WIKIS_DIR"/demo/raw/*-decided-postgres.md | head -n 1)"
check "capture adds the Captured line" bash -c "head -n 1 '$f' | grep -q '^Captured: '"
check "capture's name has seconds, not a guess" bash -c "basename '$f' | grep -Eq '^20[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{6}-'"
printf 'Captured: 2026-01-01\n\nAlready has it.\n' | "$W" capture demo decided-postgres >/dev/null
check "a second capture in the same second never overwrites" bash -c "ls '$WIKIS_DIR'/demo/raw/ | grep -q 'decided-postgres-2.md' || [ \$(ls '$WIKIS_DIR'/demo/raw/ | grep -c decided-postgres) -ge 2 ]"
check "a note that has the line keeps just one" bash -c "[ \$(cat '$WIKIS_DIR'/demo/raw/*decided-postgres*.md | grep -c '^Captured:') -eq 2 ]"
printf 'pdf bytes\n' > "$T/spec.pdf"
expect "capture --copy stores a document unchanged" "spec.pdf" "$W" capture demo --copy "$T/spec.pdf"
refuse "capture refuses an empty note" bash -c "'$W' capture demo empty </dev/null"
printf 'From a file.\n' > "$T/note.md"
expect "capture --file reads the note from a file" "captured: raw/" "$W" capture demo from-file --file "$T/note.md"
check "and adds the Captured line" bash -c "head -n 1 \"\$(ls '$WIKIS_DIR'/demo/raw/*-from-file.md)\" | grep -q '^Captured: '"
refuse "capture --file needs the file to exist" "$W" capture demo nope --file "$T/nope.md"
refuse "capture refuses --file and --copy together" "$W" capture demo both --file "$T/note.md" --copy "$T/note.md"
# An agent's sandbox can block writes to the wikis. Each command must say so and
# fail, never report a capture, lock or log entry that wasn't written.
chmod 555 "$WIKIS_DIR/demo/raw"
out="$(printf 'x\n' | "$W" capture demo blocked 2>&1)" && bad "capture fails when it can't write the note (it succeeded)" "$out" || ok "capture fails when it can't write the note"
case "$out" in *"Nothing was saved"*) ok "and says nothing was saved" ;; *) bad "and says nothing was saved" "$out" ;; esac
chmod 755 "$WIKIS_DIR/demo/raw"
check "and leaves no note behind" bash -c "! ls '$WIKIS_DIR'/demo/raw/ | grep -q blocked"
printf 'free\n' > "$WIKIS_DIR/demo/.compile-lock" && chmod 444 "$WIKIS_DIR/demo/.compile-lock"
refuse "lock fails when it can't write the lock" "$W" lock demo
chmod 644 "$WIKIS_DIR/demo/.compile-lock"
chmod 444 "$WIKIS_DIR/demo/log.md"
refuse "log fails when it can't write log.md" "$W" log demo ingest "Note: blocked" --conflicts 0
chmod 644 "$WIKIS_DIR/demo/log.md"
expect "lock takes a free lock" "locked:" "$W" lock demo
refuse "lock refuses a held one" "$W" lock demo
expect "lock --renew rewrites the time" "renewed:" "$W" lock demo --renew
expect "lock --release frees it" "released:" "$W" lock demo --release
printf 'held abc123 2020-01-01T00:00:00Z\n' > "$WIKIS_DIR/demo/.compile-lock"
expect "a lock older than 30 minutes is taken" "locked:" "$W" lock demo
"$W" lock demo --release >/dev/null
fi

if section "Background compile"; then
# A stand-in for the headless agent: it keeps the prompt, and logs each waiting note
# as compiled, which is what marks one done.
cat > "$T/bin/fake-agent" <<FAKE
#!/bin/sh
cat > "$T/fake-prompt"
[ -z "\${FAKE_SLEEP:-}" ] || sleep "\$FAKE_SLEEP"
[ -z "\${FAKE_FAIL:-}" ] || { echo "fake-agent: refused" >&2; exit 3; }
[ -z "\${FAKE_NOTHING:-}" ] || { echo "fake-agent: left them all, none could be compiled"; exit 0; }
for f in \$("$W" pending "\$LLM_WIKI_COMPILE_WIKI" | sed -n 's/^\(raw\/[^ ]*\).*/\1/p'); do
  "$W" log "\$LLM_WIKI_COMPILE_WIKI" ingest "Fake" --source "\$f" >/dev/null
done
[ -z "\${FAKE_LATE:-}" ] || printf 'Captured: 2026-01-01\n\nLate.\n' > "$WIKIS_DIR/bg/raw/2026-01-01-000009-late.md"
echo "0 created, 0 updated"
FAKE
chmod +x "$T/bin/fake-agent"
"$W" new bg >/dev/null
BG="$WIKIS_DIR/bg"
BGC="$HOME/.config/llm-wiki/compile"
BGR="$HOME/.local/state/llm-wiki/compile/runs.csv"
bg_note() { printf 'Captured: 2026-01-01\n\nNote %s.\n' "$1" > "$BG/raw/2026-01-01-00000$1-note.md"; }
# bg_runs <n>: wait for the nth run to be recorded, which is the last thing a run does.
bg_runs() {
  local i=0
  while [ "$i" -lt 150 ]; do
    [ "$(grep -c ',bg,' "$BGR" 2>/dev/null || true)" -lt "$1" ] || return 0
    sleep 0.2
    i=$((i + 1))
  done
  return 1
}
bg_hook() { hook "$T/projects/bg" | context; }
mkdir -p "$T/projects/bg" "${BGC%/*}" && git -C "$T/projects/bg" init -q
bg_note 1
bg_note 2
expect "background compile is off by default" "at session start: off" "$W" compile
expect "setup --list says sessions compile" "background compile is off" "$W" setup --list
lacks "off, the hook leaves the notes to the session" "in the background" bg_hook
printf 'agent=no-such-agent-here\n' > "$BGC"
out="$("$W" compile bg 2>&1)" && bad "compile needs its agent installed" "$out" || case "$out" in *"isn't a command here"*) ok "compile needs its agent installed" ;; *) bad "compile needs its agent installed" "$out" ;; esac
check "and takes no lock" test ! -f "$BG/.compile-lock"
printf 'agent=%s\n' "$T/bin/fake-agent" > "$BGC"
out="$("$W" compile bg 2>&1)"
case "$out" in *"compiled: bg, 2 of 2 note(s)"*", ok."*) ok "compile runs the agent and reports" ;; *) bad "compile runs the agent and reports" "$out" ;; esac
case "$out" in *Terminated*) bad "stopping its timer prints nothing" "$out" ;; *) ok "stopping its timer prints nothing" ;; esac
check "the agent is told which wiki, and that nobody is watching" grep -q "wiki at $BG, unattended" "$T/fake-prompt"
check "and that the lock is already its own" grep -q "lock is already held for you" "$T/fake-prompt"
check "and never to resolve a contradiction" grep -q "Never resolve a contradiction" "$T/fake-prompt"
expect "the lock is free afterwards" "free" cat "$BG/.compile-lock"
expect "nothing is left waiting" "nothing waiting" "$W" pending bg
check "the run is recorded" grep -q ',bg,2,0,[0-9]*,[0-9]*,ok,fake-agent$' "$BGR"
check "and committed" bash -c "git -C '$WIKIS_DIR' log --format=%s -5 | grep -q 'bg: background compile, 2 of 2 note(s), ok'"
expect "compile alone shows the last runs" ",bg,2,0," "$W" compile
expect "with nothing waiting, it says so" "nothing waiting" "$W" compile bg
bg_note 3
out="$(FAKE_FAIL=1 "$W" compile bg 2>&1)" && bad "a failed agent is a failed run" "$out" || case "$out" in *"0 of 1 note(s)"*", failed."*) ok "a failed agent is a failed run" ;; *) bad "a failed agent is a failed run" "$out" ;; esac
case "$out" in *"Its last line: fake-agent: refused"*) ok "and says the agent's last line" ;; *) bad "and says the agent's last line" "$out" ;; esac
expect "and the lock is freed all the same" "free" cat "$BG/.compile-lock"
out="$(FAKE_SLEEP=30 LLM_WIKI_COMPILE_TIMEOUT=1 "$W" compile bg 2>&1)" && bad "a run past its time limit is stopped" "$out" || case "$out" in *", timeout."*) ok "a run past its time limit is stopped" ;; *) bad "a run past its time limit is stopped" "$out" ;; esac
expect "and the lock is freed then too" "free" cat "$BG/.compile-lock"
# The time limit's own sleep ending early, as it does when the limit is called off a
# moment after the agent finishes, used to mark the run as timed out and stop the agent.
mkdir -p "$T/nosleep" && printf '#!/bin/sh\nexit 1\n' > "$T/nosleep/sleep" && chmod +x "$T/nosleep/sleep"
out="$(PATH="$T/nosleep:$PATH" "$W" compile bg 2>&1)"
case "$out" in *"1 of 1 note(s)"*", ok."*) ok "a time limit that ends early stops nothing" ;; *) bad "a time limit that ends early stops nothing" "$out" ;; esac
bg_note 0
"$W" lock bg >/dev/null
rm -f "$T/fake-prompt"
refuse "compile leaves a held lock alone" "$W" compile bg
refuse "in the background too" "$W" compile bg --background
check "and runs no agent" test ! -f "$T/fake-prompt"
"$W" lock bg --release >/dev/null
n="$(grep -c ',bg,' "$BGR")"
out="$(FAKE_SLEEP=1 "$W" compile bg --background 2>&1)"
case "$out" in *"1 note(s)"*"in the background"*) ok "--background returns at once" ;; *) bad "--background returns at once" "$out" ;; esac
expect "holding the lock while it runs" "held " cat "$BG/.compile-lock"
check "the background run finishes" bg_runs $((n + 1))
expect "having compiled the note" "nothing waiting" "$W" pending bg
expect "and freed the lock" "free" cat "$BG/.compile-lock"
bg_note 4
expect "compile on turns it on for session start" "compile: on" "$W" compile on
expect "setup --list says so" "in the background at session start" "$W" setup --list
out="$(LLM_WIKI_BACKGROUND=1 hook "$T/projects/bg")"
[ -z "$out" ] && ok "a background run's own session gets nothing from the hook" || bad "a background run's own session gets nothing from the hook" "$out"
expect "and starts no run of its own" "free" cat "$BG/.compile-lock"
expect "its start says the notes are its own" "This run is the one compiling them" env LLM_WIKI_BACKGROUND=1 "$W" start bg
n="$(grep -c ',bg,' "$BGR")"
expect "on, the hook hands the notes to a background run" "being compiled in the background now" bg_hook
check "which finishes" bg_runs $((n + 1))
expect "and compiles them" "nothing waiting" "$W" pending bg
bg_note 5
expect "start hands notes over too" "being compiled in the background now" "$W" start bg
check "and that run finishes" bg_runs $((n + 2))
bg_note 6
"$W" lock bg >/dev/null
expect "start says when another session holds the lock" "another session holds the compile lock" "$W" start bg
lacks "and the hook starts nothing then" "in the background" bg_hook
"$W" lock bg --release >/dev/null
expect "compile off turns it off" "compile: off" "$W" compile off
expect "off, start leaves the notes to the session" "Compile them before the user's request" "$W" start bg
refuse "compile rejects an unknown option" "$W" compile bg --nope
printf 'auto=off\nagent=no-such-agent-here\n' > "$BGC"
lacks "off, start says nothing about a missing agent" "isn't a command in this shell" "$W" start bg
printf 'auto=on\nagent=no-such-agent-here\n' > "$BGC"
expect "on with its agent missing, start says why nothing started" "no-such-agent-here isn't a command in this shell" "$W" start bg
expect "and still leaves the notes to the session" "Compile them before the user's request" "$W" start bg
# A stand-in for Claude Code, which unlike another agent is run headless with a tool
# list. It keeps its arguments and logs the waiting notes as compiled.
mkdir -p "$T/claude-bin"
cat > "$T/claude-bin/claude" <<FAKE
#!/bin/sh
[ "\$1" != --version ] || exit 0
printf '%s\n' "\$@" > "$T/claude-args"
cat > /dev/null
for f in \$("$W" pending bg | sed -n 's/^\(raw\/[^ ]*\).*/\1/p'); do
  "$W" log bg ingest "Fake" --source "\$f" >/dev/null
done
FAKE
chmod +x "$T/claude-bin/claude"
printf 'agent=%s\n' "$T/claude-bin/claude" > "$BGC"
out="$("$W" compile bg 2>&1)"
case "$out" in *"1 of 1 note(s)"*", ok."*) ok "claude named by its full path runs" ;; *) bad "claude named by its full path runs" "$out" ;; esac
check "as Claude Code: headless, on sonnet, with a tool list" bash -c "grep -qx -- '-p' '$T/claude-args' && grep -qx 'sonnet' '$T/claude-args' && grep -qx -- '--allowedTools' '$T/claude-args'"
check "allowed the wiki commands a compile needs" grep -q '^Bash(.* pending \*)$' "$T/claude-args"
check "and recorded by its name" grep -q ',ok,claude$' "$BGR"
rm -f "$BGC" "$T/claude-args"
bg_note 7
out="$(PATH="$T/claude-bin:$PATH" "$W" compile bg 2>&1)"
case "$out" in *"1 of 1 note(s)"*", ok."*) ok "with no agent named, claude on the PATH runs" ;; *) bad "with no agent named, claude on the PATH runs" "$out" ;; esac
check "the same way" grep -qx -- '--allowedTools' "$T/claude-args"
# A note captured while a run is going is the next run's. It used to turn a run that
# compiled everything it was given into "0 of 1, partial".
printf 'agent=%s\n' "$T/bin/fake-agent" > "$BGC"
bg_note 8
# A run that ends well and compiled none of its notes isn't "partial": nothing was done.
out="$(FAKE_NOTHING=1 "$W" compile bg 2>&1)" && bad "a run that compiles nothing is recorded as none" "$out" || case "$out" in *"0 of 1 note(s)"*", none."*) ok "a run that compiles nothing is recorded as none" ;; *) bad "a run that compiles nothing is recorded as none" "$out" ;; esac
case "$out" in *"Its last line: fake-agent: left them all"*) ok "and says the agent's last line, which is where it says why" ;; *) bad "and says the agent's last line, which is where it says why" "$out" ;; esac
check "and so in the runs" bash -c "tail -n 1 '$BGR' | grep -q ',bg,1,1,[0-9]*,[0-9]*,none,fake-agent$'"
out="$(FAKE_LATE=1 "$W" compile bg 2>&1)"
case "$out" in *"1 of 1 note(s)"*", ok."*) ok "a note captured during a run doesn't count against it" ;; *) bad "a note captured during a run doesn't count against it" "$out" ;; esac
check "the run is recorded with nothing left" bash -c "tail -n 1 '$BGR' | grep -q ',bg,1,0,[0-9]*,[0-9]*,ok,fake-agent$'"
expect "and the late note waits for the next run" "000009-late" "$W" pending bg
# Claude Code that is installed and can't be executed, as in an agent's sandbox. The
# run used to start and fail at once, after start had told the session to leave the notes.
mkdir -p "$T/claude-blocked"
printf '#!/bin/sh\nexit 126\n' > "$T/claude-blocked/claude" && chmod +x "$T/claude-blocked/claude"
printf 'auto=on\nagent=%s\n' "$T/claude-blocked/claude" > "$BGC"
n="$(grep -c ',bg,' "$BGR")"
out="$("$W" start bg 2>&1)"
case "$out" in *"claude can't be run from this shell, so it didn't start"*) ok "on with Claude Code it can't run, start says why nothing started" ;; *) bad "on with Claude Code it can't run, start says why nothing started" "$out" ;; esac
case "$out" in *"Compile them before the user's request"*) ok "and leaves the notes to the session" ;; *) bad "and leaves the notes to the session" "$out" ;; esac
case "$out" in *"in the background now"*) bad "and doesn't say a run has them" "$out" ;; *) ok "and doesn't say a run has them" ;; esac
lacks "the hook starts nothing either" "in the background" bg_hook
out="$("$W" compile bg 2>&1)" && bad "compile says it can't run Claude Code" "$out" || case "$out" in *"claude can't be run from this shell"*) ok "compile says it can't run Claude Code" ;; *) bad "compile says it can't run Claude Code" "$out" ;; esac
expect "and so does compile on" "can't be run from this shell" "$W" compile on
check "no run was started or recorded" test "$(grep -c ',bg,' "$BGR")" = "$n"
expect "and the lock is free" "free" cat "$BG/.compile-lock"
if [ "$(id -u)" != 0 ]; then
  chmod 000 "$BGR"
  out="$("$W" compile 2>&1)" && case "$out" in *"can't read"*"runs.csv from this shell"*) ok "compile alone says when it can't read the runs" ;; *) bad "compile alone says when it can't read the runs" "$out" ;; esac || bad "compile alone says when it can't read the runs" "$out"
  case "$out" in *"ermission denied"*) bad "without a raw error" "$out" ;; *) ok "without a raw error" ;; esac
  chmod 644 "$BGR"
else
  skipped "a runs file that can't be read (root can read anything)"
fi
rm -f "$BGC"
fi

if section "Reminders"; then
"$W" new rem >/dev/null
RM="$WIKIS_DIR/rem"
RD="$HOME/.local/state/llm-wiki/reminders"
mkdir -p "$T/projects/rem" && git -C "$T/projects/rem" init -q
cat > "$RM/wiki/conventions.md" <<'REM'
---
title: Conventions for rem
summary: How to work in rem.
updated: 2026-11-05
verified: 2026-11-05
---

## For agents

- Check CI after a push.

## Reminders

- before bash `git push`: Before a push, make sure the hooks ran. [raw/2026-01-01-000000-x.md]
- on edit `payments/*`: Money is in cents. (raw/2026-01-01-000000-y.md)
- on tool `Agent`: Set the model.
- on bash `[ -f retry.conf ]`: Read retry.conf first.
- sometimes bash `x`: not a reminder
- on bash ` `: a pattern of one space would match nearly every command

```
- before bash `git tag`: an example inside a fence
```

## Tools

- ls (cli): listing
REM
printf '\n## Reminders\n\n- on bash `npm publish`: Ask first.\n' >> "$WIKIS_DIR/global/wiki/conventions.md"
TAB="$(printf '\t')"
out="$("$W" __reminders "$RM" 2>&1)"
case "$out" in *"before${TAB}bash${TAB}git push${TAB}Before a push, make sure the hooks ran.${TAB}rem"*) ok "a reminder line is read, without its citation" ;; *) bad "a reminder line is read, without its citation" "$out" ;; esac
case "$out" in *"on${TAB}edit${TAB}payments/*${TAB}Money is in cents.${TAB}rem"*) ok "or its citation in round brackets, which pages also use" ;; *) bad "or its citation in round brackets, which pages also use" "$out" ;; esac
case "$out" in "on${TAB}bash${TAB}npm publish${TAB}Ask first.${TAB}global"*) ok "the shared wiki's reminders come first" ;; *) bad "the shared wiki's reminders come first" "$out" ;; esac
check "five are read: one shared, four of its own" test "$(printf '%s\n' "$out" | grep -vc "$TAB-\$")" = 5
case "$out" in *"on${TAB}bash${TAB}gh release create${TAB}This looks like an operational job"*"${TAB}-") ok "and the built-in ones come last, with - for the wiki" ;; *) bad "and the built-in ones come last, with - for the wiki" "$out" ;; esac
case "$out" in *"not a reminder"* | *"inside a fence"*) bad "a line that isn't a reminder, or sits in a code fence, is left out" "$out" ;; *) ok "a line that isn't a reminder, or sits in a code fence, is left out" ;; esac
out="$("$W" lint rem 2>&1)"
case "$out" in *"reminder line not understood: 2"*"sometimes bash"*) ok "lint names the line it couldn't read" ;; *) bad "lint names the line it couldn't read" "$out" ;; esac
case "$out" in *"a pattern of one space"*) ok "and one whose pattern is only a space" ;; *) bad "and one whose pattern is only a space" "$out" ;; esac
lacks "and not the one in the fence" "inside a fence" "$W" lint rem

# tool_call <json>: what the tool-call hook replies.
tool_call() { printf '%s' "$1" | CLAUDE_PLUGIN_ROOT="$REPO" sh "$REPO/hooks/pre-tool-use.sh"; }
check "the plugin registers the tool-call hook" grep -q '"PreToolUse"' "$REPO/hooks/hooks.json"
check "its Python parses" python3 -c "import ast, sys; ast.parse(open(sys.argv[1]).read())" "$REPO/hooks/reminders.py"
out="$(tool_call '{"session_id":"s-1","tool_name":"Bash","tool_input":{"command":"git push"}}')"
[ -z "$out" ] && ok "with no session started, a tool call gets nothing" || bad "with no session started, a tool call gets nothing" "$out"
hook "$T/projects/rem" '{"session_id":"s-1","source":"startup"}' >/dev/null
check "session start writes the session's reminders" test "$(grep -vc "$TAB-\$" "$RD/s-1.tsv")" = 5
push='{"session_id":"s-1","cwd":"'"$T/projects/rem"'","tool_name":"Bash","tool_input":{"command":"cd x && git push origin main"}}'
out="$(tool_call "$push")"
case "$out" in *'"permissionDecision": "deny"'*"make sure the hooks ran"*"from the wiki rem"*) ok "a before reminder stops the call once, with the rule" ;; *) bad "a before reminder stops the call once, with the rule" "$out" ;; esac
if printf '%s' "$out" | python3 -c 'import json, sys; json.load(sys.stdin)' 2>/dev/null; then ok "and its reply is JSON"; else bad "and its reply is JSON" "$out"; fi
out="$(tool_call "$push")"
[ -z "$out" ] && ok "the same call made again goes through" || bad "the same call made again goes through" "$out"
edit='{"session_id":"s-1","cwd":"'"$T/projects/rem"'","tool_name":"Edit","tool_input":{"file_path":"'"$T/projects/rem"'/payments/charge.go"}}'
out="$(tool_call "$edit")"
case "$out" in *'"additionalContext"'*"Money is in cents"*) ok "an on reminder comes as context for a matching file" ;; *) bad "an on reminder comes as context for a matching file" "$out" ;; esac
case "$out" in *permissionDecision*) bad "and doesn't stop the call" "$out" ;; *) ok "and doesn't stop the call" ;; esac
out="$(tool_call "$edit")"
[ -z "$out" ] && ok "each reminder is given once a session" || bad "each reminder is given once a session" "$out"
out="$(tool_call '{"session_id":"s-1","cwd":"'"$T/projects/rem"'","tool_name":"Read","tool_input":{"file_path":"'"$T/projects/rem"'/payments/x.go"}}')"
[ -z "$out" ] && ok "a file reminder is for edits, not reads" || bad "a file reminder is for edits, not reads" "$out"
expect "a tool reminder matches the tool's name" "Set the model" tool_call '{"session_id":"s-1","tool_name":"Agent","tool_input":{"prompt":"x"}}'
expect "the shared wiki's reminder applies too" "Ask first. (from the wiki global" tool_call '{"session_id":"s-1","tool_name":"Bash","tool_input":{"command":"npm publish"}}'
out="$(tool_call '{"session_id":"s-1","tool_name":"Bash","tool_input":{"command":"ls"}}')"
[ -z "$out" ] && ok "a call no reminder covers gets nothing" || bad "a call no reminder covers gets nothing" "$out"
# Only * is special. Read as a shell glob, [ -f retry.conf ] is a set of letters, and
# any command holding one of them would match.
out="$(tool_call '{"session_id":"s-1","tool_name":"Bash","tool_input":{"command":"git status"}}')"
[ -z "$out" ] && ok "a bracket in a pattern is a bracket, not a set of letters" || bad "a bracket in a pattern is a bracket, not a set of letters" "$out"
# The built-in reminder: a release or a deploy is an operational job, recorded from its
# first run. Left to memory, 14 releases of llm-relay went by with nothing written down.
hook "$T/projects/rem" '{"session_id":"s-ops","source":"startup"}' >/dev/null
out="$(tool_call '{"session_id":"s-ops","tool_name":"Bash","tool_input":{"command":"git tag -l"}}')"
[ -z "$out" ] && ok "listing tags is not a release" || bad "listing tags is not a release" "$out"
out="$(tool_call '{"session_id":"s-ops","tool_name":"Bash","tool_input":{"command":"git tag -a v1.2.0 -m x && git tag v1.2.0-rc"}}')"
case "$out" in *'"additionalContext"'*"operational job"*"Feedback: toil"*"from the handbook, rules/patterns.md"*) ok "a release command gets the reminder to record the job" ;; *) bad "a release command gets the reminder to record the job" "$out" ;; esac
case "$out" in *permissionDecision*) bad "and it doesn't stop the call" "$out" ;; *) ok "and it doesn't stop the call" ;; esac
check "a command two of its patterns match hears it once" test "$(printf '%s' "$out" | grep -o 'operational job' | grep -c .)" = 1
out="$(tool_call '{"session_id":"s-ops","tool_name":"Bash","tool_input":{"command":"gh release create v1.2.0"}}')"
[ -z "$out" ] && ok "and the rest of the release doesn't hear it again" || bad "and the rest of the release doesn't hear it again" "$out"
mkdir -p "$T/projects/plain"
"$W" new plain >/dev/null 2>&1
hook "$T/projects/plain" '{"session_id":"s-plain","source":"startup"}' >/dev/null
expect "a wiki with no reminders of its own still gets it" "operational job" tool_call '{"session_id":"s-plain","tool_name":"Bash","tool_input":{"command":"terraform apply -auto-approve"}}'
expect "and matches the command that holds it" "Read retry.conf first" tool_call '{"session_id":"s-1","tool_name":"Bash","tool_input":{"command":"[ -f retry.conf ] && cat retry.conf"}}'
check "a question mark is itself too" python3 -B -c "
import io, sys
sys.argv, sys.stdin = ['x', '/nowhere'], io.StringIO('')
sys.path.insert(0, '$REPO/hooks')
import reminders
assert reminders.glob('is it up?', '*up?'), 'a ? matches itself'
assert not reminders.glob('is it upx', '*up?'), 'a ? matched another character'
assert reminders.glob('a\\nb', 'a*b'), 'a * crosses lines'
"
check "a file pattern is read from the project folder down, not from the folders above it" python3 -B -c "
import io, sys
sys.argv, sys.stdin = ['x', '/nowhere'], io.StringIO('')
sys.path.insert(0, '$REPO/hooks')
import reminders
m = lambda path, cwd: reminders.matches('edit', 'payments/*', 'Edit', {'file_path': path}, cwd)
assert m('/w/app/payments/charge.go', '/w/app'), 'a folder in the project'
assert m('/w/app/svc/payments/charge.go', '/w/app'), 'a folder deeper in the project'
assert not m('/w/payments/app/src/main.go', '/w/payments/app'), 'a folder of that name above the project matched'
assert not m('/elsewhere/payments/x.go', '/w/app'), 'a file outside the project matched'
assert reminders.matches('edit', '*.sql', 'Edit', {'file_path': '/elsewhere/a.sql'}, '/w/app'), 'a pattern that fits the whole path'
assert m('/w/app/payments/charge.go', ''), 'with no project folder given, as before'
"
out="$(tool_call 'not json'; echo "rc=$?")"
[ "$out" = "rc=0" ] && ok "input it can't read is ignored, and the hook still exits 0" || bad "input it can't read is ignored, and the hook still exits 0" "$out"
out="$(tool_call '{"session_id":"../s-1","tool_name":"Bash","tool_input":{"command":"git push"}}')"
[ -z "$out" ] && ok "a session id that isn't a plain name is ignored" || bad "a session id that isn't a plain name is ignored" "$out"
hook "$T/projects/rem" '{"session_id":"s-1","source":"compact"}' >/dev/null
expect "after a compaction the reminders are given again" "make sure the hooks ran" tool_call "$push"
hook "$T/projects/rem" '{"session_id":"s-1","source":"resume"}' >/dev/null
out="$(printf '%s' "$push" | LLM_WIKI_BACKGROUND=1 CLAUDE_PLUGIN_ROOT="$REPO" sh "$REPO/hooks/pre-tool-use.sh")"
[ -z "$out" ] && ok "a background compile's session gets no reminders" || bad "a background compile's session gets no reminders" "$out"
# A read of a wiki page logs itself as a lookup, and a handoff logs its start. Neither
# needs the session to have reminders, and neither may fail the call.
LS="$WIKIS_DIR/stats.csv"; LD="$WIKIS_DIR/delegation-log.csv"
rm -f "$LS"; [ ! -f "$LD" ] || mv "$LD" "$LD.keep"
mkdir -p "$RM/wiki/concepts" "$RM/raw" "$WIKIS_DIR/notawiki/wiki" "$T/projects/rem/wiki"
printf -- '---\ntitle: A\nsummary: a\nupdated: 2026-11-09\nverified: 2026-11-09\n---\n\nText.\n' > "$RM/wiki/concepts/a.md"
cp "$RM/wiki/concepts/a.md" "$RM/wiki/concepts/b.md"
cp "$RM/wiki/concepts/a.md" "$WIKIS_DIR/notawiki/wiki/x.md"
cp "$RM/wiki/concepts/a.md" "$T/projects/rem/wiki/x.md"
printf 'a note\n' > "$RM/raw/2026-11-09-000000-n.md"
lines() { cat "$1" 2>/dev/null | grep -c . || true; }
is() { local name="$1" want="$2" got="$3"; if [ "$got" = "$want" ]; then ok "$name"; else bad "$name" "wanted: $want
got: $got"; fi; }
# read_of <session> <path>: a Read call, through the hook.
read_of() { tool_call '{"session_id":"'"$1"'","cwd":"'"$T"'/projects/rem","tool_name":"Read","tool_input":{"file_path":"'"$2"'"}}'; }
today="$(date -u +%Y-%m-%d)"
out="$(read_of l-1 "$RM/wiki/concepts/a.md"; echo "rc=$?")"
[ "$out" = "rc=0" ] && ok "a read of a wiki page gets no reply, and the hook exits 0" || bad "a read of a wiki page gets no reply, and the hook exits 0" "$out"
is "it logs a hit, under the header" "date,wiki,result
$today,rem,hit" "$(cat "$LS" 2>/dev/null)"
read_of l-1 "$RM/wiki/concepts/b.md" >/dev/null
check "a second page of the same wiki in the session logs nothing more" test "$(lines "$LS")" = 2
read_of l-2 "$RM/wiki/concepts/b.md" >/dev/null
check "another session logs its own lookup" test "$(lines "$LS")" = 3
check "and the header was written once" test "$(grep -c '^date,wiki,result' "$LS")" = 1
check "the session's reads are kept beside its reminders" test -s "$RD/l-1.reads"
for p in "$RM/index.md" "$RM/AGENTS.md" "$RM/raw/2026-11-09-000000-n.md" "$WIKIS_DIR/notawiki/wiki/x.md" "$T/projects/rem/wiki/x.md" "$T/projects/rem/payments/x.md" "$RM/wiki/concepts/nothing.md" "$RM/wiki/concepts"; do
  read_of l-3 "$p" >/dev/null
done
check "index.md, AGENTS.md, raw/, a folder that isn't a wiki, a wiki/ outside the collections, a page that isn't there and a file outside the wikis log nothing" test "$(lines "$LS")" = 3
printf '%s' '{"session_id":"l-3","tool_name":"Read","tool_input":{"file_path":"'"$RM"'/wiki/concepts/a.md"}}' | XDG_STATE_HOME="$T/no-state" sh "$REPO/hooks/pre-tool-use.sh"
check "a session with no reminders folder still logs" test "$(lines "$LS")" = 4
check "and the folder it made holds the record" test -s "$T/no-state/llm-wiki/reminders/l-3.reads"
hook "$T/projects/rem" '{"session_id":"l-6","source":"startup"}' >/dev/null
expect "a session with reminders still gets them for a Bash call" "make sure the hooks ran" tool_call '{"session_id":"l-6","cwd":"'"$T"'/projects/rem","tool_name":"Bash","tool_input":{"command":"git push"}}'
out="$(read_of l-6 "$RM/wiki/concepts/a.md")"
[ -z "$out" ] && ok "and a read of a page gets no reminder" || bad "and a read of a page gets no reminder" "$out"
check "but it logs the lookup" test "$(lines "$LS")" = 5
if [ "$(id -u)" != 0 ]; then
  chmod 444 "$LS"
  out="$(read_of l-7 "$RM/wiki/concepts/a.md"; echo "rc=$?")"
  [ "$out" = "rc=0" ] && ok "a stats.csv that can't be written doesn't fail the hook" || bad "a stats.csv that can't be written doesn't fail the hook" "$out"
  chmod 644 "$LS"
else
  skipped "a stats.csv that can't be written (root can write anywhere)"
fi
out="$(printf '%s' '{"session_id":"l-8","tool_name":"Read","tool_input":"nonsense"}' | CLAUDE_PLUGIN_ROOT="$REPO" sh "$REPO/hooks/pre-tool-use.sh"; echo "rc=$?")"
[ "$out" = "rc=0" ] && ok "a Read call of an unexpected shape is ignored" || bad "a Read call of an unexpected shape is ignored" "$out"
out="$(printf '%s' '{"session_id":"l-9","tool_name":"Read","tool_input":{"file_path":"'"$RM"'/wiki/concepts/a.md"}}' | LLM_WIKI_BACKGROUND=1 sh "$REPO/hooks/pre-tool-use.sh")"
check "a background compile's reads aren't lookups" test "$(lines "$LS")" = 5

# A handoff: the Agent and Task tools and a start_session tool write a row, "started".
# agent_call <session> <tool name> <input json>
agent_call() { printf '%s' '{"session_id":"'"$1"'","cwd":"'"$T"'/projects/rem","tool_name":"'"$2"'","tool_input":'"$3"'}' | XDG_STATE_HOME="$T/no-state" CLAUDE_PLUGIN_ROOT="$REPO" sh "$REPO/hooks/pre-tool-use.sh"; }
out="$(agent_call h-1 Agent '{"description":"Run the tests, all of them","prompt":"x","model":"sonnet","effort":"low"}'; echo "rc=$?")"
[ "$out" = "rc=0" ] && ok "an Agent call is allowed, with no reply" || bad "an Agent call is allowed, with no reply" "$out"
is "and writes a row with the model and effort, under the header" "date,project,kind,model,effort,result
$today,rem,Run the tests all of them,sonnet,low,started" "$(cat "$LD" 2>/dev/null)"
agent_call h-1 mcp__ccd_session__start_session '{"title":"Fix the build","model":"opus","effort":"high","prompt":"x"}'
is "a start_session call writes a row too" "$today,rem,Fix the build,opus,high,started" "$(tail -n 1 "$LD")"
agent_call h-1 Task '{"description":"Sweep files, again","prompt":"x"}'
is "a Task call with no model gives empty fields" "$today,rem,Sweep files again,,,started" "$(tail -n 1 "$LD")"
agent_call h-1 Agent '{"description":"'"$(printf 'word %.0s' $(seq 30))"'"}'
check "a long kind is cut at 60 characters" test "$(tail -n 1 "$LD" | cut -d, -f3 | awk '{ print length($0) }')" -le 60
agent_call h-1 mcp__other__run '{"description":"not a handoff"}'
agent_call h-1 Bash '{"command":"echo Agent start_session"}'
check "other tools add no row, and the header was written once" bash -c "test \"\$(grep -c . '$LD')\" = 5 && test \"\$(grep -c '^date,project' '$LD')\" = 1"
# A call a reminder stops is made again. Only the one let through is a handoff.
mkdir -p "$T/no-state/llm-wiki/reminders"
printf 'before\ttool\tAgent\tSay which model, and why.\trem\n' > "$T/no-state/llm-wiki/reminders/h-2.tsv"
out="$(agent_call h-2 Agent '{"description":"Stopped once","model":"haiku"}')"
case "$out" in *'"permissionDecision": "deny"'*"Say which model, and why."*) ok "an Agent call a reminder stops is refused once" ;; *) bad "an Agent call a reminder stops is refused once" "$out" ;; esac
check "and writes no row yet" test "$(grep -c 'Stopped once' "$LD")" = 0
agent_call h-2 Agent '{"description":"Stopped once","model":"haiku"}'
check "made again it goes through, and is one row" test "$(grep -c "^$today,rem,Stopped once,haiku,,started\$" "$LD")" = 1
rm -rf "$T/no-state"
"$W" delegation ask >/dev/null
out="$("$W" delegation 2>&1)"
case "$out" in *"OPEN"*"Fix the build (opus)"*"1     0      0       0     1"*"5 handoff(s)"*"no outcome recorded yet"*) ok "wiki delegation counts a started row as open, not as ok" ;; *) bad "wiki delegation counts a started row as open, not as ok" "$out" ;; esac
# An outcome goes in the row the hook wrote: the oldest open one for the project and model.
expect "an outcome closes the handoff the hook saw start" "logged: test run on sonnet (low), ok, for rem, the handoff started $today" "$W" delegation log "test run" sonnet low ok --project rem
is "in its row, with the kind the agent gave" "$today,rem,test run,sonnet,low,ok" "$(sed -n 2p "$LD")"
check "and adds no row" test "$(grep -c . "$LD")" = 6
"$W" delegation log "file sweep" flash medium fixed --project rem >/dev/null
is "a row the hook wrote with no model takes an outcome on any model" "$today,rem,file sweep,flash,medium,fixed" "$(sed -n 4p "$LD")"
"$W" delegation log "test run" sonnet low ok --project other >/dev/null
is "an outcome with no open row for its project is a row of its own" "$today,other,test run,sonnet,low,ok" "$(tail -n 1 "$LD")"
"$W" delegation log "a redo" gpt high redone --project rem >/dev/null
is "the next goes in the next open row it fits, oldest first" "$today,rem,a redo,gpt,high,redone" "$(sed -n 5p "$LD")"
"$W" delegation log "a redo" gpt high redone --project rem >/dev/null
is "and one on a model no open row names is a row of its own" "$today,rem,a redo,gpt,high,redone" "$(tail -n 1 "$LD")"
out="$("$W" delegation 2>&1)"
case "$out" in *"a redo (gpt)"*"2     0      0       2     0"*"test run (sonnet)"*"2     2      0       0     0"*"2 handoff(s)"*) ok "and the table counts each handoff once" ;; *) bad "and the table counts each handoff once" "$out" ;; esac
rm -f "$LD" "$LS"; [ ! -f "$LD.keep" ] || mv "$LD.keep" "$LD"
touch -t 202001010000 "$RD/old-session.tsv"
hook "$T/projects/rem" '{"session_id":"s-2","source":"startup"}' >/dev/null
check "session start sweeps reminder files over a week old" test ! -f "$RD/old-session.tsv"
check "and keeps the others" test -f "$RD/s-1.tsv"
expect "log prints the counts" "2 created, 1 updated" "$W" log demo ingest "Note: smoke" --created wiki/sources/a.md --created wiki/x.md --updated wiki/y.md
check "log writes the handbook's format" bash -c "tail -n 5 '$WIKIS_DIR/demo/log.md' | grep -q '^- conflicts: 0' && grep -q '^## 20[0-9-]* ingest: Note: smoke' '$WIKIS_DIR/demo/log.md'"
refuse "log needs a title for an ingest" "$W" log demo ingest
expect "delegation log records a handoff" "logged: test run" "$W" delegation log "test run" sonnet low ok --project demo
check "and the log is CSV with a header" bash -c "head -n 1 '$WIKIS_DIR/delegation-log.csv' | grep -q '^date,project,kind'"
refuse "delegation log refuses an unknown result" "$W" delegation log x sonnet low maybe
# Gemini's Antigravity conversations go into the digest too, under the project
# their file paths point at.
G="$HOME/.gemini/antigravity/brain/conv1/.system_generated/logs"
mkdir -p "$G" "$T/claude-empty"
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
{
  printf '{"type":"USER_INPUT","created_at":"%s","content":"<USER_REQUEST>\\nAdd a cardio log screen\\n</USER_REQUEST>"}\n' "$now"
  printf '{"type":"PLANNER_RESPONSE","created_at":"%s","tool_calls":[{"name":"write_file","args":{"Path":"%s/projects/web/cardio.ts"}}]}\n' "$now" "$T"
  printf '{"type":"PLANNER_RESPONSE","created_at":"%s","content":"Added the cardio screen."}\n' "$now"
} > "$G/transcript_full.jsonl"
expect "backfill counts Gemini conversations" "1 Gemini conversation(s)" "$W" journal backfill --since 1d --from "$T/claude-empty"
check "and files them under the project their paths point at" grep -q '^### \[demo\].*1 in Gemini' "$WIKIS_DIR/journal/backfill.md"
check "with the user's prompt, the files changed and the last reply" bash -c "grep -q 'Add a cardio log screen' '$WIKIS_DIR/journal/backfill.md' && grep -q 'files changed: cardio.ts' '$WIKIS_DIR/journal/backfill.md' && grep -q 'last reply: Added the cardio screen.' '$WIKIS_DIR/journal/backfill.md'"
rm -rf "$HOME/.gemini"
printf 'digest\n' > "$WIKIS_DIR/journal/backfill.md"
expect "backfill --done removes the digest" "removed:" "$W" journal backfill --done
check "and it's gone" test ! -e "$WIKIS_DIR/journal/backfill.md"
# sync: the failure from real use was a rebase-pull refusing a dirty collection.
git -C "$WIKIS_DIR" config pull.rebase true
git -C "$T/clone2" pull -q --no-rebase --no-edit >/dev/null 2>&1 || true
printf 'x\n' > "$T/clone2/global/raw/2026-01-01-000000-from-a-teammate.md"
git -C "$T/clone2" add -A && git -C "$T/clone2" commit -qm "global: capture" && git -C "$T/clone2" push -q
printf 'waiting\n' > "$WIKIS_DIR/global/raw/2026-01-02-000000-uncommitted.md"
expect "sync commits one wiki and pulls past another wiki's uncommitted note" "synced:" "$W" sync demo -m "demo: smoke sync"
check "the teammate's note came in" test -f "$WIKIS_DIR/global/raw/2026-01-01-000000-from-a-teammate.md"
check "the other wiki's note stayed uncommitted" bash -c "git -C '$WIKIS_DIR' status --short | grep -q 'global/raw/2026-01-02-000000-uncommitted.md'"
rm -f "$WIKIS_DIR/global/raw/2026-01-02-000000-uncommitted.md"
# With no wiki named, sync uses the one start would.
echo "from web" > "$WIKIS_DIR/demo/raw/2026-01-03-000000-from-web.md"
out="$(cd "$T/projects/web" && "$W" sync -m "demo: from web" 2>&1)"
case "$out" in *"sync: demo, the wiki for the repository web"*"synced:"*) ok "sync with no wiki named uses the repository's wiki" ;; *) bad "sync with no wiki named uses the repository's wiki" "$out" ;; esac
check "and committed its note" bash -c "git -C '$WIKIS_DIR' log -1 --format=%s | grep -qx 'demo: from web'"
expect "inside a wiki, it uses that wiki" "sync: demo, the wiki this folder is in" bash -c "cd '$WIKIS_DIR/demo/raw' && '$W' sync -m 'demo: nothing'"
mkdir -p "$T/projects/nowiki" && git -C "$T/projects/nowiki" init -q
out="$(cd "$T/projects/nowiki" && "$W" sync 2>&1)" && bad "a repository no wiki covers is an error" "$out" || case "$out" in *"no wiki covers nowiki. Run:"*"sync <wiki>"*) ok "a repository no wiki covers is an error that says what to run" ;; *) bad "a repository no wiki covers is an error that says what to run" "$out" ;; esac
expect "outside any repository or wiki, it says to name one" "isn't in a repository or a wiki" bash -c "cd '$T' && '$W' sync"
# A trip to the remote is most of a sync's time. With a commit to send and nobody
# else's on the remote, sync pushes and doesn't pull.
git -C "$WIKIS_DIR" add -A >/dev/null 2>&1; git -C "$WIKIS_DIR" commit -qm "smoke: before push first" >/dev/null 2>&1; git -C "$WIKIS_DIR" push -q >/dev/null 2>&1
echo "one trip" > "$WIKIS_DIR/demo/raw/2026-01-05-000000-one-trip.md"
out="$("$W" sync demo -m "demo: one trip" 2>&1)"
case "$out" in *"pulled"*) bad "sync with a commit and a quiet remote pushes without pulling" "$out" ;; *"synced: pushed "*) ok "sync with a commit and a quiet remote pushes without pulling" ;; *) bad "sync with a commit and a quiet remote pushes without pulling" "$out" ;; esac
check "and the remote has the commit" bash -c "git -C '$T/remote.git' log -1 --format=%s | grep -qx 'demo: one trip'"
# A commit made by hand and never pushed goes out too, with nothing new to commit.
echo "by hand" > "$WIKIS_DIR/demo/raw/2026-01-05-000001-by-hand.md"
git -C "$WIKIS_DIR" add -A -- demo && git -C "$WIKIS_DIR" commit -qm "demo: by hand" -- demo
out="$("$W" sync demo 2>&1)"
case "$out" in *"nothing to commit in demo"*"synced: pushed "*) ok "sync pushes a commit left unpushed" ;; *) bad "sync pushes a commit left unpushed" "$out" ;; esac
check "and the remote has that one" bash -c "git -C '$T/remote.git' log -1 --format=%s | grep -qx 'demo: by hand'"
# Nothing to send: sync pulls, so a teammate's note still comes in, and it doesn't
# say "synced: ", which the MCP servers read as "this note was pushed".
git -C "$T/clone2" pull -q --no-rebase --no-edit >/dev/null 2>&1 || true
printf 'x\n' > "$T/clone2/global/raw/2026-01-05-000002-quiet-day.md"
git -C "$T/clone2" add -A && git -C "$T/clone2" commit -qm "global: quiet day" && git -C "$T/clone2" push -q
out="$("$W" sync demo 2>&1)"
case "$out" in *"synced: "*) bad "sync with nothing to send pulls and doesn't say synced" "$out" ;; *"up to date: pulled "*"nothing to push"*) ok "sync with nothing to send pulls and doesn't say synced" ;; *) bad "sync with nothing to send pulls and doesn't say synced" "$out" ;; esac
check "and the teammate's note came in" test -f "$WIKIS_DIR/global/raw/2026-01-05-000002-quiet-day.md"
# The remote moved and there is a commit to send: the push is refused, so pull, then push.
printf 'x\n' > "$T/clone2/global/raw/2026-01-05-000003-moved.md"
git -C "$T/clone2" add -A && git -C "$T/clone2" commit -qm "global: moved" && git -C "$T/clone2" push -q
echo "after" > "$WIKIS_DIR/demo/raw/2026-01-05-000004-after.md"
expect "sync pulls when the remote refuses the push, then pushes" "synced: pulled and pushed" "$W" sync demo -m "demo: after"
check "and both sides' commits are on the remote" bash -c "git -C '$T/remote.git' log -5 --format=%s | grep -qx 'global: moved' && git -C '$T/remote.git' log -5 --format=%s | grep -qx 'demo: after'"
fi

if section "Index and lint"; then
L="$WIKIS_DIR/lintdemo"
"$W" new lintdemo >/dev/null
mkdir -p "$L/wiki/concepts" "$L/wiki/howto"
page() { printf -- '---\ntitle: %s\nsummary: %s\nupdated: 2026-01-01\nverified: %s\n---\n\n%s\n' "$2" "$3" "${5:-2026-10-01}" "${4:-Body.}" > "$L/wiki/$1"; }
page concepts/zebra.md Zebra "Zebras come first in this index, by hand." "See [the howto](../howto/setup.md)."
page concepts/alpha.md Alpha '"Alpha: a summary YAML had to quote."'
page howto/setup.md Setup "How to set up." "Cites global:wiki/nope.md and links [nothing](../concepts/missing.md)."
page concepts/old.md Old "A page nobody has checked in years." "Body." 2020-01-01
printf -- '- [Zebra](wiki/concepts/zebra.md): stale text\n- [Gone](wiki/concepts/gone.md): no such page\n- [Zebra](wiki/concepts/zebra.md): twice\n' > "$T/lines"
printf '# Index\n\n## Concepts\n' > "$L/index.md"; cat "$T/lines" >> "$L/index.md"
refuse "index --check fails when the index is out of step" "$W" index lintdemo --check
out="$("$W" index lintdemo 2>&1)"
case "$out" in *"1 updated, 3 added, 1 removed, 1 duplicate(s)"*) ok "index updates, adds, removes and dedupes" ;; *) bad "index updates, adds, removes and dedupes" "$out" ;; esac
case "$out" in *"was: stale text"*) ok "index shows the text it replaced" ;; *) bad "index shows the text it replaced" "$out" ;; esac
check "the hand-made order is kept: zebra stays first" bash -c "grep '^- ' '$L/index.md' | head -n 1 | grep -q zebra.md"
check "a new how-to gets its own heading" grep -q '^## How-to' "$L/index.md"
check "YAML quotes don't reach the index" bash -c "grep -q '): Alpha: a summary YAML had to quote.\$' '$L/index.md'"
expect "a second run changes nothing" "nothing to change" "$W" index lintdemo
printf 'Captured: 2026-01-01\n\nWaiting.\n' > "$L/raw/2026-01-01-000000-waiting.md"
out="$("$W" lint lintdemo 2>&1)"
for want in "broken link" "broken citation" "not verified in 180 days" "notes waiting"; do
  case "$out" in *"$want"*) ok "lint reports: $want" ;; *) bad "lint reports: $want" "$out" ;; esac
done
printf -- '---\ntitle: Cited\nsummary: Cites raw files.\nsources: [raw/2026-01-01-000000-waiting.md, raw/2026-01-01-000001-gone.md]\nupdated: 2026-01-01\nverified: 2026-10-01\n---\n\nBody.\n' > "$L/wiki/concepts/cited.md"
out="$("$W" lint lintdemo 2>&1)"
case "$out" in *"missing source file"*"cited.md -> raw/2026-01-01-000001-gone.md"*) ok "lint reports a sources: entry with no raw file" ;; *) bad "lint reports a sources: entry with no raw file" "$out" ;; esac
case "$out" in *"-> raw/2026-01-01-000000-waiting.md"*) bad "and only the missing one" "$out" ;; *) ok "and only the missing one" ;; esac
# Obsidian rewrites a page's lists one item a line when a property is edited there.
# Read a line at a time, such a page had no sources: lint stopped checking them, and
# the notes it compiled counted as waiting again.
printf -- '---\ntitle: Cited\nsummary: Cites raw files.\ntags:\n  - one\n  - two\nsources:\n  - raw/2026-01-01-000000-waiting.md\n  - "raw/2026-01-01-000001-gone.md"\nupdated: 2026-01-01\nverified: 2026-10-01\n---\n\nBody, with [[Zebra]], [[zebra|a name]] and `[[ -f x ]]`.\n\n```\n[[ -n "$in_a_fence" ]]\n```\n- raw/2026-01-01-000002-body.md\n' > "$L/wiki/concepts/cited.md"
out="$("$W" lint lintdemo 2>&1)"
case "$out" in *"missing source file"*"cited.md -> raw/2026-01-01-000001-gone.md"*) ok "lint reads sources: written one a line, as Obsidian rewrites it" ;; *) bad "lint reads sources: written one a line, as Obsidian rewrites it" "$out" ;; esac
case "$out" in *"-> raw/2026-01-01-000000-waiting.md"* | *"frontmatter missing"*"cited.md"*) bad "and finds nothing else wrong with that frontmatter" "$out" ;; *) ok "and finds nothing else wrong with that frontmatter" ;; esac
case "$out" in *"notes waiting"*) bad "and the note such a page names is compiled, to lint" "$out" ;; *) ok "and the note such a page names is compiled, to lint" ;; esac
expect "and to pending, in the Bash" "nothing waiting" env LLM_WIKI_NO_GO=1 "$W" pending lintdemo
expect "and with whatever helper there is" "nothing waiting" "$W" pending lintdemo
printf 'Captured: 2026-01-01\n\nA line in a page, not in its sources.\n' > "$L/raw/2026-01-01-000002-body.md"
expect "a list item below the sources is not one of them" "000002-body" env LLM_WIKI_NO_GO=1 "$W" pending lintdemo
rm "$L/raw/2026-01-01-000002-body.md"
case "$out" in *"wikilink"*"cited.md -> [[Zebra]]"*"cited.md -> [[zebra]]"*) ok "lint reports wikilinks, which it can't follow" ;; *) bad "lint reports wikilinks, which it can't follow" "$out" ;; esac
case "$out" in *"-f x"* | *"in_a_fence"*) bad "and not double brackets in code" "$out" ;; *) ok "and not double brackets in code" ;; esac
printf -- '---\ntitle: Cited\nsummary:\nupdated: 2026-01-01\nverified: 2026-10-01\n---\n\nBody.\n' > "$L/wiki/concepts/cited.md"
expect "an empty key is still a missing one" "frontmatter missing summary" "$W" lint lintdemo
rm "$L/wiki/concepts/cited.md"
check "the template's own ignore file covers Obsidian" grep -qxF .obsidian/ "$L/.gitignore"
check "and lint leaves a note the user made as theirs" grep -q 'no log entry names' "$REPO/template/rules/lint.md"
# wiki obsidian, on a collection of its own.
OB="$T/ob"
WIKIS_DIR="$OB" "$W" new one >/dev/null 2>&1
printf '.DS_Store\n' > "$OB/.gitignore"
ob() { WIKIS_DIR="$OB" "$W" "$@"; }
out="$(ob upgrade --all 2>&1)"
case "$out" in *".gitignore: added .obsidian/"*".gitignore: added .trash/"*) ok "upgrade adds Obsidian's folders to a collection's ignore file" ;; *) bad "upgrade adds Obsidian's folders to a collection's ignore file" "$out" ;; esac
lacks "and only once" ".gitignore: added" ob upgrade --all
expect "obsidian writes the vault's starter settings" "wrote: " ob obsidian --no-open
check "and they are JSON, with markdown links" python3 -c "import json, sys; d = json.load(open(sys.argv[1])); assert d['useMarkdownLinks'] is True and d['newLinkFormat'] == 'relative' and d['userIgnoreFilters']" "$OB/.obsidian/app.json"
expect "a second run says they are there" "settings: already in" ob obsidian --no-open
out="$(ob obsidian 2>&1)"
case "$out" in *"Open it once by hand"*) ok "a vault Obsidian doesn't know yet is opened by hand, the first time" ;; *) bad "a vault Obsidian doesn't know yet is opened by hand, the first time" "$out" ;; esac
printf '{}\n' > "$OB/.obsidian/app.json"
expect "the empty file Obsidian makes is replaced" "wrote: " ob obsidian --no-open
printf '{"vimMode": true}\n' > "$OB/.obsidian/app.json"
expect "settings of your own are kept, and the recommended ones printed" "useMarkdownLinks" ob obsidian --no-open
check "and the file is as it was" grep -qx '{"vimMode": true}' "$OB/.obsidian/app.json"
refuse "obsidian refuses an option it doesn't know" ob obsidian --open
lacks "Obsidian's folder is not a wiki, to status" ".obsidian" ob status
lacks "nor with the Bash alone" ".obsidian" env LLM_WIKI_NO_GO=1 WIKIS_DIR="$OB" "$W" status
lacks "with no Obsidian on the machine, setup has nothing to ask" "obsidian" ob setup --list
mkdir -p "$HOME/Library/Application Support/obsidian" "${XDG_CONFIG_HOME:-$HOME/.config}/obsidian"
expect "where Obsidian has run, setup --new would ask" "theirs  <- new" bash -c "WIKIS_DIR='$OB' '$W' setup --list | grep '^obsidian'"
rm "$OB/.obsidian/app.json"
expect "setup obsidian writes the settings on a yes" "wrote: " bash -c "printf 'y\n' | WIKIS_DIR='$OB' LLM_WIKI_TEST_TTY=1 '$W' setup obsidian"
out="$(ob setup --list | grep '^obsidian')"
case "$out" in *"ours"*) case "$out" in *"<- new"*) bad "and it isn't asked again" "$out" ;; *) ok "and it isn't asked again" ;; esac ;; *) bad "and it isn't asked again" "$out" ;; esac
rm -rf "$HOME/Library/Application Support/obsidian" "${XDG_CONFIG_HOME:-$HOME/.config}/obsidian"
printf '\n- [Ghost](wiki/concepts/ghost.md): gone\n' >> "$L/index.md"
expect "lint reports an index line with no page" "index line with no page" "$W" lint lintdemo
expect "lint --all covers every wiki" "== global" "$W" lint --all
refuse "lint needs a wiki or --all" "$W" lint
fi

if section "Setup fit"; then
expect "which suggests a wiki with a shared word" "Close matches: demo" "$W" which demo-api
expect "and the cover fix" "cover <wiki> demo-api" "$W" which demo-api
refuse "which still exits 1 when nothing covers it" "$W" which demo-api
expect "an https remote is explained" "signs in with a password or token" "$W" __push-advice "fatal: could not read Username for 'https://gitlab.com'" "https://gitlab.com/kn/w.git"
expect "and the SSH form names the right host" "git@gitlab.com:" "$W" __push-advice "fatal: could not read Username" "https://gitlab.com/kn/w.git"
expect "a refused key is explained" "didn't accept the key" "$W" __push-advice "git@gitlab.com: Permission denied (publickey)." "git@gitlab.com:kn/w.git"
expect "a blocked port is explained" "port 443" "$W" __push-advice "ssh: connect to host gitlab.com port 22: Operation timed out" "git@gitlab.com:kn/w.git"
expect "a missing repository is explained" "isn't at that address" "$W" __push-advice "fatal: repository not found" "git@gitlab.com:kn/w.git"
out="$(hook "$T/projects/web" | context 2>&1)"
case "$out" in *"means $T/data/bin/wiki"* | *"means ~/"*"/bin/wiki"*) ok "the hook gives sessions the stable wiki command" ;; *) bad "the hook gives sessions the stable wiki command" "$out" ;; esac
expect "the report defers to the user's reply style" "usual reply style" "$W" report
check "save writes journal lines" grep -q 'journal note' "$REPO/commands/save.md"
fi

if section "Harvest Claude Code memory"; then
M="$HOME/.claude/projects/-x-web"
mkdir -p "$M/memory" "$HOME/.claude/projects/-x-unknown/memory"
printf '{"type":"user","cwd":"%s","sessionId":"h1"}\n' "$T/projects/web" > "$M/h1.jsonl"
printf '# Memory index\n' > "$M/memory/MEMORY.md"
printf -- '---\nname: no-push\nmetadata:\n  type: feedback\n---\n\nNever push without asking.\n' > "$M/memory/no-push.md"
printf -- '---\nname: deploy-host\nmetadata:\n  type: reference\n---\n\nDeploys go through the canary host.\n' > "$M/memory/deploy-host.md"
printf -- '---\nname: stray\nmetadata:\n  type: project\n---\n\nA fact from a folder with no project.\n' > "$HOME/.claude/projects/-x-unknown/memory/stray.md"
rm -f "$HOME/.config/llm-wiki/tips"
expect "the harvest tip counts memory notes" "3 note(s) of its own memory" "$W" tips
expect "a dry run shows where each note would go" "deploy-host.md -> demo (reference, from demo)" "$W" harvest --dry-run
check "a dry run copies nothing" bash -c "! ls '$WIKIS_DIR'/*/raw/ | grep -q harvest"
out="$("$W" harvest 2>&1)"
case "$out" in *"3 note(s) copied"*) ok "harvest copies the notes" ;; *) bad "harvest copies the notes" "$out" ;; esac
check "a correction goes to the shared wiki" bash -c "grep -l 'Never push without asking' '$WIKIS_DIR'/global/raw/*-harvest-*no-push.md"
check "a reference goes to the project's wiki" bash -c "grep -l 'canary host' '$WIKIS_DIR'/demo/raw/*-harvest-*deploy-host.md"
check "a note from an unknown folder goes to the shared wiki" bash -c "ls '$WIKIS_DIR'/global/raw/ | grep -q 'harvest-[0-9]*-stray.md'"
check "MEMORY.md, the index, is left out" bash -c "! ls '$WIKIS_DIR'/*/raw/ | grep -qi 'harvest-[0-9]*-memory.md'"
check "each wiki gets a manifest naming the source project" bash -c "grep -q 'saved while working in demo' '$WIKIS_DIR'/global/raw/*-harvest-00-manifest.md"
check "the memory notes are untouched" grep -q 'Never push without asking' "$M/memory/no-push.md"
expect "harvesting again copies nothing new" "skipped 3 already harvested" "$W" harvest
lacks "after a harvest, its tip goes away" "of its own memory" "$W" tips
fi

if section "Setup fixes"; then
check "setup --new would ask about tab completion" bash -c "SHELL=/bin/zsh '$W' setup --list | grep -q '^completion  *off  <- new'"
printf '.DS_Store\n.compile-lock\njournal/\ndelegation.md\ndelegation-log.csv\nstats.csv\n' > "$WIKIS_DIR/.gitignore"
git -C "$WIKIS_DIR" add .gitignore >/dev/null 2>&1 && git -C "$WIKIS_DIR" commit -qm "old ignores" -- .gitignore >/dev/null 2>&1
expect "with no wiki behind, upgrade still commits collection changes" 'Committed the upgrade as "wikis: update collection files"' "$W" upgrade --all
check "and the ignore rules are anchored" grep -qx '/delegation.md' "$WIKIS_DIR/.gitignore"
if [ "$(id -u)" != 0 ] && [ ! -e "$HOME/.claude/CLAUDE.md" ]; then
  mkdir -p "$HOME/.claude" && printf 'x\n' > "$HOME/.claude/CLAUDE.md" && chmod 000 "$HOME/.claude/CLAUDE.md"
  out="$("$W" setup --list 2>&1)"
  case "$out" in *"claude  "*"unknown, can't read ~/.claude/CLAUDE.md"*) ok "setup --list says when it can't read CLAUDE.md" ;; *) bad "setup --list says when it can't read CLAUDE.md" "$out" ;; esac
  case "$out" in *"ermission denied"*) bad "without a raw error" "$out" ;; *) ok "without a raw error" ;; esac
  chmod 644 "$HOME/.claude/CLAUDE.md" && rm -f "$HOME/.claude/CLAUDE.md"
else
  skipped "a CLAUDE.md that can't be read"
fi
fi

if section "Stats"; then
rm -f "$WIKIS_DIR/stats.csv"
expect "stats with no log says so" "No lookups logged yet" "$W" stats
check "stats.csv is git-ignored" git -C "$WIKIS_DIR" check-ignore -q stats.csv
today="$(date -u +%Y-%m-%d)"
printf 'date,wiki,result\n%s,demo,hit\n%s,demo,miss\n%s,global,hit\n2000-01-01,demo,miss\n' "$today" "$today" "$today" > "$WIKIS_DIR/stats.csv"
expect "stats computes a wiki's hit rate" "50%" "$W" stats
expect "stats totals every wiki" "67%" "$W" stats
lacks "stats leaves out lookups before the range" "25%" "$W" stats
expect "stats says a page read logs itself, and misses were by hand" "logs a hit, once per wiki per session" "$W" stats
"$W" find zzznothingmatches >/dev/null
check "find logs a search that found nothing, with its word" bash -c "tail -n 1 '$WIKIS_DIR/stats.csv' | grep -q ',global,search-none,zzznothingmatches$'"
"$W" find canary >/dev/null
check "and one that found something" bash -c "tail -n 1 '$WIKIS_DIR/stats.csv' | grep -q ',search-found,canary$'"
expect "stats lists the words that found nothing" "1 found nothing: zzznothingmatches" "$W" stats
expect "searches don't change the hit rate" "67%" "$W" stats
# Page reads come from transcripts, so they don't depend on a session logging anything.
TP="$HOME/.claude/projects/usage-test"; mkdir -p "$TP"
ts="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
printf '{"timestamp":"%s","sessionId":"s1","cwd":"%s","message":{"id":"m1","usage":{"input_tokens":5,"output_tokens":5},"content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"%s/demo/wiki/alpha.md"}},{"type":"tool_use","id":"t2","name":"Bash","input":{"command":"cat %s/demo/wiki/beta.md"}},{"type":"tool_use","id":"t3","name":"Edit","input":{"file_path":"%s/global/wiki/x.md"}},{"type":"tool_use","id":"t4","name":"Bash","input":{"command":"grep x %s/*/wiki/y.md"}}]}}\n' "$ts" "$HOME" "$WIKIS_DIR" "$WIKIS_DIR" "$WIKIS_DIR" "$WIKIS_DIR" > "$TP/s1.jsonl"
out="$("$W" report 2>&1)"
case "$out" in *"## Wiki use"*"- demo: pages opened in 1 session(s)"*"Searches: 2, of which 1 found nothing: zzznothingmatches"*"Most sessions do not log"*) ok "the report counts sessions that opened pages, once each, and searches" ;; *) bad "the report counts sessions that opened pages, once each, and searches" "$out" ;; esac
case "$out" in *"answered"*"%"*) bad "and gives no hit rate" "$out" ;; *) ok "and gives no hit rate" ;; esac
case "$out" in *"- global: pages opened"*) bad "an edit isn't opening a page" "$out" ;; *) ok "an edit isn't opening a page" ;; esac
case "$out" in *"- *: pages opened"*) bad "a glob in a command isn't a wiki" "$out" ;; *) ok "a glob in a command isn't a wiki" ;; esac
rm -rf "$TP"
fi

if section "Plugin updates reach the wiki command"; then
# Two installed versions side by side, as Claude Code leaves them after an update.
# v2's template says v98, so status shows which version ran.
C1="$HOME/.claude/plugins/cache/mk/llm-wiki/v1"
C2="$HOME/.claude/plugins/cache/mk/llm-wiki/v2"
mkdir -p "$C1" "$C2"
(cd "$REPO" && tar cf - --exclude .git --exclude tests .) | (cd "$C1" && tar xf -)
(cd "$REPO" && tar cf - --exclude .git --exclude tests .) | (cd "$C2" && tar xf -)
set_version "$C2/template/AGENTS.md" 98
CLAUDE_PLUGIN_ROOT="$C1" CLAUDE_PLUGIN_DATA="$T/pdata" CLAUDE_PROJECT_DIR="$T" bash "$C1/hooks/session-start.sh" </dev/null >/dev/null
check "the hook writes the command for an installed plugin" test -x "$T/pdata/bin/wiki"
lacks "with no install record, the command runs its own version" "v98" "$T/pdata/bin/wiki" status
printf '{"version":2,"plugins":{"llm-wiki@mk":[{"scope":"user","installPath":"%s","version":"v2"}]}}\n' "$C2" > "$HOME/.claude/plugins/installed_plugins.json"
expect "after an update, the command runs the new version at once" "behind template v98" "$T/pdata/bin/wiki" status
# wiki link puts the command on the PATH. Each case gets a PATH without the real ~/.local/bin.
base_path="/usr/bin:/bin:/usr/sbin:/sbin"
mkdir -p "$HOME/.local/bin"
expect "link uses a writable folder already on the PATH" "linked ~/.local/bin/wiki" env PATH="$HOME/.local/bin:$base_path" "$T/pdata/bin/wiki" link
check "the linked wiki is the plugin's command" test "$HOME/.local/bin/wiki" -ef "$T/pdata/bin/wiki"
expect "link again says it's done" "already a command" env PATH="$HOME/.local/bin:$base_path" "$T/pdata/bin/wiki" link
rm -f "$HOME/.local/bin/wiki"
expect "without one, link asks before touching the shell profile" "link --yes" env PATH="$base_path" SHELL=/bin/zsh "$T/pdata/bin/wiki" link </dev/null
check "and leaves the profile alone" test ! -e "$HOME/.zshrc"
expect "link --yes adds ~/.local/bin to the profile" "added it to your PATH" env PATH="$base_path" SHELL=/bin/zsh "$T/pdata/bin/wiki" link --yes
check "the profile line is there" grep -qF 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.zshrc"
mkdir -p "$T/otherbin" && printf '#!/bin/sh\n' > "$T/otherbin/wiki" && chmod +x "$T/otherbin/wiki"
refuse "link leaves someone else's wiki command alone" env PATH="$T/otherbin:$base_path" "$T/pdata/bin/wiki" link
printf '{"extraKnownMarketplaces":{"mk":{"source":{"source":"github","repo":"x/y"}}}}\n' > "$HOME/.claude/settings.json"
expect "status warns when auto-update is off" "auto-update is off" "$T/pdata/bin/wiki" status
printf '{"extraKnownMarketplaces":{"mk":{"source":{"source":"github","repo":"x/y"},"autoUpdate":true}}}\n' > "$HOME/.claude/settings.json"
lacks "and is quiet once it's on" "auto-update is off" "$T/pdata/bin/wiki" status
rm -f "$HOME/.claude/settings.json" "$HOME/.zshrc"
rm -rf "$C1"
expect "it still works once the old version is deleted" "behind template v98" "$T/pdata/bin/wiki" status
printf '{"version":2,"plugins":{"llm-wiki@mk":[{"scope":"user","installPath":"%s/gone"}]}}\n' "$HOME" > "$HOME/.claude/plugins/installed_plugins.json"
expect "a record pointing nowhere gives a clear error" "can't find the llm-wiki plugin" "$T/pdata/bin/wiki" status
check "a plugin run from a clone never looks up a version" grep -q 'key=""' "$T/data/bin/wiki"
rm -f "$HOME/.claude/plugins/installed_plugins.json"
fi

if section "Journal and standup"; then
expect "journal note writes an entry" "journal:" "$W" journal note demo "smoke test entry"
refuse "journal note refuses a future day" "$W" journal note --day 2999-01-01 demo "too early"
expect "standup includes the journal entry" "smoke test entry" "$W" standup --since 2d
refuse "journal set validates values" "$W" journal set format weird
C="$T/code/busy"
mkdir -p "$C" && git -C "$C" init -q
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do git -C "$C" commit -q --allow-empty -m "busy commit $i"; done
"$W" journal set code_dirs "$T/code" >/dev/null
expect "standup caps commits per repository" "(7 earlier commit(s) not listed)" "$W" standup --since 2d --max 5
expect "the cap keeps the newest commit" "busy commit 12" "$W" standup --since 2d --max 5
lacks "the cap drops the older ones" "busy commit 7" "$W" standup --since 2d --max 5
expect "detailed reports list every commit" "busy commit 1" "$W" standup --since 2d --max 5 --format detailed
# A config include git can't read fails every repository, as an agent's sandbox did.
printf 'blocked\n' > "$T/gitconfig-blocked" && chmod 000 "$T/gitconfig-blocked"
printf '[include]\n\tpath = %s\n' "$T/gitconfig-blocked" > "$T/gitconfig-bad"
out="$(GIT_CONFIG_GLOBAL="$T/gitconfig-bad" "$W" standup --since 2d 2>&1)"
case "$out" in *"1 of 1 repo(s) couldn't be read"*"git said: "*"sandbox"*) ok "standup says which repositories git couldn't read, not just None found" ;; *) bad "standup says which repositories git couldn't read, not just None found" "$out" ;; esac
chmod 600 "$T/gitconfig-blocked"; rm -f "$T/gitconfig-blocked" "$T/gitconfig-bad"
mkdir -p "$T/code-empty"
"$W" journal set code_dirs "$T/code-empty" >/dev/null
expect "and says when it found no repositories at all" "No git repositories found under $T/code-empty" "$W" standup --since 2d
"$W" journal set code_dirs "$T/code" >/dev/null
# The compiled helper, against the Bash, on a fixture with fixed dates. The weekly
# report's section builds it; a part of the suite without that section builds it here.
[ -x "$T/bin/llm-wiki" ] || ! command -v go >/dev/null 2>&1 || build_helper >/dev/null 2>&1
if [ -x "$T/bin/llm-wiki" ]; then
  S="$T/code-s"; d1="2026-01-15T12:00:00"
  scommit() { GIT_AUTHOR_DATE="$d1" GIT_COMMITTER_DATE="$d1" git -C "$1" -c user.email="${3:-}" commit -q --allow-empty -m "$2"; }
  mkdir -p "$S/plain" "$S/remoted" "$S/branch" "$S/unborn" "$S/noemail" "$S/other" "$S/up" "$S/deep/er/still" "$S/WorkTree"
  for r in plain remoted branch unborn noemail other WorkTree deep/er/still; do git -C "$S/$r" init -q -b main; done
  me="$(git -C "$S/plain" config user.email || echo smoke@example.com)"
  for i in 1 2 3 4; do scommit "$S/plain" "plain commit $i" "$me"; done
  scommit "$S/remoted" "remoted commit" "$me"; git -C "$S/remoted" remote add origin 'git@host:me/named-remote.git/'
  printf 'x\n' > "$S/remoted/dirty.txt"; printf 'x\n' > "$S/remoted/dirty2.txt"
  git -C "$S/branch" checkout -q -b feature; scommit "$S/branch" "branch commit: colons, 100% and \$HOME" "$me"
  scommit "$S/noemail" "no email" "$me"; git -C "$S/noemail" config user.email ""
  scommit "$S/other" "someone else's" "else@example.com"
  scommit "$S/WorkTree" "capital name" "$me"
  git clone -q "$S/plain" "$S/up/clone"; scommit "$S/up/clone" "not pushed" "$me"
  "$W" journal set code_dirs "$S" >/dev/null
  J="$WIKIS_DIR/journal/2026-01-15.md"; mkdir -p "$WIKIS_DIR/journal"
  printf '# 2026-01-15\n\n- 10:00 [plain] a day of work\nnot a bullet\n- 11:00 [branch] more [work] here\n- no brackets at all\n-no space\n' > "$J"
  Z="$WIKIS_DIR/Zeta"; mkdir -p "$Z/raw" "$Z/wiki/sub" "$WIKIS_DIR/notawiki/raw" "$WIKIS_DIR/.hidden/raw"
  : > "$Z/AGENTS.md"; : > "$Z/index.md"
  printf '# A title: with colon\r\n\nbody\n' > "$Z/raw/2026-01-15-120000-titled.md"
  printf 'no heading\n' > "$Z/raw/2026-01-15-120001-untitled.md"
  printf '# \n\n# second\n' > "$Z/raw/2026-01-15-120002-empty-title.md"
  printf '# no extension\n' > "$Z/raw/2026-01-15-120003-noext"
  printf '# day only\n' > "$Z/raw/2026-01-16.md"
  printf '# day and word\n' > "$Z/raw/2026-01-16-word.v2.md"
  printf '# too old\n' > "$Z/raw/2025-01-15-120000-old.md"
  printf '# not dated\n' > "$Z/raw/notes.md"
  mkdir "$Z/raw/2026-01-15-120004-folder"
  printf '# Log\n\n## 2026-01-15 ingest:   spaced\tout  words  \n## 2026-01-16 lint\n##  2026-01-15 two spaces\n## 2025-01-15 too old\n## 2026-01-15\ntext\n' > "$Z/log.md"
  printf '> **Check:** b one\n> **Conflict:** b two\n' > "$Z/wiki/b.md"
  printf '> **Check:** a-b one\n' > "$Z/wiki/a-b.md"
  printf '```\n> **Check:** fenced\n```\n> **Check:** a one\n> **Other:** no\n' > "$Z/wiki/a.md"
  printf '> **Check:** sub one\n> **Check:** sub two\n> **Check:** sub three\n' > "$Z/wiki/sub/c.md"
  printf '> **Check:** a.b one\n' > "$Z/wiki/a.b.md"
  printf '# hidden\n' > "$WIKIS_DIR/.hidden/raw/2026-01-15-120000-x.md"; : > "$WIKIS_DIR/.hidden/AGENTS.md"; : > "$WIKIS_DIR/.hidden/index.md"
  printf '# not a wiki\n' > "$WIKIS_DIR/notawiki/raw/2026-01-15-120000-x.md"
  SP=(--since 2026-01-10 --until 2026-01-20)
  sbash="$(LLM_WIKI_NO_GO=1 "$W" standup "${SP[@]}" 2>&1)"
  sgo="$(LLM_WIKI_GO="$T/bin/llm-wiki" "$W" standup "${SP[@]}" 2>&1)"
  # What the Bash printed for this fixture.
  case "$sbash" in *"### named-remote"*"(2 of 9 repo(s) couldn't be read"*"(1 repo(s) skipped: no user.email"*"- 2026-01-15 10:00 [plain] a day of work"*"- 2026-01-15 no brackets at all"*"- 2026-01-15-120000-titled: A title: with colon"*"- 2026-01-15-120001-untitled: (no title)"*"- 2026-01-15-120002-empty-title: (no title)"*"- 2026-01-15-120003-noext: no extension"*"- 2026-01-16-word.v2: day and word"*"- 2026-01-16: day only"*"- Zeta: 2026-01-15 ingest: spaced out words"*"- Zeta: 2026-01-16 lint"*"- named-remote: branch main, 2 uncommitted file(s), 0 unpushed commit(s)"*"- Zeta: **Check:** a-b one"*"- Zeta: **Check:** a.b one"*"- Zeta: **Check:** a one"*"- Zeta: **Check:** b one"*"- Zeta: **Conflict:** b two"*"Totals: "*) ok "the Bash reports the standup fixture's cases" ;; *) bad "the Bash reports the standup fixture's cases" "$sbash" ;; esac
  case "$sbash" in *"sub one"*) bad "only a wiki's first five callouts are listed, by file" "$sbash" ;; *) ok "only a wiki's first five callouts are listed, by file" ;; esac
  case "$sbash" in *"too old"*|*"fenced"*|*"not dated"*|*"not a wiki"*|*"# hidden"*|*"someone else"*|*"not a bullet"*|*"no space"*|*"two spaces"*) bad "and what the range or the rules leave out stays out" "$sbash" ;; *) ok "and what the range or the rules leave out stays out" ;; esac
  [ "$sbash" = "$sgo" ] && ok "the Go helper prints the same standup as the Bash" || bad "the Go helper prints the same standup as the Bash" "$(diff <(printf '%s\n' "$sbash") <(printf '%s\n' "$sgo"))"
  ssame() {
    local name="$1" a g; shift
    a="$(LLM_WIKI_NO_GO=1 "$W" standup "$@" 2>&1)"; g="$(LLM_WIKI_GO="$T/bin/llm-wiki" "$W" standup "$@" 2>&1)"
    [ "$a" = "$g" ] && ok "and with $name" || bad "and with $name" "$(diff <(printf '%s\n' "$a") <(printf '%s\n' "$g"))"
  }
  ssame "--day" --day 2026-01-15
  # macOS's date took the seconds from the clock, so the day ran a few seconds into the next.
  out="$(LLM_WIKI_NO_GO=1 "$W" standup --day 2026-01-15 2>&1)"
  case "$out" in *"- 2026-01-15-120000-titled"*"2026-01-16: day only"*) bad "and a day ends at its last second, whatever second it is now" "$out" ;; *"- 2026-01-15-120000-titled"*) ok "and a day ends at its last second, whatever second it is now" ;; *) bad "and a day ends at its last second, whatever second it is now" "$out" ;; esac
  ssame "--since 2d" --since 2d
  ssame "--since lastweek" --since lastweek
  ssame "--format summary" "${SP[@]}" --format summary
  ssame "--format detailed and --max" "${SP[@]}" --format detailed --max 1
  ssame "--max 2" "${SP[@]}" --max 2
  ssame "--max 0" "${SP[@]}" --max 0
  ssame "--max 010, which is ten" "${SP[@]}" --max 010
  ssame "--only" "${SP[@]}" --only plain
  ssame "--only and a star" "${SP[@]}" --only 'b*'
  ssame "--only and a question mark" "${SP[@]}" --only 'pl?in'
  ssame "--only matching a journal project" "${SP[@]}" --only '- no*'
  ssame "--only and a bracket, for the Bash" "${SP[@]}" --only '[bp]*'
  ssame "--exclude" "${SP[@]}" --exclude plain
  ssame "--exclude twice, with spaces and an empty item" "${SP[@]}" --exclude ' pl* ,,Z?ta' --exclude 'named-*'
  ssame "--exclude and a star across a slash" "${SP[@]}" --exclude '*/*'
  ssame "--exclude and a backslash, for the Bash" "${SP[@]}" --exclude 'pl\ain'
  ssame "--only and --exclude" "${SP[@]}" --only '*e*' --exclude 'named*'
  "$W" journal set authors ' else@example.com , nobody ' >/dev/null
  ssame "authors set" "${SP[@]}"
  "$W" journal set authors "" >/dev/null
  "$W" journal set exclude 'Z*' >/dev/null
  ssame "journal exclude set" "${SP[@]}"
  "$W" journal set exclude "" >/dev/null
  "$W" journal set code_dirs "$T/code-empty" >/dev/null
  ssame "no repositories at all" "${SP[@]}"
  "$W" journal set code_dirs "$S:$WIKIS_DIR" >/dev/null
  git -C "$Z" init -q 2>/dev/null
  ssame "a repository under the wikis, left out" "${SP[@]}"
  rm -rf "$Z/.git"
  "$W" journal set code_dirs "$S" >/dev/null
  # The same order whatever the locale: capitals before lowercase, in glob and sort alike.
  if locale -a 2>/dev/null | grep -qi '^en_US.utf-\?8$'; then
    ulocale="$(locale -a | grep -i '^en_US.utf-\?8$' | head -n 1)"
    a="$(LC_ALL="$ulocale" LLM_WIKI_NO_GO=1 "$W" standup "${SP[@]}" 2>&1)"
    case "$a" in *"### Zeta"*"### demo"*) bad "wikis keep byte order under $ulocale" "$a" ;; *) ok "wikis keep byte order under $ulocale" ;; esac
    [ "$a" = "$(LC_ALL="$ulocale" LLM_WIKI_GO="$T/bin/llm-wiki" "$W" standup "${SP[@]}" 2>&1)" ] && ok "and the helper agrees there" || bad "and the helper agrees there"
  else
    skipped "standup under en_US.UTF-8 (no such locale here)"
  fi
  # Proof the helper ran: a wrapper leaves a mark, and it isn't asked twice.
  printf '#!/bin/sh\n[ "$1" = protocol ] || echo "$1" >> "%s"\nexec "%s" "$@"\n' "$T/helper-ran" "$T/bin/llm-wiki" > "$T/bin/spy-helper"
  chmod +x "$T/bin/spy-helper"; : > "$T/helper-ran"
  LLM_WIKI_NO_GO="" LLM_WIKI_GO="$T/bin/spy-helper" "$W" standup "${SP[@]}" >/dev/null 2>&1
  [ "$(grep -c '^standup-activity$' "$T/helper-ran")" = 1 ] && ok "wiki.sh runs the helper for the standup" || bad "wiki.sh runs the helper for the standup" "$(cat "$T/helper-ran")"
  [ "$(LLM_WIKI_GO="$T/bin/broken-helper" "$W" standup "${SP[@]}" 2>&1)" = "$sbash" ] && ok "a helper that fails falls back to the Bash for the standup too" || bad "a helper that fails falls back to the Bash for the standup too"
  [ "$(LLM_WIKI_GO="$T/bin/stale-helper" "$W" standup "${SP[@]}" 2>&1)" = "$sbash" ] && ok "and one built for another protocol is passed over" || bad "and one built for another protocol is passed over"
  out="$(LLM_WIKI_GO="$T/bin/llm-wiki" "$W" standup "${SP[@]}" --save 2>&1)"
  case "$out" in *"Totals: "*"saved: "*) ok "--save still saves what the helper printed" ;; *) bad "--save still saves what the helper printed" "$out" ;; esac
  rm -f "$WIKIS_DIR/journal/"*-activity.md
  # A file grep would call binary: the helper refuses it, and the Bash answers.
  printf -- '- [plain] bin\000ary\n' >> "$J"
  if "$T/bin/llm-wiki" standup-activity --wikis "$WIKIS_DIR" --journal "$WIKIS_DIR/journal" --start-date 2026-01-15 --end-date 2026-01-15 --start-utc 20260115000000 --end-utc 20260116000000 --max 0 >/dev/null 2>&1; then
    bad "the helper leaves a binary journal to the Bash"
  else
    ok "the helper leaves a binary journal to the Bash"
  fi
  ssame "a binary journal" "${SP[@]}"
  rm -f "$J"; rm -rf "$Z" "$WIKIS_DIR/notawiki" "$WIKIS_DIR/.hidden"
  "$W" journal set code_dirs "$T/code" >/dev/null
else
  skipped "the Go helper against the Bash for the standup (go isn't installed)"
fi
fi

if section "Commit distance"; then
R="$T/code/demo"
mkdir -p "$R" && git -C "$R" init -q && git -C "$R" commit -q --allow-empty -m first
old="$(git -C "$R" rev-parse --short HEAD)"
for i in $(seq 1 55); do git -C "$R" commit -q --allow-empty -m "c$i"; done
new="$(git -C "$R" rev-parse --short HEAD)"
fm() { printf -- '---\ntitle: %s\nsummary: x\nupdated: 2026-10-29\nverified: %s\ncommit: %s\n---\n\nBody.\n' "$1" "$(date -u +%Y-%m-%d)" "$2" > "$WIKIS_DIR/demo/wiki/$1.md"; }
fm far "demo@$old"; fm near "demo@$new"; fm gone "demo@deadbee"; fm bare "$old"
out="$("$W" stale 90 2>&1)"
case "$out" in *"far.md  (55 commits behind demo)"*) ok "stale counts commits a page is behind its repository" ;; *) bad "stale counts commits a page is behind its repository" "$out" ;; esac
case "$out" in *"near.md"*) bad "a page at the repository's HEAD isn't stale" "$out" ;; *) ok "a page at the repository's HEAD isn't stale" ;; esac
case "$out" in *"gone.md  (commit deadbee not found in demo)"*) ok "stale reports a commit the repository doesn't have" ;; *) bad "stale reports a commit the repository doesn't have" "$out" ;; esac
case "$out" in *"bare.md"*"write repo@hash"*) ok "a bare commit in a wiki over several repositories is flagged" ;; *) bad "a bare commit in a wiki over several repositories is flagged" "$out" ;; esac
expect "lint reports a commit far behind" "commit far behind its repository" "$W" lint demo
git -C "$R" remote add origin "git@example.com:me/renamed.git"
fm far "renamed@$old"
expect "a clone is found by its remote's name too, not only its folder" "far.md  (55 commits behind renamed)" "$W" stale 90
fm far "demo@$old"
expect "and still by its folder name" "far.md  (55 commits behind demo)" "$W" stale 90
fm far "nothere@$old"
lacks "a repository with no clone falls back to dates quietly" "far.md" "$W" stale 90
rm -f "$WIKIS_DIR"/demo/wiki/{far,near,gone,bare}.md
fi

if section "Dependency map"; then
D="$T/code/deps"
mkdir -p "$D/lib" "$D/app/web" "$D/app/inner"
git -C "$D/lib" init -q; git -C "$D/app" init -q; git -C "$D/app/inner" init -q
printf 'module example.com/me/lib\n\ngo 1.22\n' > "$D/lib/go.mod"
printf 'module example.com/me/app\n\nrequire (\n\texample.com/me/lib/sub v1.2.0\n\tgithub.com/other/thing v0.1.0\n)\n' > "$D/app/go.mod"
printf '{"name":"@me/web","dependencies":{"react":"19"}}\n' > "$D/app/web/package.json"
printf '{"name":"inner-only"}\n' > "$D/app/inner/package.json"
out="$("$W" deps --all 2>&1)"
for want in "lib owns go example.com/me/lib" "app owns npm @me/web (web/package.json)" "app uses lib's go example.com/me/lib/sub"; do
  case "$out" in *"$want"*) ok "deps: $want" ;; *) bad "deps: $want" "$out" ;; esac
done
case "$out" in *"app owns npm inner-only"*) bad "deps counts a nested repository under its own name" "$out" ;; *) ok "deps counts a nested repository under its own name" ;; esac
case "$out" in *"github.com/other/thing"*) bad "deps lists only uses of your own repositories' packages" "$out" ;; *) ok "deps lists only uses of your own repositories' packages" ;; esac
lacks "by default deps leaves out repositories no wiki covers" "example.com/me/lib" "$W" deps
# One folder nobody may read, as an agent's sandbox has, used to end every command
# that maps repositories to wikis: nothing printed, exit 1.
if [ "$(id -u)" != 0 ]; then
  with_rc() { "$@" 2>&1; echo "rc=$?"; }
  lint_was="$(with_rc "$W" lint demo)"; stale_was="$(with_rc "$W" stale 90)"; deps_was="$(with_rc "$W" deps --all)"
  mkdir -p "$T/code/locked/inner" && chmod 000 "$T/code/locked"
  now="$(with_rc "$W" lint demo)"
  [ "$now" = "$lint_was" ] && [ "$(printf '%s\n' "$now" | grep -c .)" -gt 1 ] && ok "lint is the same with a code folder it can't read" || bad "lint is the same with a code folder it can't read" "$now"
  now="$(with_rc "$W" stale 90)"
  [ "$now" = "$stale_was" ] && [ "$(printf '%s\n' "$now" | grep -c .)" -gt 1 ] && ok "and so is stale" || bad "and so is stale" "$now"
  now="$(with_rc "$W" deps --all)"
  [ "$now" = "$deps_was" ] && [ "$(printf '%s\n' "$now" | grep -c .)" -gt 1 ] && ok "and deps" || bad "and deps" "$now"
  chmod 755 "$T/code/locked" && rmdir "$T/code/locked/inner" "$T/code/locked"
else
  skipped "a code folder that can't be read (root can read anything)"
fi
mkdir -p "$T/code-none" && "$W" journal set code_dirs "$T/code-none" >/dev/null
out="$("$W" deps --all 2>&1)" && bad "deps with no repositories says a sandbox may be why" "$out" || case "$out" in *"no repositories under code_dirs"*"agent's sandbox"*) ok "deps with no repositories says a sandbox may be why" ;; *) bad "deps with no repositories says a sandbox may be why" "$out" ;; esac
"$W" journal set code_dirs "$T/code" >/dev/null
"$W" deps --all --write >/dev/null 2>&1
check "deps --write saves the shared wiki's data/dependencies.csv" grep -q '^uses,app,go,example.com/me/lib/sub,lib,' "$WIKIS_DIR/global/data/dependencies.csv"
rm -rf "$D" "$WIKIS_DIR/global/data/dependencies.csv"
fi

if section "Sync takes turns"; then
# Another session's sync holds the collection's lock: this one waits, then runs.
L="$(git -C "$WIKIS_DIR" rev-parse --absolute-git-dir)/llm-wiki-sync.lock"
echo "wait" > "$WIKIS_DIR/demo/raw/2026-01-04-000000-wait.md"
mkdir "$L"; ( sleep 2; rmdir "$L" ) &
out="$("$W" sync demo -m "demo: wait test" 2>&1)"
case "$out" in *"waiting for another session's sync"*"synced:"*) ok "sync waits for another session's sync, then runs" ;; *) bad "sync waits for another session's sync, then runs" "$out" ;; esac
check "and leaves no lock behind" test ! -d "$L"
echo "stale" > "$WIKIS_DIR/demo/raw/2026-01-04-000001-stale.md"
mkdir "$L"; touch -t 202001010000 "$L"
expect "a lock older than five minutes is stale" "synced:" "$W" sync demo -m "demo: stale lock"
# A note that came in and also sits here uncommitted, identical: set aside, pull again.
git -C "$T/clone2" pull -q --no-rebase --no-edit >/dev/null 2>&1
printf 'Captured: 2026-10-30\n\nSame note.\n' > "$T/clone2/demo/raw/2026-10-30-000001-same.md"
git -C "$T/clone2" add -A && git -C "$T/clone2" commit -qm "demo: same note" && git -C "$T/clone2" push -q
cp "$T/clone2/demo/raw/2026-10-30-000001-same.md" "$WIKIS_DIR/demo/raw/"
printf 'Captured: 2026-10-30\n\nOther.\n' > "$WIKIS_DIR/agents/raw/2026-10-30-000002-other.md"
out="$("$W" sync agents -m "agents: other" 2>&1)"
case "$out" in *"identical to what came in"*"synced:"*) ok "sync sets aside an identical local copy of an incoming file, then pulls" ;; *) bad "sync sets aside an identical local copy of an incoming file, then pulls" "$out" ;; esac
fi

if section "Session start in one call"; then
git -C "$WIKIS_DIR" add -A >/dev/null 2>&1; git -C "$WIKIS_DIR" commit -qm "smoke: before start" >/dev/null 2>&1; git -C "$WIKIS_DIR" push -q >/dev/null 2>&1
git -C "$T/clone2" pull -q --no-rebase --no-edit >/dev/null 2>&1
printf 'Captured: 2026-10-29\n\nFrom the other machine.\n' > "$T/clone2/demo/raw/2026-10-29-000000-other.md"
git -C "$T/clone2" add -A && git -C "$T/clone2" commit -qm "demo: capture 1 note" && git -C "$T/clone2" push -q
out="$("$W" start web 2>&1)"
case "$out" in *"wiki: "*"/demo, for the repository web"*) ok "start finds the wiki for a repository" ;; *) bad "start finds the wiki for a repository" "$out" ;; esac
case "$out" in *"pull: up to date"*) ok "start pulls the collection" ;; *) bad "start pulls the collection" "$out" ;; esac
check "and the pull brought the other machine's note" test -f "$WIKIS_DIR/demo/raw/2026-10-29-000000-other.md"
case "$out" in *"===== "*"/demo/index.md"*"===== "*"/global/index.md (global)"*"For agents, from"*"===== Waiting to be compiled"*"/demo: "*"note(s)"*) ok "start prints the indexes, For agents and what waits, in that order" ;; *) bad "start prints the indexes, For agents and what waits, in that order" "$out" ;; esac
expect "start points at the handbook" "/demo/AGENTS.md, the handbook" "$W" start web
mkdir -p "$WIKIS_DIR/demo/wiki"
printf -- '---\ntitle: Conventions\nsummary: x\nupdated: 2026-10-30\nverified: 2026-10-30\n---\n\n## For agents\n\n- After a push, check CI with gh pr checks. [raw/2026-10-30-000000-ci.md]\n\n## Tools\n\n- ls (cli): listing (raw/2026-10-30-000000-tools.md)\n- nosuchtool123 (cli): never installed\n- jira (mcp): tickets\n- $(touch %s/pwned) (cli): never run\n' "$T" > "$WIKIS_DIR/demo/wiki/conventions.md"
out="$("$W" start web 2>&1)"
case "$out" in *"For agents, from"*"demo/wiki/conventions.md"*"check CI with gh pr checks"*) ok "start prints the project's own For agents section" ;; *) bad "start prints the project's own For agents section" "$out" ;; esac
case "$out" in *"raw/2026-10-30-000000"*) bad "start leaves a rule's citation out, in either bracket" "$out" ;; *) ok "start leaves a rule's citation out, in either bracket" ;; esac
case "$out" in *"- ls (cli): listing  [installed]"*) ok "start marks a listed tool that's installed" ;; *) bad "start marks a listed tool that's installed" "$out" ;; esac
case "$out" in *"nosuchtool123 (cli): never installed  [NOT FOUND on this shell's PATH"*) ok "and one that isn't" ;; *) bad "and one that isn't" "$out" ;; esac
case "$out" in *"jira (mcp): tickets  [an MCP server"*) ok "and asks the agent to check an MCP itself" ;; *) bad "and asks the agent to check an MCP itself" "$out" ;; esac
check "nothing in the page is run" test ! -e "$T/pwned"
rm -f "$WIKIS_DIR/demo/wiki/conventions.md"
expect "start with no wiki for the repository uses the shared one" "No wiki covers brand-new yet" "$W" start brand-new
git -C "$WIKIS_DIR" remote set-url origin "$T/nowhere.git"
out="$("$W" start web 2>&1)" && ok "a failed pull doesn't fail start" || bad "a failed pull doesn't fail start" "$out"
case "$out" in *"pull: failed"*"pull before your first write"*) ok "and says so, with what to do" ;; *) bad "and says so, with what to do" "$out" ;; esac
git -C "$WIKIS_DIR" remote set-url origin "$T/remote.git"
fi

if section "A remote the branch doesn't track"; then
# setup's `git remote add` set no upstream, so a bare pull failed (a work Mac, 2026-10-30).
git -C "$WIKIS_DIR" branch -q --unset-upstream
expect "start pulls anyway" "pull: up to date with the remote" "$W" start web
check "and the branch tracks origin from then on" git -C "$WIKIS_DIR" rev-parse -q --verify '@{u}'
git -C "$WIKIS_DIR" branch -q --unset-upstream
lacks "update pulls anyway" "the pull failed" "$W" update --wikis-only
check "and sets the upstream too" git -C "$WIKIS_DIR" rev-parse -q --verify '@{u}'
git init -q --bare "$T/empty.git"
git -C "$WIKIS_DIR" remote set-url origin "$T/empty.git"
git -C "$WIKIS_DIR" branch -q --unset-upstream
expect "start with an empty remote says the next sync pushes to it" "the remote has nothing yet" "$W" start web
echo "first push" > "$WIKIS_DIR/demo/raw/first-push.md"
expect "sync to an empty remote makes the first push" "to origin for the first time" "$W" sync demo -m "demo: first push"
check "the remote has the branch, and the branch tracks it" git -C "$WIKIS_DIR" rev-parse -q --verify '@{u}'
git -C "$WIKIS_DIR" remote set-url origin "$T/remote.git"
git -C "$WIKIS_DIR" fetch -q origin && git -C "$WIKIS_DIR" branch -q --set-upstream-to="origin/$(git -C "$WIKIS_DIR" symbolic-ref --short HEAD)"
git -C "$WIKIS_DIR" rm -q "demo/raw/first-push.md" && git -C "$WIKIS_DIR" commit -q -m "demo: drop test note" && git -C "$WIKIS_DIR" pull -q --no-rebase --no-edit && git -C "$WIKIS_DIR" push -q
fi

if section "Antigravity plugin"; then
lacks "without Antigravity, setup --list says nothing about it" "antigravity    " "$W" setup --list
mkdir -p "$HOME/.gemini"
expect "with Antigravity, setup --list shows the plugin missing" "plugin missing" "$W" setup --list
expect "and names the section" "| antigravity |" "$W" setup --list
expect "and setup --new would ask about it" "antigravity" bash -c "'$W' setup --list; true"
out="$(printf '{"workspacePaths":["%s"],"conversationId":"c1"}' "$T/projects/web" | "$W" __agy-start)"
msg="$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["injectSteps"][0]["systemMessage"]["systemMessage"])' 2>&1)"
case "$msg" in *"wiki: "*"/demo, for the repository web"*"===== Waiting to be compiled"*) ok "the hook runs start for the open project and replies in Antigravity's format" ;; *) bad "the hook runs start for the open project and replies in Antigravity's format" "$out" ;; esac
case "$msg" in *"Do not run start again"*) ok "and tells the model not to run start again" ;; *) bad "and tells the model not to run start again" "$msg" ;; esac
case "$msg" in *"./wiki.sh"*|*" wiki.sh "*) bad "its commands are runnable paths, never ./wiki.sh" "$msg" ;; *) ok "its commands are runnable paths, never ./wiki.sh" ;; esac
out="$(printf 'not json' | "$W" __agy-start)"
case "$out" in *'"injectSteps"'*"Not in a repository"*) ok "bad input still gets a reply, for the shared wiki" ;; *) bad "bad input still gets a reply, for the shared wiki" "$out" ;; esac
check "the hook doesn't create the plugin by itself" test ! -e "$HOME/.gemini/config/plugins/llm-wiki"
mkdir -p "$HOME/.gemini/config/plugins/llm-wiki" && printf '{}' > "$HOME/.gemini/config/plugins/llm-wiki/plugin.json"
printf '{}' | "$W" __agy-start >/dev/null
expect "once installed, the hook keeps the plugin current" "plugin current" "$W" setup --list
# A file the state is worked out from, which this shell can't read, as in another
# agent's sandbox. It used to come out as "old", and setup would write the plugin again.
if [ "$(id -u)" != 0 ]; then
  chmod 000 "$HOME/.gemini/config/plugins/llm-wiki/hooks.json"
  expect "a plugin file it can't read is unknown, not old" "antigravity         unknown, can't read ~/.gemini/config/plugins/llm-wiki/hooks.json" "$W" setup --list
  expect "and setup antigravity changes nothing" "Nothing was changed" in_tty "$W" setup antigravity
  chmod 644 "$HOME/.gemini/config/plugins/llm-wiki/hooks.json"
else
  skipped "an Antigravity plugin file that can't be read (root can read anything)"
fi
check "its rule names the wikis and the start hook" grep -q "SessionStart hook runs" "$HOME/.gemini/config/plugins/llm-wiki/rules/AGENTS.md"
check "its hooks.json is Antigravity's flat SessionStart format" python3 -c "import json,sys; h=json.load(open(sys.argv[1]))['llm-wiki']['SessionStart'][0]; assert h['type']=='command' and h['command'].endswith(' __agy-start')" "$HOME/.gemini/config/plugins/llm-wiki/hooks.json"
check "its plugin.json has only fields Antigravity reads" python3 -c "import json,sys; assert set(json.load(open(sys.argv[1]))) <= {'name','description','logo','suggestedPrompts','displayName','version','disabled'}" "$HOME/.gemini/config/plugins/llm-wiki/plugin.json"
check "it links the llm-wiki skill" test -f "$HOME/.gemini/config/plugins/llm-wiki/skills/llm-wiki/SKILL.md"
A="$HOME/.gemini/config/plugins/llm-wiki/skills"
check "it makes a skill from each slash command" test -f "$A/wiki-compile/SKILL.md" -a -f "$A/wiki-save/SKILL.md" -a -f "$A/wiki-standup/SKILL.md" -a -f "$A/wiki-status/SKILL.md"
check "including the tour" grep -q '^Run `.*wiki.sh tour` for the tour.s guide, and read its output.$' "$A/wiki-tour/SKILL.md"
check "named and described for the agent" grep -q '^name: wiki-standup$' "$A/wiki-standup/SKILL.md"
check "an inline command becomes one to run, by a path the agent can use" grep -q '^Run `.*wiki.sh standup <options the user gave, if any>` for raw activity, and read its output.$' "$A/wiki-standup/SKILL.md"
lacks "and nothing Claude-only is left in them" 'ARGUMENTS\|CLAUDE_PLUGIN_ROOT\|^!`\|,,' cat "$A/wiki-compile/SKILL.md" "$A/wiki-save/SKILL.md" "$A/wiki-standup/SKILL.md" "$A/wiki-status/SKILL.md"
mkdir -p "$A/wiki-mine" "$A/wiki-gone" && echo "mine" > "$A/wiki-mine/SKILL.md" && sed 's/wiki-status/wiki-gone/' "$A/wiki-status/SKILL.md" > "$A/wiki-gone/SKILL.md"
echo "an edit" >> "$A/wiki-save/SKILL.md"
printf '{}' | "$W" __agy-start >/dev/null
check "a skill it didn't make is left alone" grep -qx mine "$A/wiki-mine/SKILL.md"
check "one it made for a command that's gone is removed" test ! -e "$A/wiki-gone"
lacks "and an edited one is made again" "an edit" cat "$A/wiki-save/SKILL.md"
rm -r "$A/wiki-mine"
check "and the team skills from the wikis" test "$HOME/.gemini/config/plugins/llm-wiki/skills/bump-proto" -ef "$WIKIS_DIR/global/skills/bump-proto"
mkskill "$WIKIS_DIR/global/skills/tidy-logs" "Tidy logs."
expect "skills link links new team skills into the plugin too" "tidy-logs (from global), for Antigravity" "$W" skills link
rm -r "$WIKIS_DIR/global/skills/tidy-logs"; "$W" skills link >/dev/null
check "and removes them there when they're gone" test ! -e "$HOME/.gemini/config/plugins/llm-wiki/skills/tidy-logs"
check "without touching the llm-wiki skill" test -f "$HOME/.gemini/config/plugins/llm-wiki/skills/llm-wiki/SKILL.md"
rm "$HOME/.gemini/config/plugins/llm-wiki/skills/bump-proto"
"$W" upgrade --all >/dev/null 2>&1
check "upgrade --all links team skills into the plugin too" test -L "$HOME/.gemini/config/plugins/llm-wiki/skills/bump-proto"
mkdir -p "$HOME/.gemini/config" && printf '{"userSettings":{"globalPermissionGrants":{"allow":["command(ls)"]}}}\n' > "$HOME/.gemini/config/config.json"
out="$("$W" permissions 2>&1)"
case "$out" in *"Antigravity grants"*"\"read_file($WIKIS_DIR)\","*"\"write_file($WIKIS_DIR)\","*"command("*"wiki"*) ok "permissions lists Antigravity's grants for the wikis and wiki.sh" ;; *) bad "permissions lists Antigravity's grants for the wikis and wiki.sh" "$out" ;; esac
expect "setup --list counts the missing Antigravity grants" "grant(s) missing" "$W" setup --list
"$W" permissions 2>/dev/null | sed -n '/^"read_file('"$(printf '%s' "$WIKIS_DIR" | sed 's#/#\\/#g')"')",/,$p' | sed 's/,$//' | python3 -c 'import json,sys; p=sys.argv[1]; s=json.load(open(p)); s["userSettings"]["globalPermissionGrants"]["allow"]+= [json.loads(l) for l in sys.stdin.read().splitlines()]; json.dump(s,open(p,"w"))' "$HOME/.gemini/config/config.json"
expect "once present, setup --list says so" "grants in place" "$W" setup --list
printf '{"something":"else"}\n' > "$HOME/.gemini/config/config.json"
lacks "an unexpected config.json isn't touched or reported on" "grant" "$W" setup --list
# The tool-call hooks: Gemini's tool names read as Claude's, Antigravity's reply shapes.
AP="$HOME/.gemini/config/plugins/llm-wiki"
"$W" new agyrem >/dev/null
cat > "$WIKIS_DIR/agyrem/wiki/conventions.md" <<'REM'
---
title: Conventions for agyrem
summary: How to work in agyrem.
updated: 2026-11-07
verified: 2026-11-07
---

## Reminders

- before bash `git push`: Before a push, make sure the hooks ran.
- on edit `payments/*`: Money is in cents.
- on tool `Agent`: Set the model.
REM
mkdir -p "$T/projects/agyrem/payments" && git -C "$T/projects/agyrem" init -q
RD="$HOME/.local/state/llm-wiki/reminders"
LOG="$HOME/.local/state/llm-wiki/agy-hooks.log"
export TMPDIR="$T/tmp"; mkdir -p "$TMPDIR"
agy_start() { printf '{"workspacePaths":["file://%s"],"conversationId":"%s"}' "$T/projects/agyrem" "$1" | "$W" __agy-start >/dev/null; }
# agy <tool|invoke> <json>: what Antigravity's hook replies.
agy() { printf '%s' "$2" | sh "$AP/hooks/agy-hook.sh" "$1"; }
# call <conversation> <tool name> <args json>
call() { printf '{"conversationId":"%s","workspacePaths":["file://%s"],"toolCall":{"name":"%s","args":%s}}' "$1" "$T/projects/agyrem" "$2" "$3"; }
ALLOW='{"decision": "allow"}'
is() { local name="$1" want="$2" got="$3"; if [ "$got" = "$want" ]; then ok "$name"; else bad "$name" "wanted: $want
got: $got"; fi; }
check "setup installs the tool-call hooks beside the plugin" test -x "$AP/hooks/agy-hook.sh" -a -f "$AP/hooks/reminders.py"
check "hooks.json has PreToolUse for every tool (the docs' matcher *), and PreInvocation" python3 -c "
import json, sys
h = json.load(open(sys.argv[1]))['llm-wiki']
m = h['PreToolUse'][0]
assert m['matcher'] == '*' and m['hooks'][0]['type'] == 'command' and m['hooks'][0]['command'].endswith('hooks/agy-hook.sh tool')
assert h['PreInvocation'][0]['command'].endswith('hooks/agy-hook.sh invoke')
assert h['SessionStart'][0]['command'].endswith(' __agy-start')" "$AP/hooks.json"
rm "$AP/hooks/agy-hook.sh"
expect "a plugin without them is old" "plugin old" "$W" setup --list
agy_start c-1
expect "and the next conversation brings them back" "plugin current" "$W" setup --list
check "a conversation's reminders are written when it starts" grep -q "git push" "$RD/agy-c-1.tsv"
check "and nothing is queued yet" test ! -e "$RD/agy-c-1.pending"
before="$(find "$HOME/.gemini" "$T/projects/agyrem" -type f | sort | cksum)"
out="$(agy tool "$(call c-1 run_command '{"CommandLine":"cd x && git push origin main","Cwd":"/x"}')")"
if printf '%s' "$out" | python3 -c 'import json, sys; d = json.load(sys.stdin); assert d["decision"] == "deny" and "make sure the hooks ran" in d["reason"] and "from the wiki agyrem" in d["reason"]' 2>/dev/null; then ok "a before reminder denies the shell command once, with the rule"; else bad "a before reminder denies the shell command once, with the rule" "$out"; fi
is "the same command made again goes through" "$ALLOW" "$(agy tool "$(call c-1 run_command '{"CommandLine":"git push origin main"}')")"
is "a command no reminder covers goes through" "$ALLOW" "$(agy tool "$(call c-1 run_command '{"CommandLine":"ls"}')")"
is "an edit reminder doesn't match a read" "$ALLOW" "$(agy tool "$(call c-1 view_file "{\"AbsolutePath\":\"$T/projects/agyrem/payments/a.go\"}")")"
check "and queues nothing" test ! -e "$RD/agy-c-1.pending"
is "an on reminder lets the edit go" "$ALLOW" "$(agy tool "$(call c-1 replace_file_content "{\"TargetFile\":\"$T/projects/agyrem/payments/charge.go\"}")")"
check "and queues its rule" grep -q "^- Money is in cents. (from the wiki agyrem, wiki/conventions.md)$" "$RD/agy-c-1.pending"
is "a file outside what the pattern covers queues nothing more" "$ALLOW" "$(agy tool "$(call c-1 write_to_file "{\"TargetFile\":\"$T/projects/agyrem/main.go\"}")")"
is "the same edit again goes through" "$ALLOW" "$(agy tool "$(call c-1 multi_replace_file_content "{\"TargetFile\":\"$T/projects/agyrem/payments/charge.go\"}")")"
is "a tool reminder matches Gemini's subagent tool" "$ALLOW" "$(agy tool "$(call c-1 invoke_subagent '{"Subagents":[]}')")"
out="$(agy invoke '{"conversationId":"c-1"}')"
if printf '%s' "$out" | python3 -c 'import json, sys; m = json.load(sys.stdin)["injectSteps"][0]["systemMessage"]["systemMessage"]; assert "Money is in cents." in m and "Set the model." in m' 2>/dev/null; then ok "PreInvocation hands over the queued rules as a system message"; else bad "PreInvocation hands over the queued rules as a system message" "$out"; fi
is "once" '{}' "$(agy invoke '{"conversationId":"c-1"}')"
check "and the queue is gone" test ! -e "$RD/agy-c-1.pending"
check "the hooks wrote nothing outside the state folder" test "$before" = "$(find "$HOME/.gemini" "$T/projects/agyrem" -type f | sort | cksum)"
agy_start c-2
printf -- '- Old news (from the wiki agyrem, wiki/conventions.md)\n' > "$RD/agy-c-2.pending"; touch -t 202001010000 "$RD/agy-c-2.pending"
is "a queue more than a day old is dropped, not delivered" '{}' "$(agy invoke '{"conversationId":"c-2"}')"
check "and removed" test ! -e "$RD/agy-c-2.pending"
printf 'x\n' > "$RD/agy-c-9.pending"; touch -t 202001010000 "$RD/agy-c-9.pending"
agy_start c-3
check "a new conversation sweeps old queues" test ! -e "$RD/agy-c-9.pending"
# The app's own file tools differ from the docs: write_file takes Path, and so does read_file.
agy_start c-5
is "a read_file with Path is not an edit" "$ALLOW" "$(agy tool "$(call c-5 read_file "{\"Path\":\"$T/projects/agyrem/payments/charge.go\"}")")"
check "and a read_file queues nothing" test ! -e "$RD/agy-c-5.pending"
# A read_file or view_file of a wiki page is a lookup, once per wiki per conversation.
LS="$WIKIS_DIR/stats.csv"; rm -f "$LS"
mkdir -p "$WIKIS_DIR/agyrem/wiki/concepts"
printf -- '---\ntitle: A\nsummary: a\nupdated: 2026-11-09\nverified: 2026-11-09\n---\n\nText.\n' > "$WIKIS_DIR/agyrem/wiki/concepts/a.md"
cp "$WIKIS_DIR/agyrem/wiki/concepts/a.md" "$WIKIS_DIR/agyrem/wiki/concepts/b.md"
lines() { cat "$1" 2>/dev/null | grep -c . || true; }
today="$(date -u +%Y-%m-%d)"
is "a read_file of a page gets an allow" "$ALLOW" "$(agy tool "$(call c-5 read_file "{\"Path\":\"$WIKIS_DIR/agyrem/wiki/concepts/a.md\"}")")"
is "and logs a hit" "date,wiki,result
$today,agyrem,hit" "$(cat "$LS" 2>/dev/null)"
is "a view_file of another page, in the same conversation, gets an allow" "$ALLOW" "$(agy tool "$(call c-5 view_file "{\"AbsolutePath\":\"$WIKIS_DIR/agyrem/wiki/concepts/b.md\"}")")"
check "and logs nothing more" test "$(lines "$LS")" = 2
agy tool "$(call c-1 view_file "{\"AbsolutePath\":\"$WIKIS_DIR/agyrem/wiki/concepts/b.md\"}")" >/dev/null
check "another conversation logs its own" test "$(lines "$LS")" = 3
for p in "$WIKIS_DIR/agyrem/index.md" "$WIKIS_DIR/agyrem/AGENTS.md" "$T/projects/agyrem/payments/charge.go"; do
  agy tool "$(call c-3 read_file "{\"Path\":\"$p\"}")" >/dev/null
done
check "index.md, AGENTS.md and a file outside the wikis log nothing" test "$(lines "$LS")" = 3
check "the conversation's reads are kept beside its reminders" test -s "$RD/agy-c-5.reads"
check "the plugin's copy of the hook body is this one" cmp -s "$REPO/hooks/reminders.py" "$AP/hooks/reminders.py"
rm -f "$LS"
# The args are built apart: bash 3.2 mangles this much quoting inside nested $( ).
wf_args="{\"Path\":\"$T/projects/agyrem/payments/charge.go\",\"Content\":\"x\",\"Overwrite\":true}"
is "a write_file with Path is an edit" "$ALLOW" "$(agy tool "$(call c-5 write_file "$wf_args")")"
check "and a write_file queues its rule" grep -q "^- Money is in cents. (from the wiki agyrem, wiki/conventions.md)$" "$RD/agy-c-5.pending"
# A hook's exit code isn't documented, so on every path it prints a reply that lets the call go, and exits 0.
is "bad JSON gets an allow" "$ALLOW" "$(agy tool 'not json')"
is "an empty line gets an allow" "$ALLOW" "$(agy tool '')"
is "a call of an unexpected shape gets an allow" "$ALLOW" "$(agy tool '{"conversationId":"c-3","toolCall":"run_command"}')"
is "a call with no conversation gets an allow" "$ALLOW" "$(agy tool '{"toolCall":{"name":"run_command","args":{"CommandLine":"git push"}}}')"
is "a conversation with no rows gets an allow" "$ALLOW" "$(agy tool "$(call c-none run_command '{"CommandLine":"git push"}')")"
is "PreInvocation with bad JSON gets an empty reply" '{}' "$(agy invoke 'not json')"
is "a missing state folder gets an allow" "$ALLOW" "$(printf '%s' "$(call c-3 run_command '{"CommandLine":"git push"}')" | XDG_STATE_HOME="$T/no-state" sh "$AP/hooks/agy-hook.sh" tool)"
check "and the hook still exits 0" sh -c "printf 'x' | XDG_STATE_HOME='$T/no-state' sh '$AP/hooks/agy-hook.sh' tool >/dev/null"
check "and says so in the log, in the temp folder when the state folder is missing" grep -q "no-state" "$TMPDIR/llm-wiki-agy-hooks.log"
if [ "$(id -u)" != 0 ]; then
  agy_start c-4
  chmod 000 "$RD/agy-c-4.tsv"
  is "an unreadable rows file gets an allow" "$ALLOW" "$(agy tool "$(call c-4 run_command '{"CommandLine":"git push"}')")"
  chmod 644 "$RD/agy-c-4.tsv"
  chmod 000 "$RD"
  is "an unreadable state folder gets an allow, as in a sandbox that refuses it" "$ALLOW" "$(agy tool "$(call c-4 run_command '{"CommandLine":"git push"}')")"
  chmod 755 "$RD"
else
  skipped "the hooks with a state folder that can't be read (root can read anything)"
fi
is "with python3 gone, an allow" "$ALLOW" "$(printf '%s' "$(call c-3 run_command '{"CommandLine":"git push"}')" | PATH="/nonexistent" /bin/sh "$AP/hooks/agy-hook.sh" tool)"
for want in deny queued delivered no-match no-conversation no-rows "error: "; do
  check "the log has a $want line" grep -q "	$want" "$LOG"
done
check "each line of it has a time, the event, the conversation, the tool and what came of it" awk -F'\t' 'NF != 5 { exit 1 }' "$LOG"
rm -rf "$HOME/.gemini"
fi

if section "Codex plugin"; then
lacks "without Codex, setup --list says nothing about it" "codex" "$W" setup --list
mkdir -p "$HOME/.codex"
expect "with Codex, setup --list shows the plugin missing" "codex               plugin missing" "$W" setup --list
expect "and names the section" "| codex |" "$W" setup --list
codex_reply() { python3 -c 'import json,sys; d=json.load(sys.stdin)["hookSpecificOutput"]; print(d["hookEventName"]); print(d["additionalContext"])' 2>&1; }
msg="$(printf '{"cwd":"%s","hook_event_name":"SessionStart","source":"startup"}' "$T/projects/web" | "$W" __codex-start | codex_reply)"
case "$msg" in "SessionStart"*"wiki: "*"/demo, for the repository web"*"===== Waiting to be compiled"*) ok "the hook runs start for the session's folder and replies with additionalContext" ;; *) bad "the hook runs start for the session's folder and replies with additionalContext" "$msg" ;; esac
case "$msg" in *"Do not run start again"*) ok "and tells the model not to run start again" ;; *) bad "and tells the model not to run start again" "$msg" ;; esac
case "$msg" in *"./wiki.sh"*|*"just compacted"*) bad "its commands are runnable paths, and a fresh session isn't told it was compacted" "$msg" ;; *) ok "its commands are runnable paths, and a fresh session isn't told it was compacted" ;; esac
msg="$(printf '{"cwd":"%s","hook_event_name":"PostCompact"}' "$T/projects/web" | "$W" __codex-start | codex_reply)"
case "$msg" in "PostCompact"*"just compacted"*"capture"*) ok "after compaction it says to capture before answering" ;; *) bad "after compaction it says to capture before answering" "$msg" ;; esac
case "$msg" in *"===== "*) bad "and doesn't repeat start's output" "$msg" ;; *) ok "and doesn't repeat start's output" ;; esac
expect "a SessionStart after compaction gets both" "just compacted" bash -c "printf '{\"cwd\":\"%s\",\"hook_event_name\":\"SessionStart\",\"source\":\"compact\"}' '$T/projects/web' | '$W' __codex-start"
expect "bad input still gets a reply, for the shared wiki" "Not in a repository" bash -c "cd '$HOME' && printf 'not json' | '$W' __codex-start"
check "the hook doesn't create the plugin by itself" test ! -e "$HOME/.codex/llm-wiki"
# A stand-in for the codex command: it records its arguments and marks the config
# the way the real one does.
cat > "$T/bin/codex" <<EOF
#!/bin/sh
echo "\$*" >> "$T/codex.log"
case "\$*" in
  "plugin marketplace add "*) printf '[marketplaces.llm-wiki]\nsource = "%s"\n' "\$4" >> "$HOME/.codex/config.toml" ;;
  "plugin add llm-wiki@llm-wiki") grep -qF '[plugins."llm-wiki@llm-wiki"]' "$HOME/.codex/config.toml" 2>/dev/null || printf '[plugins."llm-wiki@llm-wiki"]\nenabled = true\n' >> "$HOME/.codex/config.toml" ;;
esac
EOF
chmod +x "$T/bin/codex"
printf '# Mine\n\nKeep this.\n\nMy knowledge wikis live in ~/old. Run the old line.\n\nAnd this.\n' > "$HOME/.codex/AGENTS.md"
out="$(printf 'y\n' | PATH="$T/bin:$PATH" in_tty "$W" setup codex 2>&1)"
case "$out" in *"replaces the wiki line"*"/hooks and trust both"*) ok "setup codex installs it and says to trust its hooks" ;; *) bad "setup codex installs it and says to trust its hooks" "$out" ;; esac
check "it adds the marketplace and the plugin with the codex command" grep -qx "plugin add llm-wiki@llm-wiki" "$T/codex.log"
check "its marketplace lists the plugin" python3 -c "import json,sys; p=json.load(open(sys.argv[1]))['plugins'][0]; assert p['name']=='llm-wiki' and p['source']=={'source':'local','path':'./plugins/llm-wiki'}" "$HOME/.codex/llm-wiki/.agents/plugins/marketplace.json"
check "its hooks run __codex-start at SessionStart and PostCompact" python3 -c "import json,sys; h=json.load(open(sys.argv[1]))['hooks']['hooks']; assert all(h[e][0]['hooks'][0]['command'].endswith(' __codex-start') for e in ('SessionStart','PostCompact'))" "$HOME/.codex/llm-wiki/plugins/llm-wiki/.codex-plugin/plugin.json"
check "the old line is replaced in place, and the rest of AGENTS.md stays" python3 -c "import sys; t=open(sys.argv[1]).read(); assert t.startswith('# Mine\n\nKeep this.\n\nMy knowledge wikis live in') and 'plugin' in t.split('\n')[4] and t.endswith('\n\nAnd this.\n') and 'old line' not in t" "$HOME/.codex/AGENTS.md"
check "it links the llm-wiki skill" test -f "$HOME/.codex/skills/llm-wiki/SKILL.md"
check "and the slash commands as skills" test -f "$HOME/.codex/skills/wiki-compile/SKILL.md"
rm "$HOME/.codex/skills/bump-proto"; "$W" upgrade --all >/dev/null 2>&1
check "upgrade --all links team skills for Codex too" test -L "$HOME/.codex/skills/bump-proto"
check "and the team skills from the wikis" test "$HOME/.codex/skills/bump-proto" -ef "$WIKIS_DIR/global/skills/bump-proto"
expect "setup --list shows it current" "codex               plugin current" env PATH="$T/bin:$PATH" "$W" setup --list
if [ "$(id -u)" != 0 ]; then
  todo_was="$(PATH="$T/bin:$PATH" "$W" status 2>&1 | grep 'new setting' || true)"
  chmod 000 "$HOME/.codex/config.toml"
  expect "a Codex file it can't read is unknown, not old" "codex               unknown, can't read ~/.codex/config.toml" env PATH="$T/bin:$PATH" "$W" setup --list
  now="$(PATH="$T/bin:$PATH" "$W" status 2>&1 | grep 'new setting' || true)"
  [ "$now" = "$todo_was" ] && ok "and status doesn't count it as a new setting" || bad "and status doesn't count it as a new setting" "was: $todo_was now: $now"
  : > "$T/codex.log"
  expect "and setup codex changes nothing" "Nothing was changed" env PATH="$T/bin:$PATH" LLM_WIKI_TEST_TTY=1 "$W" setup codex
  check "nor runs codex" test ! -s "$T/codex.log"
  chmod 644 "$HOME/.codex/config.toml"
else
  skipped "a Codex file that can't be read (root can read anything)"
fi
: > "$T/codex.log"
PATH="$T/bin:$PATH" in_tty "$W" setup codex </dev/null >/dev/null 2>&1
check "running setup again doesn't reinstall an unchanged plugin" test ! -s "$T/codex.log"
mkskill "$WIKIS_DIR/global/skills/tidy-logs" "Tidy logs."
expect "skills link links new team skills for Codex too" "tidy-logs (from global), for Codex" "$W" skills link
rm -r "$WIKIS_DIR/global/skills/tidy-logs"; "$W" skills link >/dev/null
check "and removes them there when they're gone" test ! -e "$HOME/.codex/skills/tidy-logs"
rm "$HOME/.codex/skills/llm-wiki"
printf '{"cwd":"%s","hook_event_name":"SessionStart"}' "$T/projects/web" | "$W" __codex-start >/dev/null
check "each session start relinks the skill" test -f "$HOME/.codex/skills/llm-wiki/SKILL.md"
rm -rf "$HOME/.codex" "$T/bin/codex" "$T/codex.log"
fi

if section "Cursor"; then
lacks "without Cursor, setup --list says nothing about it" "cursor" "$W" setup --list
mkdir -p "$HOME/.cursor"
expect "with Cursor and no Claude Code plugin, setup --list shows the hook missing" "cursor              hook missing" "$W" setup --list
expect "and names the section" "| cursor |" "$W" setup --list
msg="$(printf '{"workspace_roots":["%s"],"hook_event_name":"sessionStart"}' "$T/projects/web" | "$W" __cursor-start | python3 -c 'import json,sys; print(json.load(sys.stdin)["additional_context"])' 2>&1)"
case "$msg" in *"Do not run start again"*"wiki: "*"/demo, for the repository web"*) ok "the hook runs start for the first workspace and replies with additional_context" ;; *) bad "the hook runs start for the first workspace and replies with additional_context" "$msg" ;; esac
expect "bad input still gets a reply" "additional_context" bash -c "cd '$HOME' && printf 'not json' | '$W' __cursor-start"
check "the hook doesn't install itself" test ! -e "$HOME/.cursor/hooks.json"
printf '{"version":1,"hooks":{"afterFileEdit":[{"command":"./format.sh"}],"sessionStart":[{"command":"./mine.sh"}]}}\n' > "$HOME/.cursor/hooks.json"
out="$(printf 'y\n' | in_tty "$W" setup cursor 2>&1)"
case "$out" in *"added."*"User Rules"*"llm-wiki hook in ~/.cursor/hooks.json runs"*) ok "setup cursor adds the hook and gives the user-rules line" ;; *) bad "setup cursor adds the hook and gives the user-rules line" "$out" ;; esac
check "its hooks.json keeps the other hooks and adds ours" python3 -c "import json,sys; h=json.load(open(sys.argv[1])); s=h['hooks']['sessionStart']; assert h['version']==1 and h['hooks']['afterFileEdit'][0]['command']=='./format.sh' and s[0]['command']=='./mine.sh' and s[1]['command'].endswith(' __cursor-start') and len(s)==2" "$HOME/.cursor/hooks.json"
expect "setup --list shows it current" "cursor              hook current" "$W" setup --list
if [ "$(id -u)" != 0 ]; then
  chmod 000 "$HOME/.cursor/hooks.json"
  expect "a Cursor hooks file it can't read is unknown, not missing" "cursor              unknown, can't read ~/.cursor/hooks.json" "$W" setup --list
  expect "and setup cursor changes nothing" "Nothing was changed" in_tty "$W" setup cursor
  chmod 644 "$HOME/.cursor/hooks.json"
else
  skipped "a Cursor hooks file that can't be read (root can read anything)"
fi
in_tty "$W" setup cursor </dev/null >/dev/null 2>&1
check "running setup again doesn't add it twice" python3 -c "import json,sys; assert len(json.load(open(sys.argv[1]))['hooks']['sessionStart'])==2" "$HOME/.cursor/hooks.json"
check "it links the llm-wiki skill for Cursor" test -f "$HOME/.cursor/skills/llm-wiki/SKILL.md"
check "and the slash commands as skills" test -f "$HOME/.cursor/skills/wiki-status/SKILL.md"
rm "$HOME/.cursor/skills/bump-proto"; "$W" upgrade --all >/dev/null 2>&1
check "upgrade --all links team skills for Cursor too" test -L "$HOME/.cursor/skills/bump-proto"
check "and the team skills" test "$HOME/.cursor/skills/bump-proto" -ef "$WIKIS_DIR/global/skills/bump-proto"
# With the Claude Code plugin installed, Cursor runs its hook, so ours stays quiet.
mkdir -p "$HOME/.claude/plugins"
git init -q "$T/mkt" && git -C "$T/mkt" commit -q --allow-empty -m one && first="$(git -C "$T/mkt" rev-parse HEAD)"
printf '{"version":2,"plugins":{"llm-wiki@mk":[{"scope":"user","installPath":"%s","gitCommitSha":"%s"}]}}\n' "$T/mkt" "$first" > "$HOME/.claude/plugins/installed_plugins.json"
printf '{"mk":{"source":{"source":"directory","path":"%s"},"installLocation":"%s"}}\n' "$T/mkt" "$T/mkt" > "$HOME/.claude/plugins/known_marketplaces.json"
expect "with the Claude Code plugin, the Cursor hook replies with nothing" "{}" bash -c "printf '{}' | '$W' __cursor-start"
expect "and setup --list says Cursor runs that plugin" "cursor              runs the Claude Code plugin" "$W" setup --list
lacks "status is quiet while the plugin copy matches its marketplace" "behind its marketplace" "$W" status
git -C "$T/mkt" commit -q --allow-empty -m two
expect "status says when the plugin copy is behind its marketplace, for Cursor too" "llm-wiki@mk is installed from ${first:0:7}, behind its marketplace at $(git -C "$T/mkt" rev-parse --short=7 HEAD). Claude Code and Cursor run that copy" "$W" status
rm -rf "$HOME/.cursor" "$HOME/.claude/plugins/installed_plugins.json" "$HOME/.claude/plugins/known_marketplaces.json" "$T/mkt"
fi

if section "Feedback on llm-wiki"; then
FB="$HOME/.local/state/llm-wiki/feedback"
expect "feedback is off until the user turns it on" "feedback               off" bash -c "'$W' setup --list | sed 's/  */               /'"
expect "and setup --new would ask" "feedback" bash -c "'$W' setup --list | grep '<- new'"
printf 'details\n' > "$T/fb.md"
expect "while off, add saves nothing and says not to retry" "nothing was saved. Don't try again" "$W" feedback add bug "something" --file "$T/fb.md"
check "and wrote no note" test ! -d "$FB"
lacks "start has no Feedback section while it's off" "Feedback on llm-wiki" "$W" start web
expect "setup feedback takes the answer" "feedback: share" bash -c "printf 'share\n' | LLM_WIKI_TEST_TTY=1 '$W' setup feedback"
expect "a bad kind is refused" "the kind is one of" "$W" feedback add oops "something" --file "$T/fb.md"
expect "a note without details is refused" "the details go in --file" bash -c "'$W' feedback add bug 'something' </dev/null"
cat > "$T/fb.md" <<EOF
Ran \`wiki sync\` in $HOME/code/web with no wiki name, from the demo wiki (demo:wiki/x.md).
Remote git@github.com:acme/demo-service.git, user someone@example.com, token ghp_abcdefghijklmnopqrstuvwxyz0123456789.
Issues go to https://github.com/broxgit/llm-wiki/issues.
EOF
expect "add saves a note" "feedback: saved" "$W" feedback add bug "sync without a name only says name a wiki" --agent "Smoke, test model" --file "$T/fb.md"
n="$(ls "$FB" | head -n 1)"; n="${n%.md}"
check "the note records its kind, agent, version and system" bash -c "grep -q '^Kind: bug' '$FB/$n.md' && grep -q '^Agent: Smoke, test model' '$FB/$n.md' && grep -q '^Handbook: v' '$FB/$n.md' && grep -q '^System: ' '$FB/$n.md'"
expect "the same summary again counts as seen again" "seen again" bash -c "printf 'more\n' | '$W' feedback add bug 'Sync without a name only says name a wiki' --agent other"
check "in one note, seen twice" bash -c "[ \$(ls '$FB' | wc -l) -eq 1 ] && grep -q '^Seen: 2' '$FB/$n.md'"
expect "feedback lists it" "seen 2   sync without a name only says name a wiki" "$W" feedback
expect "start tells agents to follow rules/feedback.md" "===== Feedback on llm-wiki: share" "$W" start web
lacks "a note captured today doesn't make start remind the user yet" "wait for the user to read" "$W" start web
sed -i.bak 's/^Captured: .*/Captured: 2026-01-01 09:00 UTC/' "$FB/$n.md" && rm -f "$FB/$n.md.bak"
expect "an older one does, telling the agent never to send it" "Never run feedback send yourself" "$W" start web
lacks "and only once a day" "wait for the user to read" "$W" start web
TS="$HOME/.config/llm-wiki/tips"
sed -i.bak '/^shown:feedback /d' "$TS" && rm -f "$TS.bak"
"$W" feedback >/dev/null
expect "an agent listing them doesn't count as the user looking" "wait for the user to read" "$W" start web
sed -i.bak '/^shown:feedback /d' "$TS" && rm -f "$TS.bak"
printf 'used:feedback %s\n' "$(date -u +%Y-%m-%d)" >> "$TS"
lacks "for three days after the user looked, start doesn't remind" "wait for the user to read" "$W" start web
sed -i.bak '/^used:feedback /d' "$TS" && rm -f "$TS.bak"
out="$("$W" report 2>&1)"
case "$out" in *"## Needs you"*"- llm-wiki feedback: 1 note(s)"*"Run: "*"feedback send <id> (it asks before filing)"*) ok "report lists the notes under Needs you, with how to read and file them" ;; *) bad "report lists the notes under Needs you, with how to read and file them" "$out" ;; esac
expect "status lists it under To do" "feedback: 1 note(s) from agents about llm-wiki" "$W" status
out="$("$W" feedback show "$n" 2>&1)"
case "$out" in "[bug] sync without a name only says name a wiki"*) ok "show drafts the issue, title first" ;; *) bad "show drafts the issue, title first" "$out" ;; esac
case "$out" in *"$HOME"*|*"demo:wiki"*|*" demo wiki"*|*acme*|*someone@example.com*|*ghp_*) bad "the draft has home paths, project names, remotes, emails and tokens scrubbed" "$out" ;; *) ok "the draft has home paths, project names, remotes, emails and tokens scrubbed" ;; esac
case "$out" in *"https://github.com/broxgit/llm-wiki/issues"*) ok "but keeps llm-wiki's own repository" ;; *) bad "but keeps llm-wiki's own repository" "$out" ;; esac
expect "send needs a terminal, so an agent can't file one" "needs a terminal" bash -c "'$W' feedback send '$n' </dev/null"
cat > "$T/bin/gh" <<EOF
#!/bin/sh
case "\$1 \$2" in
  "auth status") exit 0 ;;
  "issue create") echo "\$*" > "$T/gh.log"; cat > "$T/gh.body"; echo "https://github.com/broxgit/llm-wiki/issues/999" ;;
esac
EOF
chmod +x "$T/bin/gh"
out="$(printf 'n\n' | PATH="$T/bin:$PATH" LLM_WIKI_TEST_TTY=1 "$W" feedback send "$n" 2>&1)"
case "$out" in *"This would be filed on broxgit/llm-wiki"*"Not filed"*) ok "send shows the draft and files nothing on a no" ;; *) bad "send shows the draft and files nothing on a no" "$out" ;; esac
check "gh wasn't asked to file" test ! -e "$T/gh.log"
expect "on a yes, it files it with gh" "filed: https://github.com/broxgit/llm-wiki/issues/999" bash -c "printf 'y\n' | PATH='$T/bin:$PATH' LLM_WIKI_TEST_TTY=1 '$W' feedback send '$n'"
check "on llm-wiki's repository, with the drafted title" grep -q -- "--repo broxgit/llm-wiki --title \[bug\] sync without a name" "$T/gh.log"
lacks "and the scrubbed body" "acme" cat "$T/gh.body"
check "the note is marked sent, with the issue" grep -q '^Status: sent .* https://github.com/broxgit/llm-wiki/issues/999' "$FB/$n.md"
lacks "status no longer counts it" "feedback:" "$W" status
printf 'other\n' | "$W" feedback add idea "an idea" >/dev/null
m="$(cd "$FB" && echo *-an-idea.md)"; m="${m%.md}"
"$W" feedback dismiss "$m" >/dev/null
check "dismiss marks a note dismissed" grep -q '^Status: dismissed' "$FB/$m.md"
printf 'mode=notes\n' > "$HOME/.config/llm-wiki/feedback"
printf 'x\n' | "$W" feedback add docs "a docs note" >/dev/null
m="$(cd "$FB" && echo *-a-docs-note.md)"; m="${m%.md}"
expect "in notes mode, send refuses" "sharing is off" bash -c "printf 'y\n' | LLM_WIKI_TEST_TTY=1 '$W' feedback send '$m'"
lacks "and start doesn't ask agents to point the user at it" "wait for the user to read" "$W" start web
# Another collection's wiki names are private too, wherever this runs from.
mkdir -p "$T/other-coll/client-secret-wiki" && touch "$T/other-coll/client-secret-wiki/AGENTS.md" "$T/other-coll/client-secret-wiki/index.md"
printf 'other %s\n' "$T/other-coll" > "$HOME/.config/llm-wiki/collections"
printf 'Hit this in the client-secret-wiki wiki.\n' | "$W" feedback add bug "a note naming another collection" >/dev/null
m="$(cd "$FB" && echo *-a-note-naming-another-collection.md)"; m="${m%.md}"
lacks "the draft scrubs wiki names from every collection" "client-secret-wiki" "$W" feedback show "$m"
rm -rf "$T/other-coll" "$HOME/.config/llm-wiki/collections"
# Two summaries that share a slug, saved in the same second, are two notes.
printf 'x\n' | "$W" feedback add docs "It broke" >/dev/null; printf 'y\n' | "$W" feedback add docs "It broke!" >/dev/null
check "two notes whose summaries share a slug never overwrite each other" bash -c "[ \$(ls '$FB' | grep -c -- '-it-broke') -eq 2 ] && grep -lq '^Summary: It broke!' '$FB'/*-it-broke*.md"
check "the handbook rule ships in the template" grep -q 'wiki.sh feedback add' "$REPO/template/rules/feedback.md"
check "and AGENTS.md points to it" grep -q 'rules/feedback.md' "$REPO/template/AGENTS.md"
check "the open items rule ships in the template" grep -q 'Waiting: <who> | <what>' "$REPO/template/rules/open.md"
check "and AGENTS.md points to it" grep -q 'rules/open.md' "$REPO/template/AGENTS.md"
check "and the empty ledger ships" grep -q '^# Open items' "$REPO/template/open.md"
check "and compile says how to stamp Verified: lines" grep -q 'Verified:' "$REPO/template/rules/compile.md"
check "and the lesson kind is in the patterns rules" grep -q '\*\*lesson\*\*' "$REPO/template/rules/patterns.md"
check "and an operational job is recorded from the first run" grep -q 'from the first run' "$REPO/template/rules/patterns.md"
check "and each separate request is a sighting" grep -q 'each separate request is a sighting' "$REPO/template/rules/patterns.md"
check "and AGENTS.md says the first run counts" grep -q 'the first run included' "$REPO/template/AGENTS.md"
check "and lint drops a job seen once and not again" grep -q 'single sighting' "$REPO/template/rules/lint.md"
# feedback add, from the compiled helper and from the Bash: the same stdout, stderr and
# exit code, and the same notes, by name, permissions and text. The clock in a name or
# a note is written STAMP or WHEN, since the two run a moment apart.
[ -x "$T/bin/llm-wiki" ] || ! command -v go >/dev/null 2>&1 || build_helper >/dev/null 2>&1
if [ -x "$T/bin/llm-wiki" ]; then
  printf '#!/bin/sh\n[ "$1" = feedback-add ] || exec "%s" "$@"\n"%s" "$@"\nrc=$?\necho "$rc" >> "%s"\nexit $rc\n' "$T/bin/llm-wiki" "$T/bin/llm-wiki" "$T/fb-ran" > "$T/bin/fb-spy"
  chmod +x "$T/bin/fb-spy"
  mkdir -p "$T/fbp/seed" "$T/fbp/share/llm-wiki" "$T/fbp/notes/llm-wiki" "$T/fbp/off/llm-wiki"
  printf 'mode=share\n' > "$T/fbp/share/llm-wiki/feedback"; printf 'mode=notes\n' > "$T/fbp/notes/llm-wiki/feedback"; printf 'mode=nope\n' > "$T/fbp/off/llm-wiki/feedback"
  fbnote() { printf 'Kind: bug\nSummary: %s\nStatus: %s\nAgent: someone\nCaptured: 2026-01-01 10:00 UTC\nllm-wiki: abc1234\nHandbook: v1\nSystem: a system\nSeen: %s\n\nSeen: in the details too\n' "$2" "$3" "$4" > "$T/fbp/seed/$1.md"; }
  fbnote 20260101-100000-known-thing "Known Thing" new 2
  fbnote 20260101-100001-old-thing "Old thing" "dismissed 2026-01-02" 1
  fbnote 20260101-100002-odd-count "Odd count" new "x"
  fbnote 20260101-100003-open-end "Open end" new 1; printf 'and no line break at the end' >> "$T/fbp/seed/20260101-100003-open-end.md"
  fbnote 20260101-100004-uncounted "Uncounted" new 1; grep -v '^Seen: 1$' "$T/fbp/seed/20260101-100004-uncounted.md" > "$T/fbp/x"; mv "$T/fbp/x" "$T/fbp/seed/20260101-100004-uncounted.md"
  printf 'what I ran\n\nwhat it printed\n\n\n' > "$T/fbp/details.md"; : > "$T/fbp/empty.md"
  FSTAMP='s/[0-9]\{8\}-[0-9]\{6\}-/STAMP-/g; s/[0-9]\{4\}-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9] UTC/WHEN/g'
  # FLOCKED: the notes' folder can't be written in for the run. FNODIR: nor made.
  FLOCKED=""; FNODIR=""
  # brun <helper> <mode> <stdin's file> <feedback add's arguments>: feedback add with
  # that helper, or with the Bash alone when none is named, on a fresh copy of the
  # seeded notes. Prints stdout, the exit code and the notes. stderr goes to $T/fb.err.
  brun() {
    local go="$1" mode="$2" in="$3" no=1 f d="$T/fbp/state/llm-wiki/feedback"
    shift 3
    [ -z "$go" ] || no=""
    chmod -R u+w "$T/fbp/state" 2>/dev/null; rm -rf "$T/fbp/state"; mkdir -p "$T/fbp/state/llm-wiki"
    [ -n "$FNODIR" ] || cp -Rp "$T/fbp/seed" "$d"
    [ -z "$FLOCKED" ] || chmod 555 "$d"
    [ -z "$FNODIR" ] || chmod 555 "$T/fbp/state/llm-wiki"
    (cd "$T" && XDG_STATE_HOME="$T/fbp/state" XDG_CONFIG_HOME="$T/fbp/$mode" LLM_WIKI_NO_GO="$no" LLM_WIKI_GO="$go" "$W" feedback add "$@" < "$in" 2>"$T/fb.raw-err"; echo "exit $?") | sed "$FSTAMP"
    sed "$FSTAMP" "$T/fb.raw-err" > "$T/fb.err"
    for f in "$d"/* "$d"/.[!.]*; do
      [ -e "$f" ] || continue
      printf -- '--- %s %s\n' "$(printf '%s' "${f##*/}" | sed "$FSTAMP")" "$(ls -l "$f" | cut -c1-10)"
      sed "$FSTAMP" "$f"
    done
  }
  # bsame <check> <helper|bash> <mode> <stdin's file> <arguments>: both say and keep
  # the same, and with the helper on, the answer came from the one named.
  bsame() {
    local name="$1" who="$2" a b ran
    shift 2
    : > "$T/fb-ran"
    a="$(brun "" "$@")"
    cp "$T/fb.err" "$T/fb.a"
    b="$(brun "$T/bin/fb-spy" "$@")"
    ran="$(cat "$T/fb-ran")"
    case "$who:$ran" in helper:0) ran=helper ;; helper:* | bash: | bash:0) ran="not the $who (the helper's feedback-add ended: ${ran:-never ran})" ;; *) ran=bash ;; esac
    if [ "$a" = "$b" ] && cmp -s "$T/fb.a" "$T/fb.err" && [ "$ran" = "$who" ]; then
      ok "$name"
    else
      bad "$name" "$(printf 'answered by: %s\n%s' "$ran" "$(diff <(printf '%s\n' "$a"; cat "$T/fb.a") <(printf '%s\n' "$b"; cat "$T/fb.err"))")"
    fi
  }
  bsame "feedback add, helper and Bash: a note, with its details on stdin" helper share "$T/fbp/details.md" friction "Sync: says 'name a wiki' & no more!" --agent "Smoke, a model"
  out="$(brun "$T/bin/fb-spy" share "$T/fbp/details.md" friction "Sync: says 'name a wiki' & no more!" --agent "Smoke, a model")"
  case "$out" in "feedback: saved STAMP-sync-says-name-a-wiki-no-more. The user can file it with: wiki feedback send"*"exit 0"*"--- STAMP-sync-says-name-a-wiki-no-more.md -rw-r--r--"*"Kind: friction"*"Agent: Smoke, a model"*"Captured: WHEN"*"Seen: 1"*"what it printed") ok "and the helper's note has what the Bash's has, without the blank lines at the end" ;; *) bad "and the helper's note has what the Bash's has, without the blank lines at the end" "$out" ;; esac
  bsame "with notes kept and not shared, which it doesn't offer to file" helper notes "$T/fbp/details.md" idea "an idea"
  bsame "with feedback off, or set to a word it doesn't know" helper off "$T/fbp/details.md" idea "an idea"
  bsame "details in a file, and no agent" helper share /dev/null docs "from a file" --file "$T/fbp/details.md"
  bsame "a summary longer than a name, cut at a dash" helper share "$T/fbp/details.md" bug "a summary that runs on well past what a name holds"
  bsame "a summary with no letters or digits" helper share "$T/fbp/details.md" bug "?!"
  bsame "a summary with letters that aren't ASCII" helper share "$T/fbp/details.md" bug "$(printf 'Caf\303\251 \303\211COLE caf\351')"
  bsame "the same summary again, whatever its case, is seen again" helper share "$T/fbp/details.md" bug "KNOWN thing" --agent "Another, model"
  out="$(brun "$T/bin/fb-spy" share "$T/fbp/details.md" bug "KNOWN thing")"
  case "$out" in "feedback: seen again, STAMP-known-thing (seen 3 times)"*"Seen: 3"*"Seen: 3"*"## Seen again WHEN"*"what it printed"*) ok "and the helper counts it in the note it was in" ;; *) bad "and the helper counts it in the note it was in" "$out" ;; esac
  bsame "a note whose only count is a line of its details, which the Bash answers" bash share "$T/fbp/details.md" bug "uncounted"
  bsame "a dismissed note's summary starts a new note" helper share "$T/fbp/details.md" bug "Old thing"
  bsame "two kinds in one word, which the Bash takes" helper share "$T/fbp/details.md" "bug friction" "two kinds"
  bsame "feedback add refuses, the same from both: nothing at all" helper share "$T/fbp/details.md"
  bsame "a kind and no summary" helper share "$T/fbp/details.md" bug
  bsame "a kind it doesn't have" helper share "$T/fbp/details.md" oops "a summary"
  bsame "an empty summary" helper share "$T/fbp/details.md" bug ""
  bsame "an option it doesn't have" helper share "$T/fbp/details.md" bug "a summary" --nope x
  bsame "--agent with nothing after it" helper share "$T/fbp/details.md" bug "a summary" --agent
  bsame "no details" helper share /dev/null bug "a summary"
  bsame "details that are only line breaks" helper share "$T/fbp/empty.md" bug "a summary" --file "$T/fbp/empty.md"
  bsame "a details file that isn't there, which the Bash answers" bash share /dev/null bug "a summary" --file "$T/fbp/gone.md"
  bsame "a summary with a line break, which the Bash answers" bash share "$T/fbp/details.md" bug "two
lines"
  bsame "a count the shell reads its own way, which the Bash answers" bash share "$T/fbp/details.md" bug "odd count"
  bsame "a note that doesn't end its last line, which the Bash answers" bash share "$T/fbp/details.md" bug "open end"
  if [ "$(id -u)" != 0 ]; then
    FLOCKED=1
    bsame "a folder of notes it can't write in, which the Bash answers" bash share "$T/fbp/details.md" bug "locked out"
    FLOCKED=""; FNODIR=1
    bsame "and one it can't make" helper share "$T/fbp/details.md" bug "no folder"
    FNODIR=""
  else
    skipped "feedback add where it can't write (running as root)"
  fi
  [ "$(brun "$T/bin/broken-helper" share "$T/fbp/details.md" bug "fallback")" = "$(brun "" share "$T/fbp/details.md" bug "fallback")" ] && ok "a helper that fails leaves feedback add to the Bash, with the details still on stdin" || bad "a helper that fails leaves feedback add to the Bash, with the details still on stdin"
  chmod -R u+w "$T/fbp" 2>/dev/null; rm -rf "$T/fbp" "$T/bin/fb-spy" "$T"/fb.err "$T"/fb.a "$T"/fb.raw-err "$T/fb-ran"
else
  skipped "the Go helper against the Bash for feedback add (go isn't installed)"
fi
rm -rf "$FB" "$HOME/.config/llm-wiki/feedback" "$T/bin/gh" "$T/gh.log" "$T/gh.body" "$T/fb.md"
fi

if section "MCP server"; then
[ -x "$T/bin/llm-wiki" ] || ! command -v go >/dev/null 2>&1 || build_helper >/dev/null 2>&1
# Two servers answer `wiki mcp`: the compiled helper's when there is one, and
# mcp/server.py. MCP_GO names the helper to serve, and with none the Python does.
MCP_GO=""
mcp_serve() { if [ -n "$MCP_GO" ]; then LLM_WIKI_NO_GO="" LLM_WIKI_GO="$MCP_GO" "$W" mcp; else LLM_WIKI_NO_GO=1 "$W" mcp; fi; }
# mcp_call <tool> <json arguments>: the tool's text, with ERROR: in front if it failed.
mcp_call() {
  local a="${2:-}"
  [ -n "$a" ] || a='{}'
  printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"%s","arguments":%s}}\n' "$1" "$a" | mcp_serve \
    | python3 -c 'import json,sys; r=json.loads(sys.stdin.readline())["result"]; print(("ERROR: " if r.get("isError") else "")+r["content"][0]["text"])'
}
# mcp_tools <who> <slug>: the protocol and every tool, from the server MCP_GO chose.
mcp_tools() {
  local who="$1" slug="$2" out SC
  out="$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}' '{"jsonrpc":"2.0","method":"notifications/initialized"}' 'not json' '{"jsonrpc":"2.0","id":2,"method":"ping"}' '{"jsonrpc":"2.0","id":3,"method":"nope"}' '{"jsonrpc":"2.0","id":4,"method":"tools/list"}' | mcp_serve)"
  check "$who: initialize answers in the client's protocol version, with instructions" python3 -c "import json,sys; r=json.loads(sys.argv[1].splitlines()[0])['result']; assert r['protocolVersion']=='2025-03-26' and 'wiki_start' in r['instructions'] and 'tools' in r['capabilities']" "$out"
  check "$who: a notification gets no reply, bad JSON a parse error, and the server carries on" python3 -c "import json,sys; l=[json.loads(x) for x in sys.argv[1].splitlines()]; assert len(l)==5 and l[1]['error']['code']==-32700 and l[2]['id']==2 and l[3]['error']['code']==-32601" "$out"
  check "$who: it lists its tools, each with a schema" python3 -c "import json,sys; t=json.loads(sys.argv[1].splitlines()[4])['result']['tools']; assert [x['name'] for x in t]==['wiki_list','wiki_start','wiki_search','wiki_read','wiki_status','wiki_capture','wiki_feedback'] and all(x['inputSchema']['type']=='object' for x in t)" "$out"
  check "$who: it tells chat agents the wikis come before memory and past chats" python3 -c "import json,sys; l=sys.argv[1].splitlines(); r=json.loads(l[0])['result']['instructions']; t={x['name']:x['description'] for x in json.loads(l[4])['result']['tools']}; assert 'before memory' in r and 'before memory' in t['wiki_start'] and 'before memory' in t['wiki_search']" "$out"
  expect "$who: wiki_list lists the wikis and what they cover" "covers: api web" mcp_call wiki_list
  expect "$who: wiki_start finds the project's wiki" "/demo, for the repository web" mcp_call wiki_start '{"repository":"web"}'
  expect "$who: with no project, the shared wiki" "Not in a repository" mcp_call wiki_start
  expect "$who: wiki_search searches" "Deploy flow" mcp_call wiki_search '{"word":"canary"}'
  expect "$who: wiki_read defaults to the index" "# Index" mcp_call wiki_read '{"wiki":"demo"}'
  expect "$who: and reads a page" "blue-green" mcp_call wiki_read '{"wiki":"demo","path":"index.md"}'
  expect "$who: wiki_status shows what's due" "HANDBOOK" mcp_call wiki_status
  expect "$who: a path out of the wiki is refused" "ERROR: that path is outside the wiki" mcp_call wiki_read '{"wiki":"demo","path":"../global/index.md"}'
  expect "$who: so is an absolute one" "ERROR: give a path inside the wiki" mcp_call wiki_read "{\"wiki\":\"demo\",\"path\":\"$HOME/.gitconfig\"}"
  ln -s "$T/secret.md" "$WIKIS_DIR/demo/wiki/link.md"; echo "very secret" > "$T/secret.md"
  expect "$who: and a link that leads out" "ERROR: that path is outside the wiki" mcp_call wiki_read '{"wiki":"demo","path":"wiki/link.md"}'
  rm -f "$WIKIS_DIR/demo/wiki/link.md" "$T/secret.md"
  expect "$who: hidden folders aren't readable" "ERROR: that path is outside the wiki" mcp_call wiki_read '{"wiki":"demo","path":".compile-lock.md"}'
  expect "$who: only text files are" "ERROR: only .md, .csv and .txt" mcp_call wiki_read '{"wiki":"demo","path":"data/x.sqlite"}'
  expect "$who: a wiki name can't be a path" "ERROR: that isn't a wiki name" mcp_call wiki_read '{"wiki":"../demo"}'
  expect "$who: wiki_capture refuses a bad slug" "ERROR: the slug" mcp_call wiki_capture '{"wiki":"demo","slug":"../x","note":"n"}'
  expect "$who: and an empty note" "ERROR: the note is empty" mcp_call wiki_capture '{"wiki":"demo","slug":"x","note":" "}'
  expect "$who: wiki_capture saves and pushes" "Pushed." mcp_call wiki_capture "{\"wiki\":\"demo\",\"slug\":\"$slug\",\"note\":\"We chose Postgres, in a chat.\"}"
  # Chat can't append to stats.csv, so the server logs its lookups.
  printf 'one\n' > "$WIKIS_DIR/demo/wiki/mcp-one.md"; printf 'two\n' > "$WIKIS_DIR/demo/wiki/mcp-two.md"
  SC="$WIKIS_DIR/stats.csv"; cp "$SC" "$T/stats.bak" 2>/dev/null || true; rm -f "$SC"
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"wiki_read","arguments":{"wiki":"demo"}}}' | mcp_serve >/dev/null
  check "$who: reading the index isn't a lookup that answered anything" test ! -e "$SC"
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"wiki_read","arguments":{"wiki":"demo","path":"wiki/mcp-one.md"}}}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"wiki_read","arguments":{"wiki":"demo","path":"wiki/mcp-two.md"}}}' | mcp_serve >/dev/null
  check "$who: reading pages logs one hit, however many pages" bash -c "[ \"\$(grep -c ',demo,hit$' '$SC')\" = 1 ] && head -n 1 '$SC' | grep -qx 'date,wiki,result'"
  mcp_call wiki_search '{"word":"zzzabsent"}' >/dev/null
  check "$who: a search that finds nothing is logged, once" bash -c "[ \"\$(grep -c ',global,search-none,zzzabsent$' '$SC')\" = 1 ] && [ \"\$(grep -c search- '$SC')\" = 1 ]"
  rm -f "$SC" "$WIKIS_DIR/demo/wiki/mcp-one.md" "$WIKIS_DIR/demo/wiki/mcp-two.md"; [ ! -f "$T/stats.bak" ] || mv "$T/stats.bak" "$SC"
  check "$who: the note is a normal capture" bash -c "grep -q '^Captured: ' '$WIKIS_DIR'/demo/raw/*-$slug.md && grep -q 'We chose Postgres' '$WIKIS_DIR'/demo/raw/*-$slug.md"
  check "$who: and it reached the remote" bash -c "git --git-dir='$T/remote.git' log -1 --format=%s | grep -q 'capture $slug'"
  # sync also ends well with nothing pushed, and a capture then isn't called pushed:
  # with no remote, and in a folder that isn't in a repository the wikis own.
  git -C "$WIKIS_DIR" remote remove origin
  expect "$who: with no remote, a capture is saved and not called pushed" "but not pushed: no remote, so nothing to pull or push" mcp_call wiki_capture "{\"wiki\":\"demo\",\"slug\":\"$slug-no-remote\",\"note\":\"n\"}"
  git -C "$WIKIS_DIR" remote add origin "$T/remote.git"
  mv "$WIKIS_DIR/WIKIS.md" "$T/WIKIS.aside"
  expect "$who: nor in a folder the wikis don't own" "Saved on this machine, but not pushed: " mcp_call wiki_capture "{\"wiki\":\"demo\",\"slug\":\"$slug-unowned\",\"note\":\"n\"}"
  mv "$T/WIKIS.aside" "$WIKIS_DIR/WIKIS.md"
  rm -f "$WIKIS_DIR"/demo/raw/*-"$slug"-no-remote.md "$WIKIS_DIR"/demo/raw/*-"$slug"-unowned.md; "$W" sync demo >/dev/null 2>&1
  check "$who: and the remote is back in step after those" bash -c "[ \"\$(git -C '$WIKIS_DIR' rev-parse HEAD)\" = \"\$(git --git-dir='$T/remote.git' rev-parse HEAD)\" ]"
  expect "$who: wiki_feedback follows the setting" "feedback is off" mcp_call wiki_feedback '{"kind":"idea","summary":"s","details":"d"}'
}
mcp_tools "the Python" from-chat
if [ -x "$T/bin/llm-wiki" ]; then
  # Which server answered can't be told from a reply, so the spy notes what it was run for.
  : > "$T/helper-ran"; MCP_GO="$T/bin/spy-helper"
  mcp_tools "the helper" from-chat-again
  check "wiki mcp is served by the compiled helper when there is one" grep -qx mcp "$T/helper-ran"
  : > "$T/helper-ran"
  mcp_call wiki_search '{"word":"canary"}' >/dev/null; mcp_call wiki_start '{"repository":"web"}' >/dev/null
  check "and the helper's server searches and routes itself, with no wiki.sh find, which, capture or feedback add" bash -c "! grep -q -x -e find -e which -e capture -e feedback-add '$T/helper-ran'"
  # The helper's server stays up whatever a line holds. Python reads a line that isn't
  # UTF-8 in the C locale and stops at one in a UTF-8 locale.
  U8="$(locale -a 2>/dev/null | grep -i -E '^(en_US|C)\.utf-?8$' | head -n 1)"
  out="$(printf '{"jsonrpc":"2.0","id":1,"method":"ping","x":"\377"}\n{"jsonrpc":"2.0","id":2,"method":"ping"}\n' | LC_ALL="${U8:-C}" mcp_serve 2>&1)"
  check "a line that isn't UTF-8 is a parse error to the helper's server, and it carries on" python3 -c "import json,sys; l=[json.loads(x) for x in sys.argv[1].splitlines()]; assert len(l)==2 and l[0]['error']['code']==-32700 and l[0]['id'] is None and l[1]=={'jsonrpc':'2.0','id':2,'result':{}}, l" "$out"
  # Listing, reading and searching need no Python at all with the helper.
  mkdir -p "$T/nopy"; printf '#!/bin/sh\necho "$*" >> "%s"\nexit 127\n' "$T/python-ran" > "$T/nopy/python3"; chmod +x "$T/nopy/python3"; rm -f "$T/python-ran"
  out="$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"wiki_list"}}' '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"wiki_read","arguments":{"wiki":"demo"}}}' '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"wiki_search","arguments":{"word":"canary"}}}' | PATH="$T/nopy:$PATH" mcp_serve 2>&1)"
  case "$out" in *'"id":5,'*'Deploy flow'*) [ ! -e "$T/python-ran" ] && ok "the helper's server lists, reads and searches without running python3" || bad "the helper's server lists, reads and searches without running python3" "python3 was run: $(cat "$T/python-ran")" ;; *) bad "the helper's server lists, reads and searches without running python3" "$out" ;; esac
  rm -rf "$T/nopy" "$T/python-ran"
  # A helper is chosen once, when the server starts, and only one that speaks the protocol.
  : > "$T/helper-ran"; MCP_GO="$T/bin/stale-helper"
  expect "a helper built for another protocol is passed over, and the Python serves" "covers: api web" mcp_call wiki_list
  MCP_GO=""
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"ping"}' | LLM_WIKI_NO_GO=1 LLM_WIKI_GO="$T/bin/spy-helper" "$W" mcp >/dev/null
  check "and LLM_WIKI_NO_GO leaves a good helper out of it" test ! -s "$T/helper-ran"
else
  skipped "the MCP server from the compiled helper (go isn't installed)"
fi
expect "mcp --print gives the config entry" '"args"' "$W" mcp --print
D="$T/desktop"
lacks "without the desktop app, setup --list says nothing about Chat" "chat   " env LLM_WIKI_DESKTOP_DIR="$D" "$W" setup --list
mkdir -p "$D" && printf '{"preferences":{"x":1},"mcpServers":{"other":{"command":"o"}}}\n' > "$D/claude_desktop_config.json"
expect "with it, setup --list shows the server missing" "server missing" env LLM_WIKI_DESKTOP_DIR="$D" "$W" setup --list
# The app rewrites its config as it runs, so setup must write only once it's closed.
sleep 4242 & FAKE=$!
out="$(LLM_WIKI_DESKTOP_DIR="$D" LLM_WIKI_DESKTOP_PROC="^sleep 4242" "$W" setup chat --yes </dev/null 2>&1)" && bad "--yes refuses while the app is open" "$out" || case "$out" in *"nothing was changed"*"quit the app"*) ok "--yes refuses while the app is open" ;; *) bad "--yes refuses while the app is open" "$out" ;; esac
kill "$FAKE" 2>/dev/null; wait "$FAKE" 2>/dev/null || true
expect "and changes nothing" "server missing" env LLM_WIKI_DESKTOP_DIR="$D" "$W" setup --list
# An agent runs inside the app, so the app is its ancestor.
printf '#!/bin/sh\nLLM_WIKI_DESKTOP_DIR="%s" LLM_WIKI_DESKTOP_PROC="fake-app-4242" "%s" setup chat --yes </dev/null\nexit 0\n' "$D" "$W" > "$T/fake-app-4242"; chmod +x "$T/fake-app-4242"
expect "it sees the app when running inside it" "nothing was changed" "$T/fake-app-4242"
rm -f "$T/fake-app-4242"
sleep 4242 & FAKE=$!
( sleep 2; kill "$FAKE" 2>/dev/null ) &
out="$(printf 'y\n' | LLM_WIKI_TEST_TTY=1 LLM_WIKI_DESKTOP_DIR="$D" LLM_WIKI_DESKTOP_PROC="^sleep 4242" "$W" setup chat 2>&1)"
wait "$FAKE" 2>/dev/null || true
case "$out" in *"Quit the Claude app now"*"added. Open the Claude app"*) ok "asked with the app open, setup waits until it's closed, then writes" ;; *) bad "asked with the app open, setup waits until it's closed, then writes" "$out" ;; esac
check "keeping everything else in the config" python3 -c "import json,sys; c=json.load(open(sys.argv[1])); assert c['preferences']=={'x':1} and c['mcpServers']['other']=={'command':'o'} and c['mcpServers']['llm-wiki']['args']==['mcp']" "$D/claude_desktop_config.json"
case "$out" in *"personal preferences"*"Check them before memory or past chats"*) ok "and gives the line for the user's profile preferences" ;; *) bad "and gives the line for the user's profile preferences" "$out" ;; esac
check "with a backup beside it" bash -c "ls '$D' | grep -q 'claude_desktop_config.json.bak-llm-wiki-'"
printf '{"mcpServers":{}}\n' > "$D/claude_desktop_config.json"
expect "--yes adds it with no terminal when the app is closed" "added. Open the Claude app" env LLM_WIKI_DESKTOP_DIR="$D" LLM_WIKI_DESKTOP_PROC="^no such process" "$W" setup chat --yes
expect "--yes works only for chat" "--yes works only with" "$W" setup git --yes
expect "and setup --list shows it current" "server current" env LLM_WIKI_DESKTOP_DIR="$D" "$W" setup --list
if [ "$(id -u)" != 0 ]; then
  chmod 000 "$D/claude_desktop_config.json"
  expect "a desktop config it can't read is unknown, not missing" "chat                unknown, can't read" env LLM_WIKI_DESKTOP_DIR="$D" "$W" setup --list
  expect "and setup chat changes nothing" "Nothing was changed" env LLM_WIKI_DESKTOP_DIR="$D" LLM_WIKI_TEST_TTY=1 "$W" setup chat
  chmod 644 "$D/claude_desktop_config.json"
else
  skipped "a desktop config that can't be read (root can read anything)"
fi
rm -rf "$D"
fi

if section "Compiled without summary pages (v24)"; then
"$W" new v24 >/dev/null 2>&1
V="$WIKIS_DIR/v24"
for n in a b c d; do printf 'Captured: 2026-10-29\n\nNote %s.\n' "$n" > "$V/raw/2026-10-29-000001-$n.md"; done
expect "new notes wait" "raw/2026-10-29-000001-d.md" "$W" pending v24
"$W" log v24 ingest "Note a" --source raw/2026-10-29-000001-a.md --updated wiki/x.md >/dev/null
check "log --source writes the source line" grep -q '^- source: raw/2026-10-29-000001-a.md$' "$V/log.md"
mkdir -p "$V/wiki/concepts" && printf -- '---\ntitle: X\nsummary: x\nsources: [raw/2026-10-29-000001-b.md]\nupdated: 2026-10-29\nverified: 2026-10-29\n---\n\nBody.\n' > "$V/wiki/concepts/x.md"
mkdir -p "$V/wiki/sources" && printf -- '---\ntitle: c\n---\n' > "$V/wiki/sources/2026-10-29-000001-c.md"
out="$("$W" pending v24 2>&1)"
case "$out" in *"000001-a.md"*) bad "a note named in a log entry is compiled" "$out" ;; *) ok "a note named in a log entry is compiled" ;; esac
case "$out" in *"000001-b.md"*) bad "a note a page lists in sources: is compiled" "$out" ;; *) ok "a note a page lists in sources: is compiled" ;; esac
case "$out" in *"000001-c.md"*) bad "a note with a summary page from before v24 is compiled" "$out" ;; *) ok "a note with a summary page from before v24 is compiled" ;; esac
case "$out" in *"000001-d.md"*) ok "and an uncompiled note still waits" ;; *) bad "and an uncompiled note still waits" "$out" ;; esac
expect "status counts the same one note" "v24 v$TV 1 free" bash -c "'$W' status | grep '^v24 ' | tr -s ' '"
expect "lint agrees: one note waiting" "notes waiting to be compiled (1)" "$W" lint v24
fi
if section "Claude Code permissions"; then
mkdir -p "$HOME/.claude" && printf '{"permissions":{"allow":["Bash(ls *)"]},"theme":"dark"}\n' > "$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude/plugins/data/llm-wiki-llm-wiki/bin" && printf '#!/bin/sh\n' > "$HOME/.claude/plugins/data/llm-wiki-llm-wiki/bin/wiki" && chmod +x "$HOME/.claude/plugins/data/llm-wiki-llm-wiki/bin/wiki"
out="$("$W" permissions 2>&1)"
for want in '"Bash(wiki sync *)",' "wiki.sh sync *)" "wiki.sh capture *)" "data/llm-wiki-llm-wiki/bin/wiki sync *)" "missing from ~/.claude/settings.json"; do
  case "$out" in *"$want"*) ok "permissions prints: $want" ;; *) bad "permissions prints: $want" "$out" ;; esac
done
expect "setup --list counts the missing rules" "allow rule(s) missing" "$W" setup --list
"$W" permissions 2>/dev/null | sed 's/,$//' | python3 -c 'import json,sys; p=sys.argv[1]; s=json.load(open(p)); s["permissions"]["allow"]+= [json.loads(l) for l in sys.stdin.read().splitlines()]; json.dump(s,open(p,"w"))' "$HOME/.claude/settings.json"
expect "once present, setup --list says the commands are allowed" "wiki commands allowed" "$W" setup --list
check "and other settings were kept" python3 -c "import json,sys; s=json.load(open(sys.argv[1])); assert s['theme']=='dark' and 'Bash(ls *)' in s['permissions']['allow']" "$HOME/.claude/settings.json"
# Settings this shell can't read, as in an agent's sandbox, used to count as every rule
# missing, and as a new setting to ask about.
if [ "$(id -u)" != 0 ]; then
  todo_was="$("$W" status 2>&1 | grep 'new setting' || true)"
  chmod 000 "$HOME/.claude/settings.json"
  out="$("$W" setup --list 2>&1)"
  case "$out" in *"permissions  "*"unknown, can't read ~/.claude/settings.json"*) ok "setup --list says when it can't read the settings" ;; *) bad "setup --list says when it can't read the settings" "$out" ;; esac
  case "$out" in *"allow rule(s) missing"*) bad "instead of calling every rule missing" "$out" ;; *) ok "instead of calling every rule missing" ;; esac
  expect "permissions says it can't tell" "no telling which of these it has" "$W" permissions
  now="$("$W" status 2>&1 | grep 'new setting' || true)"
  [ "$now" = "$todo_was" ] && ok "and status doesn't count them as a new setting" || bad "and status doesn't count them as a new setting" "was: $todo_was now: $now"
  chmod 644 "$HOME/.claude/settings.json"
else
  skipped "settings that can't be read (root can read anything)"
fi
rm -f "$HOME/.claude/settings.json"
fi

if section "Collections"; then
CW="$T/wikis-work"
WIKIS_DIR="$CW" "$W" init >/dev/null 2>&1
WIKIS_DIR="$CW" "$W" new jobapp >/dev/null 2>&1
mkdir -p "$HOME/.config/llm-wiki"
printf '# test\nwork %s %s/code/workrepos/*,*gitlab.example.com:acme/*\n' "$CW" "$T" > "$HOME/.config/llm-wiki/collections"
RA="$T/code/workrepos/jobapp"; RB="$T/elsewhere/svc"; RC="$T/elsewhere/hobby"
for r in "$RA" "$RB" "$RC"; do mkdir -p "$r" && git -C "$r" init -q; done
git -C "$RB" remote add origin git@gitlab.example.com:acme/svc.git
nw() { (cd "$1" && env -u WIKIS_DIR "$W" "${@:2}"); }
expect "a repository under a folder rule goes to that collection" "$CW" nw "$RA" __collection
expect "a repository whose remote matches goes to that collection" "$CW" nw "$RB" __collection
expect "any other repository stays in the default" "$HOME/wikis" nw "$RC" __collection
expect "collections lists them with their rules" "work       $(printf '%s' "$CW" | sed "s#^$HOME#~#")  matches:" nw "$RC" collections
expect "start in a work repository finds its wiki in the work collection" "wiki: $(printf '%s' "$CW" | sed "s#^$HOME#~#")/jobapp" nw "$RA" start
expect "--collection picks one by name" "jobapp" nw "$RC" status --collection work
refuse "--collection with an unknown name fails" nw "$RC" status --collection nope
expect "the Claude Code hook routes the session to its collection" "/jobapp, for the repository jobapp" bash -c "$(declare -f hook context); T='$T' REPO='$REPO'; unset WIKIS_DIR; hook '$RA' | context"
expect "WIKIS_DIR in the environment still wins" "$WIKIS_DIR" bash -c "cd '$RA' && WIKIS_DIR='$WIKIS_DIR' '$W' __collection"
check "status in the default mentions the other collection" bash -c "cd '$RC' && env -u WIKIS_DIR WIKIS_DIR='$WIKIS_DIR' '$W' status | grep -q 'also:    collection work'"

# which with no name: the repository here, from its remote or its folder.
expect "which with no name covers the repository here" "/jobapp" nw "$RA" which
RN="$T/elsewhere/renamed-checkout"; mkdir -p "$RN"; git -C "$RN" init -q
git -C "$RN" remote add origin git@gitlab.example.com:acme/jobapp.git
expect "and goes by the remote, not the folder" "/jobapp" nw "$RN" which
expect "outside a repository it asks for a name" "which needs a repository name" nw "$T" which

# wiki_start finds a wiki in any collection, wherever they run from.
mkdir -p "$CW/jobapp/wiki"; printf -- '---\ntitle: P\n---\nA page.\n' > "$CW/jobapp/wiki/job-page.md"
git -C "$RA" commit -q --allow-empty -m one; git -C "$RN" commit -q --allow-empty -m one
[ -d "$HOME/wikis/global" ] || WIKIS_DIR="$HOME/wikis" "$W" init >/dev/null 2>&1
# mcp_any <wiki.sh args for one call's arguments>: like mcp_call, with every collection in reach.
mcp_any() {
  local a="${2:-}"
  [ -n "$a" ] || a='{}'
  printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"%s","arguments":%s}}\n' "$1" "$a" | (cd "$T" && env -u WIKIS_DIR "$W" mcp) \
    | python3 -c 'import json,sys; r=json.loads(sys.stdin.readline())["result"]; print(("ERROR: " if r.get("isError") else "")+r["content"][0]["text"])'
}
expect "wiki_start finds a repository's wiki in any collection" "/jobapp, for the repository jobapp" mcp_any wiki_start '{"repository":"jobapp"}'
expect "a repository nobody covers gets the default's shared wiki" "$(printf '%s' "$HOME/wikis/global" | sed "s#^$HOME#~#"), for the repository nosuchrepo" mcp_any wiki_start '{"repository":"nosuchrepo"}'
expect "a named collection still wins" "No wiki covers jobapp" mcp_any wiki_start '{"repository":"jobapp","collection":"default"}'
# A hit in one collection doesn't hide a hit in another with the same wiki name.
printf 'x\n' > "$HOME/wikis/global/wiki/hit.md"; printf 'x\n' > "$CW/global/wiki/hit.md"; rm -f "$HOME/wikis/stats.csv" "$CW/stats.csv"
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"wiki_read","arguments":{"wiki":"global","path":"wiki/hit.md","collection":"default"}}}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"wiki_read","arguments":{"wiki":"global","path":"wiki/hit.md","collection":"work"}}}' | (cd "$T" && env -u WIKIS_DIR "$W" mcp) >/dev/null
check "lookups count per collection" bash -c "grep -q ',global,hit$' '$HOME/wikis/stats.csv' && grep -q ',global,hit$' '$CW/stats.csv'"
rm -f "$HOME/wikis/global/wiki/hit.md" "$CW/global/wiki/hit.md" "$HOME/wikis/stats.csv"

# which, from the compiled helper and from the Bash: the same stdout, stderr and exit
# code. The weekly report's section builds the helper; a part without it builds it here.
[ -x "$T/bin/llm-wiki" ] || ! command -v go >/dev/null 2>&1 || build_helper >/dev/null 2>&1
if [ -x "$T/bin/llm-wiki" ]; then
  # A wrapper notes how the helper's which ended, so a check can tell who answered.
  printf '#!/bin/sh\n[ "$1" = which ] || exec "%s" "$@"\n"%s" "$@"\nrc=$?\necho "$rc" >> "%s"\nexit $rc\n' "$T/bin/llm-wiki" "$T/bin/llm-wiki" "$T/which-ran" > "$T/bin/which-spy"
  chmod +x "$T/bin/which-spy"
  # wsame <check> <helper|bash> <folder> [which's arguments]: both print the same there,
  # and with the helper on, the answer came from the one named.
  wsame() {
    local name="$1" who="$2" dir="$3" a b ran
    shift 3
    : > "$T/which-ran"
    a="$(cd "$dir" && env -u WIKIS_DIR LLM_WIKI_NO_GO=1 "$W" which ${1+"$@"} 2>"$T/which.a"; echo "exit $?")"
    b="$(cd "$dir" && env -u WIKIS_DIR LLM_WIKI_NO_GO= LLM_WIKI_GO="$T/bin/which-spy" "$W" which ${1+"$@"} 2>"$T/which.b"; echo "exit $?")"
    ran="$(cat "$T/which-ran")"
    case "$who:$ran" in helper:0) ran=helper ;; helper:* | bash: | bash:0) ran="not the $who (the helper's which ended: ${ran:-never ran})" ;; *) ran=bash ;; esac
    if [ "$a" = "$b" ] && cmp -s "$T/which.a" "$T/which.b" && [ "$ran" = "$who" ]; then
      ok "$name"
    else
      bad "$name" "$(printf 'answered by: %s\nBash: %s\n%s\nhelper: %s\n%s' "$ran" "$a" "$(cat "$T/which.a")" "$b" "$(cat "$T/which.b")")"
    fi
  }
  # wgo <folder> [which's arguments]: which with the helper, both streams.
  wgo() { (cd "$1" && shift && env -u WIKIS_DIR LLM_WIKI_NO_GO= LLM_WIKI_GO="$T/bin/llm-wiki" "$W" which ${1+"$@"} 2>&1); }
  # wno <folder> [which's arguments]: which with the Bash alone, both streams.
  wno() { (cd "$1" && shift && env -u WIKIS_DIR LLM_WIKI_NO_GO=1 "$W" which ${1+"$@"} 2>&1); }
  # fake_wiki <folder> [index line]: the two files that make a folder a wiki.
  fake_wiki() { mkdir -p "$1" && printf '# Handbook\n' > "$1/AGENTS.md" && printf '# Index\n%s\n' "${2:-}" > "$1/index.md"; }
  CWT="$(printf '%s' "$CW" | sed "s#^$HOME#~#")"
  WIKIS_DIR="$CW" "$W" cover jobapp jobapp-web jobapp-api >/dev/null 2>&1
  fake_wiki "$CW/payroll"
  RW="$T/code/workrepos/jobapp-web"; mkdir -p "$RW/src"; git -C "$RW" init -q
  for w in shop shop-web shop-api shop-admin shop-docs; do fake_wiki "$HOME/wikis/$w"; done
  fake_wiki "$HOME/wikis/billing" "- [Ledger](wiki/ledger.md): talks to Ledger-Core nightly"

  wsame "which, helper and Bash: a wiki named after the repository" helper "$RC" jobapp --collection work
  expect "and the helper prints its folder" "$CWT/jobapp" wgo "$RC" jobapp --collection work
  wsame "which, helper and Bash: a repository one wiki's repos.md lists among several" helper "$RC" jobapp-api --collection work
  expect "and the helper prints that wiki" "$CWT/jobapp" wgo "$RC" jobapp-api --collection work
  wsame "which, helper and Bash: no name, in a subfolder of a listed repository in a second collection" helper "$RW/src"
  expect "and the helper finds the second collection's wiki" "$CWT/jobapp" wgo "$RW/src"
  wsame "which, helper and Bash: no name, in a renamed folder, matched by its remote URL" helper "$RN"
  expect "and the helper goes by the remote" "$CWT/jobapp" wgo "$RN"
  wsame "which, helper and Bash: no name, in a repository no wiki covers" helper "$RC"
  expect "and the helper says so" "no wiki covers hobby" wgo "$RC"
  wsame "which, helper and Bash: no name, routed by remote to a collection with no wiki for it" helper "$RB"
  wsame "which, helper and Bash: a name no wiki covers or comes close to" helper "$RC" zzz-unknown
  wsame "which, helper and Bash: close matches by a shared word" helper "$RC" shop-mobile
  out="$(wgo "$RC" shop-mobile)"
  case "$out" in *"Close matches: shop shop-admin shop-api shop-docs"$'\n'"If shop-mobile belongs to one of them: "*" cover <wiki> shop-mobile"*) ok "and the helper lists four of the five, sorted" ;; *) bad "and the helper lists four of the five, sorted" "$out" ;; esac
  wsame "which, helper and Bash: a close match by a mention in an index, whatever the case" helper "$RC" LEDGER-core
  expect "and the helper names the wiki whose index has it" "Close matches: billing" wgo "$RC" LEDGER-core
  refuse "and the helper's miss still exits 1" wgo "$RC" zzz-unknown
  [ -z "$(cd "$RC" && env -u WIKIS_DIR LLM_WIKI_NO_GO= LLM_WIKI_GO="$T/bin/llm-wiki" "$W" which zzz-unknown 2>/dev/null)" ] && ok "with the advice on stderr, not stdout" || bad "with the advice on stderr, not stdout"
  # What the helper isn't sure of, it leaves to the Bash.
  wsame "which, helper and Bash: no name, outside a repository" bash "$T"
  wsame "which, helper and Bash: a name with a backslash" bash "$RC" 'odd\name'
  wsame "which, helper and Bash: a name with a line break" bash "$RC" "two
lines"
  printf -- '- jobapp-api\n' > "$CW/payroll/repos.md"
  wsame "which, helper and Bash: a repository two wikis list" bash "$RC" jobapp-api --collection work
  rm -f "$CW/payroll/repos.md"
  if [ "$(id -u)" != 0 ]; then
    chmod 000 "$CW/jobapp/repos.md"
    wsame "which, helper and Bash: a repos.md that can't be read" bash "$RC" jobapp-api --collection work
    chmod 644 "$CW/jobapp/repos.md"
    chmod 000 "$CW/jobapp"
    wsame "which, helper and Bash: a wiki's folder that can't be read" bash "$RC" jobapp-api --collection work
    expect "which says it can't read a wiki's folder, with the helper" "can't read $CWT/jobapp" wgo "$RC" jobapp-api --collection work
    expect "and with the Bash" "can't read $CWT/jobapp" wno "$RC" jobapp-api --collection work
    lacks "and does not say no wiki covers it" "no wiki covers" wgo "$RC" jobapp-api --collection work
    refuse "and exits non-zero" wno "$RC" jobapp-api --collection work
    wsame "which, helper and Bash: a wiki found by name beside one that can't be read" helper "$RC" payroll --collection work
    chmod 755 "$CW/jobapp"
    chmod 000 "$HOME/wikis/billing/index.md"
    wsame "which, helper and Bash: an index that can't be read" bash "$RC" LEDGER-core
    chmod 644 "$HOME/wikis/billing/index.md"
    chmod 000 "$CW"
    wsame "which, helper and Bash: a collection that can't be read" bash "$RC" jobapp --collection work
    expect "which says it can't read a collection, with the helper" "can't read $CWT" wgo "$RC" zzz-unknown --collection work
    expect "and with the Bash" "can't read $CWT" wno "$RC" zzz-unknown --collection work
    lacks "and does not say no wiki covers it" "no wiki covers" wno "$RC" zzz-unknown --collection work
    expect "and that no telling which wiki covers the name" "no telling which wiki covers zzz-unknown" wno "$RC" zzz-unknown --collection work
    chmod 755 "$CW"
  else
    skipped "which with folders that can't be read (root can read anything)"
  fi
  want="$(cd "$RC" && env -u WIKIS_DIR LLM_WIKI_NO_GO=1 "$W" which jobapp-api --collection work 2>&1)"
  [ "$(cd "$RC" && env -u WIKIS_DIR LLM_WIKI_NO_GO= LLM_WIKI_GO="$T/bin/broken-helper" "$W" which jobapp-api --collection work 2>&1)" = "$want" ] && ok "a helper that fails falls back to the Bash for which" || bad "a helper that fails falls back to the Bash for which"
  [ "$(cd "$RC" && env -u WIKIS_DIR LLM_WIKI_NO_GO= LLM_WIKI_GO="$T/bin/stale-helper" "$W" which jobapp-api --collection work 2>&1)" = "$want" ] && ok "and one built for another protocol is passed over" || bad "and one built for another protocol is passed over"
  # A helper that speaks the protocol but answers with neither first line isn't believed.
  printf '#!/bin/sh\n[ "$1" = protocol ] && { sed -n "s/^GO_PROTOCOL=//p" "%s"; exit 0; }\necho "~/wikis/wrong"\n' "$W" > "$T/bin/odd-helper"
  chmod +x "$T/bin/odd-helper"
  [ "$(cd "$RC" && env -u WIKIS_DIR LLM_WIKI_NO_GO= LLM_WIKI_GO="$T/bin/odd-helper" "$W" which jobapp-api --collection work 2>&1)" = "$want" ] && ok "and an answer that is neither a wiki nor the advice is passed over" || bad "and an answer that is neither a wiki nor the advice is passed over"
  for w in shop shop-web shop-api shop-admin shop-docs billing; do rm -rf "${HOME:?}/wikis/$w"; done
  rm -rf "$CW/payroll" "$RW"
else
  skipped "the Go helper against the Bash for which (go isn't installed)"
fi

# find, from the compiled helper and from the Bash: the same stdout, stderr and exit
# code, and the same line in stats.csv.
if [ -x "$T/bin/llm-wiki" ]; then
  # A wrapper notes how the helper's find ended, so a check can tell who answered.
  printf '#!/bin/sh\n[ "$1" = find ] || exec "%s" "$@"\n"%s" "$@"\nrc=$?\necho "$rc" >> "%s"\nexit $rc\n' "$T/bin/llm-wiki" "$T/bin/llm-wiki" "$T/find-ran" > "$T/bin/find-spy"
  chmod +x "$T/bin/find-spy"
  FD="$HOME/wikis"
  # frun <helper> <folder> <find's arguments>: find there with that helper, or with the
  # Bash alone when none is named. Prints stdout, the exit code, and what stats.csv
  # got. stderr goes to $T/find.err.
  frun() {
    local go="$1" dir="$2" no=1
    shift 2
    [ -z "$go" ] || no=""
    rm -f "$FD/stats.csv" "$CW/stats.csv" 2>/dev/null
    (cd "$dir" && env -u WIKIS_DIR LLM_WIKI_NO_GO="$no" LLM_WIKI_GO="$go" "$W" find "$@" 2>"$T/find.err"; echo "exit $?")
    echo "stats:"
    cat "$FD/stats.csv" "$CW/stats.csv" 2>/dev/null
  }
  # fsame <check> <helper|bash> <find's arguments>: both print and log the same, and
  # with the helper on, the answer came from the one named.
  fsame() {
    local name="$1" who="$2" a b ran
    shift 2
    : > "$T/find-ran"
    a="$(frun "" "$RC" "$@")"
    cp "$T/find.err" "$T/find.a"
    b="$(frun "$T/bin/find-spy" "$RC" "$@")"
    ran="$(cat "$T/find-ran")"
    case "$who:$ran" in helper:0) ran=helper ;; helper:* | bash: | bash:0) ran="not the $who (the helper's find ended: ${ran:-never ran})" ;; *) ran=bash ;; esac
    if [ "$a" = "$b" ] && cmp -s "$T/find.a" "$T/find.err" && [ "$ran" = "$who" ]; then
      ok "$name"
    else
      bad "$name" "$(printf 'answered by: %s\nBash: %s\n%s\nhelper: %s\n%s' "$ran" "$a" "$(cat "$T/find.a")" "$b" "$(cat "$T/find.err")")"
    fi
  }
  # Beta sorts before alpha by byte and after it in most other orders. notes has an
  # index and no handbook, and stray has neither.
  mkdir -p "$FD/Beta" "$FD/notes" "$FD/stray" "$FD/alpha/wiki/howto" "$FD/alpha/wiki/a-b" "$FD/alpha/wiki/a" "$FD/alpha/wiki/.hid" "$FD/alpha/wiki/sources" "$FD/alpha/wiki/sub/sources"
  printf '# Handbook\n' > "$FD/Beta/AGENTS.md"
  printf '# Index\n- [Canary](wiki/c.md): the canary of Beta\n' > "$FD/Beta/index.md"
  printf -- '- canary, in a folder with an index and no handbook\n' > "$FD/notes/index.md"
  printf 'canary, in a folder with no index\n' > "$FD/stray/readme.md"
  printf '# Handbook\n' > "$FD/alpha/AGENTS.md"
  printf '# Index\n\n## Canary pages\n- [Deploy flow](wiki/howto/deploy.md): canary first, then the rest\n- [Costs](wiki/costs.md): a.c is not abc, and $5 (.*) [x] ^# is no pattern\n- [School](wiki/school.md): \303\211cole normale, and caf\351 in Latin-1' > "$FD/alpha/index.md"
  printf -- '---\ntitle: Deploy\n---\nThe canary goes first.\n' > "$FD/alpha/wiki/howto/deploy.md"
  printf 'canary in a-b\n' > "$FD/alpha/wiki/a-b/x.md"
  printf 'canary in a\n' > "$FD/alpha/wiki/a/x.md"
  printf 'canary in a hidden folder\n' > "$FD/alpha/wiki/.hid/h.md"
  printf 'canary with a carriage return\r\n' > "$FD/alpha/wiki/crlf.md"
  printf -- '---\ntitle: canary only up here\n---\nNothing below.\n' > "$FD/alpha/wiki/front.md"
  # The 120th byte of its line is the first of an arrow's three.
  printf -- '---\ntitle: Long\n---\n \t  %s canary:\342\206\222 and on it goes\n' "$(printf '%0111d' 0)" > "$FD/alpha/wiki/long.md"
  # More lines that a cut at 120 bytes ends inside a character, or just after one: the
  # first byte of two, three of four, and an arrow whose last byte is the 120th.
  printf '%s twobyte:\303\251 and on\n' "$(printf '%0110d' 0)" > "$FD/alpha/wiki/cut-two.md"
  printf '%s fourbyte:\360\237\230\200 and on\n' "$(printf '%0107d' 0)" > "$FD/alpha/wiki/cut-four.md"
  printf '%s wholechar:\342\206\222 and on\n' "$(printf '%0106d' 0)" > "$FD/alpha/wiki/cut-whole.md"
  printf 'latinend, a line that ends in Latin-1: caf\351\n' > "$FD/alpha/wiki/end-latin.md"
  printf 'canary, the sixth page, so never shown\n' > "$FD/alpha/wiki/zlast.md"
  printf 'canary under sources\n' > "$FD/alpha/wiki/sources/s.md"
  printf 'canary under a deeper sources\n' > "$FD/alpha/wiki/sub/sources/t.md"
  printf 'canary in a file that is not .md\n' > "$FD/alpha/wiki/upper.MD"
  printf 'At the \303\211cole.\ncaf\351 au lait, in Latin-1\n' > "$FD/alpha/wiki/school.md"
  printf 'The work canary.\n' > "$CW/jobapp/wiki/canary.md"

  fsame "find, helper and Bash: a word in several wikis, whatever its case" helper CANARY
  out="$(frun "$T/bin/llm-wiki" "$RC" CANARY)"
  cr=$'\r'
  want="Beta:
  - [Canary](wiki/c.md): the canary of Beta
alpha:
  - [Deploy flow](wiki/howto/deploy.md): canary first, then the rest
  also in pages:
    wiki/.hid/h.md: canary in a hidden folder
    wiki/a-b/x.md: canary in a-b
    wiki/a/x.md: canary in a
    wiki/crlf.md: canary with a carriage return$cr
    wiki/long.md: $(printf '%0111d' 0) canary:
notes:
  - canary, in a folder with an index and no handbook
exit 0
stats:
date,wiki,result,word
$(date -u +%Y-%m-%d),Beta,search-found,CANARY"
  [ "$out" = "$want" ] && ok "and the helper prints index lines, then five pages by path, and logs the first wiki" || bad "and the helper prints index lines, then five pages by path, and logs the first wiki" "$out"
  fsame "find, helper and Bash: an index line in another case than the word's" helper "DEPLOY flow"
  fsame "find, helper and Bash: a page's line in another case than the word's" helper "the CANARY goes"
  expect "and the helper shows the line as it is written" "wiki/howto/deploy.md: The canary goes first." frun "$T/bin/llm-wiki" "$RC" "the CANARY goes"
  # A line is cut at 120 bytes and never inside a character, so what find prints of
  # pages that are UTF-8 is UTF-8.
  fsame "find, helper and Bash: a line cut inside a character of two bytes" helper twobyte
  expect "and the helper stops before the character" "wiki/cut-two.md: $(printf '%0110d' 0) twobyte:
exit 0" frun "$T/bin/llm-wiki" "$RC" twobyte
  fsame "find, helper and Bash: a line cut inside a character of four bytes" helper fourbyte
  expect "and the helper stops before that one too" "wiki/cut-four.md: $(printf '%0107d' 0) fourbyte:
exit 0" frun "$T/bin/llm-wiki" "$RC" fourbyte
  fsame "find, helper and Bash: a line cut just after a character" helper wholechar
  expect "and the helper keeps the character" "wiki/cut-whole.md: $(printf '%0106d' 0) wholechar:$(printf '\342\206\222')
exit 0" frun "$T/bin/llm-wiki" "$RC" wholechar
  for w in canary twobyte fourbyte wholechar; do
    frun "" "$RC" "$w" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1 || break
    frun "$T/bin/llm-wiki" "$RC" "$w" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1 || break
    w=""
  done
  [ -z "$w" ] && ok "what find prints of UTF-8 pages is UTF-8, from the helper and the Bash" || bad "what find prints of UTF-8 pages is UTF-8, from the helper and the Bash" "not UTF-8: find $w"
  # The MCP server reads find through Python as text, in whatever locale it was started.
  aspy() { (cd "$RC" && env -u WIKIS_DIR -u LC_ALL -u LC_CTYPE -u LANG "$@" python3 -c 'import subprocess, sys; print(subprocess.run([sys.argv[1], "find", sys.argv[2]], capture_output=True, text=True).stdout)' "$W" canary 2>&1); }
  expect "Python reads the helper's find as text with no locale set" "wiki/long.md: $(printf '%0111d' 0) canary:
notes:" aspy LLM_WIKI_NO_GO= LLM_WIKI_GO="$T/bin/llm-wiki"
  expect "and the Bash's" "wiki/long.md: $(printf '%0111d' 0) canary:
notes:" aspy LLM_WIKI_NO_GO=1
  fsame "find, helper and Bash: a line that ends in a Latin-1 letter loses it" helper latinend
  expect "and the helper shows the rest" "wiki/end-latin.md: latinend, a line that ends in Latin-1: caf
exit 0" frun "$T/bin/llm-wiki" "$RC" latinend
  # No output of wiki.sh can end a call to the MCP server: bytes that aren't UTF-8 come back as U+FFFD.
  expect "wiki_search answers when an index line isn't UTF-8" "- [School](wiki/school.md): " mcp_any wiki_search '{"word":"in Latin-1"}'
  lacks "and doesn't fail" "ERROR" mcp_any wiki_search '{"word":"in Latin-1"}'
  fsame "find, helper and Bash: a word that matches nothing" helper zzznothing
  expect "and the helper says so, and logs it against the shared wiki" "no mentions in any index or page: zzznothing
exit 0
stats:
date,wiki,result,word
$(date -u +%Y-%m-%d),global,search-none,zzznothing" frun "$T/bin/llm-wiki" "$RC" zzznothing
  fsame "find, helper and Bash: a heading of an index is no entry" helper "Canary pages"
  fsame "find, helper and Bash: a dot is a dot" helper a.c
  lacks "and stands for no other character" "a-b" frun "$T/bin/llm-wiki" "$RC" a.b
  fsame "find, helper and Bash: a star, a bracket, a caret and a dollar are themselves" helper '.*) [x] ^#'
  fsame "find, helper and Bash: a word with a comma, logged without it" helper 'first, then'
  expect "and the helper's log has the word without the comma" ",alpha,search-found,first then" frun "$T/bin/llm-wiki" "$RC" 'first, then'
  fsame "find, helper and Bash: a space" helper ' '
  fsame "find, helper and Bash: a word with an accent" helper "$(printf '\303\211cole')"
  expect "and the helper finds it" "- [School](wiki/school.md): " frun "$T/bin/llm-wiki" "$RC" "$(printf '\303\211cole')"
  fsame "find, helper and Bash: an accented letter in the other case is another letter" helper "$(printf '\303\251cole')"
  expect "and the helper finds nothing for it" "no mentions" frun "$T/bin/llm-wiki" "$RC" "$(printf '\303\251cole')"
  fsame "find, helper and Bash: a word and a page that aren't UTF-8" helper "$(printf 'CAF\351')"
  expect "and the helper finds them" "wiki/school.md: caf" frun "$T/bin/llm-wiki" "$RC" "$(printf 'CAF\351 au')"
  fsame "find, helper and Bash: a second collection" helper canary --collection work
  expect "and the helper searches that one alone" "jobapp:
  also in pages:
    wiki/canary.md: The work canary.
exit 0
stats:
date,wiki,result,word
$(date -u +%Y-%m-%d),jobapp,search-found,canary" frun "$T/bin/llm-wiki" "$RC" canary --collection work
  # The Bash is pinned to LC_ALL=C, so a locale changes nothing: not the order of the
  # wikis, not which letters match, not where a line is cut.
  U8="$(locale -a 2>/dev/null | grep -i -E '^(en_US|C)\.utf-?8$' | head -n 1)"
  if [ -n "$U8" ]; then
    [ "$(LC_ALL="$U8" frun "" "$RC" CANARY)" = "$want" ] && ok "find with the Bash prints the same in a UTF-8 locale" || bad "find with the Bash prints the same in a UTF-8 locale" "$(LC_ALL="$U8" frun "" "$RC" CANARY)"
    [ "$(LC_ALL="$U8" frun "$T/bin/llm-wiki" "$RC" CANARY)" = "$want" ] && ok "and so does the helper" || bad "and so does the helper" "$(LC_ALL="$U8" frun "$T/bin/llm-wiki" "$RC" CANARY)"
    expect "and an accented letter in the other case still isn't found there" "no mentions" env LC_ALL="$U8" LLM_WIKI_NO_GO=1 "$W" find "$(printf '\303\251cole')"
  else
    skipped "find in a UTF-8 locale (none is installed)"
  fi
  # Wikis whose names differ by a suffix after a dash. The shell's glob sorts them with
  # the slash each match ends in, so covers-nl/ comes before covers/ and llm-wiki/ before
  # llm/, and the first with a result is the one the search is logged against.
  for w in covers covers-nl llm llm-wiki; do
    mkdir -p "$FD/$w"
    printf '# Handbook\n' > "$FD/$w/AGENTS.md"
    printf '# Index\n- the dashword of %s\n' "$w" > "$FD/$w/index.md"
  done
  printf -- '- the llmword of llm\n' >> "$FD/llm/index.md"; printf -- '- the llmword of llm-wiki\n' >> "$FD/llm-wiki/index.md"
  fsame "find, helper and Bash: wikis named covers, covers-nl, llm and llm-wiki" helper dashword
  expect "and the helper orders them as the shell's glob of */ does, and logs the first" "covers-nl:
  - the dashword of covers-nl
covers:
  - the dashword of covers
llm-wiki:
  - the dashword of llm-wiki
llm:
  - the dashword of llm
exit 0
stats:
date,wiki,result,word
$(date -u +%Y-%m-%d),covers-nl,search-found,dashword" frun "$T/bin/llm-wiki" "$RC" dashword
  fsame "find, helper and Bash: a word only in llm and llm-wiki" helper llmword
  expect "and the helper logs llm-wiki, which comes first" "$(date -u +%Y-%m-%d),llm-wiki,search-found,llmword" frun "$T/bin/llm-wiki" "$RC" llmword
  expect "and the Bash does the same" "$(date -u +%Y-%m-%d),llm-wiki,search-found,llmword" frun "" "$RC" llmword
  rm -rf "${FD:?}/covers" "${FD:?}/covers-nl" "${FD:?}/llm" "${FD:?}/llm-wiki"
  # The helper reads no page after the fifth it shows, and the Bash takes no line from one.
  printf 'canary\0\n' > "$FD/alpha/wiki/zz-nul.md"
  fsame "find, helper and Bash: a page with a NUL byte past the five shown" helper canary
  rm -f "$FD/alpha/wiki/zz-nul.md"
  # What the helper isn't sure of, it leaves to the Bash.
  fsame "find, helper and Bash: a word with a backslash" bash 'can\ary'
  fsame "find, helper and Bash: a word with a line break" bash "canary
goes"
  printf 'canary\0\n' > "$FD/alpha/wiki/a/nul.md"
  fsame "find, helper and Bash: a page with a NUL byte" bash canary
  rm -f "$FD/alpha/wiki/a/nul.md"
  cp "$FD/Beta/index.md" "$T/beta-index"
  printf -- '- canary\0\n' >> "$FD/Beta/index.md"
  fsame "find, helper and Bash: an index with a NUL byte" bash canary
  cp "$T/beta-index" "$FD/Beta/index.md"
  ln -s ../zlast.md "$FD/alpha/wiki/a/link.md"
  fsame "find, helper and Bash: a page that is a link" bash canary
  rm -f "$FD/alpha/wiki/a/link.md"
  ln -s "$FD/alpha/wiki" "$FD/notes/wiki"
  fsame "find, helper and Bash: a wiki/ folder that is a link" bash canary
  rm -f "$FD/notes/wiki"
  if [ "$(id -u)" != 0 ]; then
    chmod 000 "$FD/alpha/wiki/a/x.md"
    fsame "find, helper and Bash: a page that can't be read" bash canary
    lacks "which the Bash leaves out" "wiki/a/x.md" frun "$T/bin/llm-wiki" "$RC" canary
    chmod 644 "$FD/alpha/wiki/a/x.md"
    chmod 000 "$FD/alpha/index.md"
    fsame "find, helper and Bash: an index that can't be read" bash canary
    chmod 644 "$FD/alpha/index.md"
    chmod 000 "$FD/alpha/wiki"
    fsame "find, helper and Bash: a folder of pages that can't be read" bash canary
    chmod 755 "$FD/alpha/wiki"
    chmod 000 "$FD/alpha"
    fsame "find, helper and Bash: a wiki's folder that can't be read" bash canary
    chmod 755 "$FD/alpha"
    chmod 000 "$FD"
    fsame "find, helper and Bash: a collection that can't be read" bash canary
    chmod 755 "$FD"
  else
    skipped "find with folders that can't be read (root can read anything)"
  fi
  want="$(frun "" "$RC" canary)"
  [ "$(frun "$T/bin/broken-helper" "$RC" canary)" = "$want" ] && ok "a helper that fails falls back to the Bash for find, and the search is logged once" || bad "a helper that fails falls back to the Bash for find, and the search is logged once" "$(frun "$T/bin/broken-helper" "$RC" canary)"
  [ "$(frun "$T/bin/stale-helper" "$RC" canary)" = "$want" ] && ok "and one built for another protocol is passed over" || bad "and one built for another protocol is passed over"
  # A helper that speaks the protocol but doesn't say how the search went isn't believed.
  printf '#!/bin/sh\n[ "$1" = protocol ] && { sed -n "s/^GO_PROTOCOL=//p" "%s"; exit 0; }\nprintf "alpha:\\n  - wrong\\n"\n' "$W" > "$T/bin/odd-helper"
  chmod +x "$T/bin/odd-helper"
  [ "$(frun "$T/bin/odd-helper" "$RC" canary)" = "$want" ] && ok "and an answer with no first line saying found or none is passed over" || bad "and an answer with no first line saying found or none is passed over" "$(frun "$T/bin/odd-helper" "$RC" canary)"

  # status, from the compiled helper and from the Bash: the same stdout, stderr and exit
  # code. The helper makes the table and counts the other collections' notes; the rest
  # is the Bash's either way. A wrapper notes how the helper's status ended, and the
  # MCP comparison below runs through it too, so it notes what else ran as spy-helper does.
  printf '#!/bin/sh\necho "$1" >> "%s"\n[ "$1" = status ] || exec "%s" "$@"\n"%s" "$@"\nrc=$?\necho "$rc" >> "%s"\nexit $rc\n' "$T/helper-ran" "$T/bin/llm-wiki" "$T/bin/llm-wiki" "$T/status-ran" > "$T/bin/status-spy"
  chmod +x "$T/bin/status-spy"
  # srun <helper> [VAR=value...]: status from a repository the default collection takes,
  # with that helper, or with the Bash alone when none is named, and no locale unless
  # given. Prints stdout and the exit code. stderr goes to $T/status.err. $SW is the
  # wiki.sh to run.
  srun() {
    local go="$1" no=1
    shift
    [ -z "$go" ] || no=""
    (cd "$RC" && env -u WIKIS_DIR -u LC_ALL -u LC_CTYPE -u LANG LLM_WIKI_NO_GO="$no" LLM_WIKI_GO="$go" "$@" "${SW:-$W}" status 2>"$T/status.err"; echo "exit $?")
  }
  # ssame <check> <helper|bash> [VAR=value...]: both print the same, and with the helper
  # on, the answer came from the one named.
  ssame() {
    local name="$1" who="$2" a b ran
    shift 2
    : > "$T/status-ran"
    a="$(srun "" "$@")"
    cp "$T/status.err" "$T/status.a"
    b="$(srun "$T/bin/status-spy" "$@")"
    ran="$(cat "$T/status-ran")"
    case "$who:$ran" in helper:0) ran=helper ;; helper:* | bash: | bash:0) ran="not the $who (the helper's status ended: ${ran:-never ran})" ;; *) ran=bash ;; esac
    if [ "$a" = "$b" ] && cmp -s "$T/status.a" "$T/status.err" && [ "$ran" = "$who" ]; then
      ok "$name"
    else
      bad "$name" "$(printf 'answered by: %s\n' "$ran"; diff <(printf '%s\n' "$a") <(printf '%s\n' "$b"); diff "$T/status.a" "$T/status.err")"
    fi
  }
  # sw <name> <version, or none>: a wiki for status, with an index and a log.
  sw() {
    mkdir -p "$FD/$1/raw"
    if [ "$2" = none ]; then printf '# AGENTS.md\n' > "$FD/$1/AGENTS.md"; else printf '# AGENTS.md\n\nHandbook version %s.\n' "$2" > "$FD/$1/AGENTS.md"; fi
    printf '# Index\n' > "$FD/$1/index.md"
    printf '# Log\n' > "$FD/$1/log.md"
  }
  # Beta and alpha get a log.md here; a wiki with no log.md has its own check below.
  printf '# Log\n' > "$FD/Beta/log.md"; printf '# Log\n' > "$FD/alpha/log.md"
  sw st-due "$TV"
  for n in a.md b.md c.txt d.md e.tar.gz f.md g.md h.md i.md j.md .hidden.md; do printf 'x\n' > "$FD/st-due/raw/2026-01-01-$n"; done
  printf 'x\n' > "$FD/st-due/raw/.x.md"; mkdir -p "$FD/st-due/raw/folder.md" "$FD/st-due/wiki/sources"
  printf '# Log\n\n## 2026-01-01 ingest | a\n- source: raw/2026-01-01-a.md\n- source: raw/2026-01-01-e.tar.gz\n' > "$FD/st-due/log.md"
  printf -- '---\nsources: [raw/2026-01-01-b.md, "raw/2026-01-01-c.txt"]\n---\nsources: raw/2026-01-01-zz.md\n' > "$FD/st-due/wiki/p.md"
  printf 'An old summary page.\n' > "$FD/st-due/wiki/sources/2026-01-01-d.md"
  # Sources one a line, as Obsidian rewrites them. k and l are compiled. m is a list
  # item after the list ended, so it waits, as it would have before.
  for n in k.md l.md m.md; do printf 'x\n' > "$FD/st-due/raw/2026-01-01-$n"; done
  printf -- '---\ntitle: q\nsources:\n  - raw/2026-01-01-k.md\n\t- "raw/2026-01-01-l.md"\nupdated: 2026-01-01\n- raw/2026-01-01-m.md\n---\n' > "$FD/st-due/wiki/q.md"
  sw st-lint "$TV"
  { printf '# Log\n\n## 2026-01-01 ingest | old\n## 2026-01-02 lint | lint\n'; for n in 1 2 3 4 5 6 7 8 9 10; do printf '## 2026-01-03 ingest | %s\n' "$n"; done; } > "$FD/st-lint/log.md"
  sw st-pat "$TV"
  printf '# Patterns\n\n## Ready\n- kind: correction\n- status: watching\n- seen: 2026-01-01 a raw/a.md x3\n## Again\n- kind: correction\n- status: accepted 2026-01-05: a convention\n- seen: 2026-01-06 b raw/b.md\n' > "$FD/st-pat/patterns.md"
  sw st-old 1; sw st-new 999; sw st-nover none
  sw st-lock "$TV"; printf 'held by s-1 since 2026-01-01\nmore\n' > "$FD/st-lock/.compile-lock"
  # covers-nl/ comes before covers/ in the shell's glob, which sorts with the slash.
  sw st-cov "$TV"; printf -- '- web\n- api\r\nnot a line\n- last' > "$FD/st-cov/repos.md"
  sw st-cov-nl "$TV"; printf -- '- one\n- two\n' > "$FD/st-cov-nl/repos.md"
  # Bytes that aren't UTF-8 stopped macOS's sed in a UTF-8 locale, and status with it.
  sw st-latin "$TV"; printf 'caf\351\n\nHandbook version %s.\n' "$TV" > "$FD/st-latin/AGENTS.md"
  printf -- '- caf\351\n' > "$FD/st-latin/repos.md"; printf '# Log\n- source: raw/caf\351.md\n' > "$FD/st-latin/log.md"; printf 'x\n' > "$FD/st-latin/raw/caf$(printf '\351').md"
  sw "st-caf$(printf '\303\251')" "$TV"
  printf 'x\n' > "$CW/jobapp/raw/2026-01-01-a.md"; printf 'x\n' > "$CW/jobapp/raw/2026-01-01-b.md"

  ssame "status, helper and Bash: every kind of row and to-do, with the other collection's notes" helper
  out="$(srun "$T/bin/llm-wiki")"
  expect "and the helper counts the notes waiting, less those compiled" "st-due                     v$TV       7        free  <- compile due" printf '%s' "$out"
  expect "and the patterns ready and not working, and the ingests since a lint" "st-pat                     v$TV       0        free  <- 1 pattern(s) ready  <- 1 accepted fix(es) not working" printf '%s' "$out"
  expect "and the lock" "st-lock                    v$TV       0        held by s-1 since 2026-01-01" printf '%s' "$out"
  expect "and what a wiki covers, a last line with no line feed and all" "free  covers: web api$(printf '\r') last" printf '%s' "$out"
  expect "and the other collection's notes" "also:    collection work at $(printf '%s' "$CW" | sed "s#^$HOME#~#"), 2 note(s) waiting." printf '%s' "$out"
  [ "$(printf '%s\n' "$out" | awk '$1 ~ /^(Beta|alpha|st-cov-nl|st-cov)$/ { printf "%s ", $1 }')" = "Beta alpha st-cov-nl st-cov " ] && ok "and orders the wikis by byte, as the shell's glob of */ does" || bad "and orders the wikis by byte, as the shell's glob of */ does" "$out"
  if [ -n "$U8" ]; then
    # A terminal sets LANG and leaves LC_ALL unset, so the Bash's own LC_ALL=C has to
    # reach its sed, grep, awk and tr by export. LC_ALL in the environment hid that.
    ssame "status, helper and Bash: the same in a UTF-8 locale, set by LANG as a terminal sets it" helper LANG="$U8"
    out="$(srun "" LANG="$U8")"
    case "$out" in *"st-pat "*"exit 0") ok "and the Bash makes the whole table there, past a wiki that isn't UTF-8" ;; *) bad "and the Bash makes the whole table there, past a wiki that isn't UTF-8" "$out" ;; esac
    [ "$out" = "$(srun "")" ] && ok "status with the Bash prints the same in a UTF-8 locale as in none" || bad "status with the Bash prints the same in a UTF-8 locale as in none" "$(diff <(printf '%s\n' "$out") <(srun ""))"
    ssame "status, helper and Bash: the same with LC_ALL set to a UTF-8 locale" helper LC_ALL="$U8"
  else
    skipped "status in a UTF-8 locale (none is installed)"
  fi
  # From the plugin, a wiki ahead of the template is the plugin's to fix.
  SPL="$HOME/.claude/plugins/cache/llm-wiki/llm-wiki/st123"
  mkdir -p "$SPL" && (cd "$REPO" && tar cf - --exclude .git --exclude tests --exclude tour --exclude bin .) | (cd "$SPL" && tar xf -)
  SW="$SPL/wiki.sh" ssame "status, helper and Bash: from the plugin, with a wiki ahead of its template" helper
  SW="$SPL/wiki.sh" expect "and the helper says so" "<- ahead of this plugin's template v$TV" srun "$T/bin/llm-wiki"
  rm -rf "$SPL"

  # What the helper isn't sure of, it leaves to the Bash.
  printf '## X\0\n' >> "$FD/st-pat/patterns.md"
  ssame "status, helper and Bash: a patterns.md with a NUL byte" bash
  printf '# Patterns\n\n## X\n- status: accepted 20260105\n- seen: 20260106 a\n' > "$FD/st-pat/patterns.md"
  ssame "status, helper and Bash: dates awk might compare as numbers" bash
  ln -s ../index.md "$FD/st-due/wiki/link.md"
  ssame "status, helper and Bash: a link under wiki/" bash
  rm -f "$FD/st-due/wiki/link.md"
  printf 'x\n' > "$FD/st-due/raw/two
lines.md"
  ssame "status, helper and Bash: a note whose name has a line break" bash
  rm -f "$FD/st-due/raw/two
lines.md"
  sw "st-old one" 1
  ssame "status, helper and Bash: a wiki behind the template whose name has a space" bash
  rm -rf "$FD/st-old one"
  mv "$FD/st-lint/log.md" "$T/st-log"
  ssame "status, helper and Bash: a wiki with no log.md, which the Bash answers" bash
  # The Bash used to stop at the first wiki with no log.md, with exit 2 and a table cut off there.
  out="$(srun "")"
  case "$out" in *"st-lint "*"st-pat "*"exit 0") ok "and the Bash makes the whole table, counting no ingests, and exits 0" ;; *) bad "and the Bash makes the whole table, counting no ingests, and exits 0" "$out" ;; esac
  mv "$T/st-log" "$FD/st-lint/log.md"
  if [ "$(id -u)" != 0 ]; then
    chmod 000 "$FD/st-due/raw"
    ssame "status, helper and Bash: a raw/ that can't be read" bash
    expect "which the Bash shows as ?" "<- can't read raw/" srun ""
    chmod 755 "$FD/st-due/raw"
  else
    skipped "status with a raw/ that can't be read (root can read anything)"
  fi
  # An answer that isn't whole is passed over, and the Bash makes the table.
  want="$(srun "")"
  [ "$(srun "$T/bin/broken-helper")" = "$want" ] && ok "a helper that fails falls back to the Bash for status" || bad "a helper that fails falls back to the Bash for status" "$(srun "$T/bin/broken-helper")"
  [ "$(srun "$T/bin/stale-helper")" = "$want" ] && ok "and one built for another protocol is passed over" || bad "and one built for another protocol is passed over"
  for odd in 'row WIKI\n' 'status\nrow WIKI\nbogus\n' 'status\nrow WIKI\n' 'status\n'; do
    printf '#!/bin/sh\n[ "$1" = protocol ] && { sed -n "s/^GO_PROTOCOL=//p" "%s"; exit 0; }\nprintf "%s"\n' "$W" "$odd" > "$T/bin/odd-helper"
    [ "$(srun "$T/bin/odd-helper")" = "$want" ] || break
    odd=""
  done
  [ -z "$odd" ] && ok "and so is an answer with no first line, a line it can't place, no also line for the other collection, or no table" || bad "and so is an answer with no first line, a line it can't place, no also line for the other collection, or no table" "helper's answer: $odd"
  rm -f "$CW/jobapp/raw/2026-01-01-a.md" "$CW/jobapp/raw/2026-01-01-b.md"
  rm -rf "$FD"/st-*

  # The MCP server, from the compiled helper and from mcp/server.py: the same replies to
  # the same requests, and the same files left behind. Replies are compared as JSON:
  # the helper writes no space after a colon or a comma, sorts an object's keys, and
  # writes text as UTF-8 where Python writes \u escapes.
  cat > "$T/mcp-same.py" <<'PY'
"""For the smoke test: lines for both MCP servers, and what came back.
  requests <batch>         a batch's request lines, to stdout
  same <a> <b>             two servers' replies are the same, compared as JSON
  client <requests> <out>  the replies are what a client needs: one line each of UTF-8
                           and JSON, in order, with the id each request sent
  text <out> <id>          the text of the reply with that id, ERROR: in front if it failed
  codes <out>              each reply's error code, or ok or tool-error, on one line
  files <folder>...        what is in the folders, for comparing two runs
"""
import hashlib
import json
import os
import re
import sys

# A note's name holds the second it was saved, as 2026-01-31-235959 for a capture and
# 20260131-235959 for feedback, and a feedback note the minute. Two runs share neither.
CLOCK = re.compile(r"\d{4}-?\d{2}-?\d{2}-\d{6}")
CLOCK_BYTES = re.compile(rb"\d{4}-?\d{2}-?\d{2}-\d{6}")
MINUTE = re.compile(rb"\d{4}-\d{2}-\d{2} \d{2}:\d{2}")
# A second note with the same name in the same second gets -2, -3 and so on, so the
# suffix is the clock's doing too: whether two notes fall in one second.
SAME_SECOND = re.compile(r"(TIME-[a-z0-9-]*?)-\d+(?=\.md|[\"\s\\])")
SAME_SECOND_BYTES = re.compile(rb"(TIME-[a-z0-9-]*?)-\d+(?=\.md|[\"\s\\])")


def strict(line):
    """One line as JSON, or ValueError: UTF-8, and no NaN or Infinity."""
    def bad(word):
        raise ValueError("not JSON: " + word)
    return json.loads(line.decode("utf-8"), parse_constant=bad)


def replies(path, blank_clock=False):
    data = open(path, "rb").read()
    if data and not data.endswith(b"\n"):
        sys.exit("%s doesn't end with a line feed" % path)
    out = []
    for n, line in enumerate(data.split(b"\n")[:-1], 1):
        if blank_clock:
            line = SAME_SECOND_BYTES.sub(rb"\1", CLOCK_BYTES.sub(b"TIME", line))
        try:
            out.append(strict(line))
        except ValueError as e:
            sys.exit("%s line %d isn't one line of UTF-8 JSON: %s: %r" % (path, n, e, line[:200]))
    return out


def requests(batch):
    lines = []
    count = [0]

    def req(method, params=None, id=None):
        count[0] += 1
        m = {"jsonrpc": "2.0", "id": id or count[0], "method": method}
        if params is not None:
            m["params"] = params
        lines.append(json.dumps(m).encode())

    def call(tool, arguments=None, id=None):
        params = {"name": tool}
        if arguments is not None:
            params["arguments"] = arguments
        req("tools/call", params, id)

    arrow = b"\xe2\x86\x92".decode()
    ecole = b"\xc3\x89cole".decode()
    # 81 bytes: the 60th is the first of a character's two.
    long = "x" + b"\xc3\xa9".decode() * 40
    upper, lower = b"\xc3\x89cole".decode(), b"\xc3\xa9cole".decode()
    if batch == "same":
        req("initialize", {"protocolVersion": "2025-03-26", "capabilities": {}, "clientInfo": {"name": "smoke", "version": "0"}})
        lines.append(b'{"jsonrpc":"2.0","method":"notifications/initialized"}')
        req("initialize")
        req("initialize", {"protocolVersion": ""})
        req("initialize", {"protocolVersion": 5})
        req("initialize", [])
        req("ping")
        req("ping", "ignored")
        req("nope")
        req("tools/list")
        req("tools/list", {"cursor": "x"})
        lines.extend([
            b"not json", b"", b"   \t ", b"[1,2]", b'"str"', b"null", b"5",
            b'{"jsonrpc":"2.0","id":"abc","method":"ping"}',
            b'{"jsonrpc":"2.0","id":null,"method":"ping"}',
            b'{"jsonrpc":"2.0","id":1.5,"method":"ping"}',
            b'{"jsonrpc":"2.0","id":{"a":[1,"\\u2028"]},"method":"ping"}',
            b'{"id":77}',
            b'{"jsonrpc":"2.0","id":78,"method":5}',
            b'{"jsonrpc":"2.0","id":79,"method":"ping"} trailing',
            b'{"jsonrpc":"2.0","id":80,"method":"ping",}',
            b'  {"jsonrpc":"2.0","id":81,"method":"ping"}  ',
            b'{"jsonrpc":"2.0","id":82,"id":83,"method":"ping"}',
        ])
        req("tools/call")
        req("tools/call", {})
        req("tools/call", {"name": "nope"})
        req("tools/call", {"name": 5})
        req("tools/call", {"name": "wiki_list", "arguments": "ignored"})
        call("wiki_list", id="list")
        for a in [
            {"wiki": "alpha"}, {"wiki": "alpha", "path": ""}, {"wiki": "alpha", "path": None},
            {"wiki": "alpha", "path": "wiki/howto/deploy.md"}, {"wiki": "alpha", "path": "./wiki/../wiki/howto/deploy.md"},
            {"wiki": "alpha", "path": "wiki/long.md"}, {"wiki": "alpha", "path": "wiki/cut-four.md"},
            {"wiki": "alpha", "path": "wiki/big.md"}, {"wiki": "alpha", "path": "wiki/fits.md"},
            {"wiki": "alpha", "path": "wiki/.hid/h.md"}, {"wiki": "alpha", "path": "../Beta/index.md"},
            {"wiki": "alpha", "path": "/etc/hosts"}, {"wiki": "alpha", "path": "~/x.md"}, {"wiki": "alpha", "path": "."},
            {"wiki": "alpha", "path": "wiki"}, {"wiki": "alpha", "path": "wiki/nope.md"}, {"wiki": "alpha", "path": "wiki/upper.MD"},
            {"wiki": "alpha", "path": "wiki/a/x.md/y.md"}, {"wiki": "Beta"}, {"wiki": "notes"}, {"wiki": "../alpha"}, {"wiki": ""}, {},
            {"wiki": "alpha\n"}, {"wiki": "jobapp"}, {"wiki": "jobapp", "collection": "default"},
            {"wiki": "global", "collection": "work"}, {"wiki": "alpha", "collection": "nope"},
        ]:
            call("wiki_read", a)
        call("wiki_read", {"wiki": "alpha", "path": "wiki/zz-crlf.md"}, id="read-crlf")
        call("wiki_read", {"wiki": "alpha", "path": "wiki/school.md"}, id="read-latin")
        call("wiki_read", {"wiki": "alpha", "path": "wiki/zz-broken.md"}, id="read-broken")
        call("wiki_search", {"word": "canary"}, id="search-canary")
        call("wiki_search", {"word": "in Latin-1"}, id="search-latin")
        for a in [
            {"word": "CANARY", "collection": "work"}, {"word": "canary", "collection": "default"}, {"word": "canary", "collection": "nope"},
            {"word": "  twobyte  "}, {"word": "fourbyte"}, {"word": "wholechar"}, {"word": "latinend"}, {"word": "zzznothing"},
            {"word": "carriage"}, {"word": arrow}, {"word": ecole}, {"word": "first, then"}, {"word": "a.c"}, {"word": "x" * 70},
            {"word": long}, {"word": "brokenarrow"}, {"word": ""}, {"word": "   "}, {"word": "-x"}, {}, {"word": None}, {"word": 0},
        ]:
            call("wiki_search", a)
        for a in [
            {"repository": "jobapp"}, {"repository": "jobapp-api"}, {"repository": "alpha"}, {"repository": "nosuchrepo"},
            {"repository": "jobapp", "collection": "default"}, {"repository": "../x"},
            {}, {"collection": "work"}, {"collection": "nope"}, None,
        ]:
            call("wiki_start", a)
        for a in [None, {"collection": "work"}, {"collection": "nope"}]:
            call("wiki_status", a)
        for a in [
            {"wiki": "alpha", "slug": "../x", "note": "n"}, {"wiki": "alpha", "slug": "x", "note": " \n "},
            {"wiki": "alpha", "slug": "x", "note": "n" * 200001}, {"wiki": "nosuch", "slug": "x", "note": "n"}, {"wiki": "alpha"}, {},
        ]:
            call("wiki_capture", a)
        call("wiki_feedback", {"kind": "nope", "summary": "s", "details": "d"})
        call("wiki_feedback", {})
    elif batch == "fallback":
        # A link under wiki/, a word with a backslash or a line break, and a repos.md that
        # isn't UTF-8: the helper's server leaves each to wiki.sh, as the Python always does.
        call("wiki_list", id="list")
        call("wiki_read", {"wiki": "alpha", "path": "wiki/a/link.md"}, id="read-link")
        call("wiki_read", {"wiki": "alpha", "path": "wiki/out.md"})
        call("wiki_search", {"word": "canary"})
        call("wiki_search", {"word": "back\\slash"})
        call("wiki_search", {"word": long + "\\"})
        call("wiki_search", {"word": "two\nlines"})
        call("wiki_start", {"repository": "jobapp-api"}, id="start")
        call("wiki_start", {"repository": "nosuchrepo"})
        call("wiki_start", {"repository": "alpha\n"})
        call("wiki_status", None)
    elif batch == "write":
        # The tools that write. Only ever in the test's own folders.
        call("wiki_capture", {"wiki": "alpha", "slug": "from-chat", "note": "We chose Postgres, in a chat.\nWith an arrow " + arrow + ".\n"}, id="capture")
        call("wiki_capture", {"wiki": "jobapp", "slug": "work-note", "note": "A work note."})
        call("wiki_capture", {"wiki": "global", "slug": "g", "note": "x", "collection": "work"})
        call("wiki_feedback", {"kind": "idea", "summary": "s", "details": "d"})
        call("wiki_feedback", {"kind": "bug", "summary": "It broke, with a comma", "details": "What I ran.\nWhat came back.", "agent": "Smoke, test model"}, id="feedback")
        call("wiki_feedback", {"kind": "oops", "summary": "s", "details": "d"})
        # Whether these two are one note depends on LC_CTYPE where tr knows accented
        # letters, as on macOS, so they tell a server whose wiki.sh has another locale.
        call("wiki_feedback", {"kind": "docs", "summary": upper + " is misspelled", "details": "d"})
        call("wiki_feedback", {"kind": "docs", "summary": lower + " is misspelled", "details": "d"})
    elif batch == "differ":
        # Where the helper's server answers differently from the Python, on purpose.
        lines.append(b'{"jsonrpc":"2.0","id":1,"method":"ping","x":"\xff"}')
        lines.append(b'{"jsonrpc":"2.0","id":NaN,"method":"ping"}')
        req("tools/call", "x")
        req("initialize", "x")
        call("wiki_read", "x")
        call("wiki_read", {"wiki": "alpha", "path": 5})
        call("wiki_read", {"wiki": 5})
        call("wiki_read", {"wiki": "alpha", "collection": 5})
        call("wiki_search", {"word": 5})
        call("wiki_start", {"repository": ["a"]})
        call("wiki_capture", {"wiki": "alpha", "slug": "x", "note": 5})
        call("wiki_feedback", {"kind": 5})
        lines.append(b'{"jsonrpc":"2.0","id":"nul","method":"tools/call","params":{"name":"wiki_read","arguments":{"wiki":"alpha","path":"a\\u0000b.md"}}}')
        lines.append(b'{"jsonrpc":"2.0","id":"surrogate","method":"tools/call","params":{"name":"wiki_search","arguments":{"word":"\\ud800"}}}')
        lines.append(b'{"jsonrpc":"2.0","id":"nul-word","method":"tools/call","params":{"name":"wiki_search","arguments":{"word":"nul\\u0000byte"}}}')
        lines.append(b"[" * 20000 + b"]" * 20000)
    else:
        sys.exit("no batch " + batch)
    req("ping", id="last")
    sys.stdout.buffer.write(b"\n".join(lines) + b"\n")


def same(a, b):
    x, y = replies(a, True), replies(b, True)
    bad = 0
    if len(x) != len(y):
        print("%d replies and %d" % (len(x), len(y)))
        bad = 1
    for n, (p, q) in enumerate(zip(x, y), 1):
        if p != q:
            bad += 1
            print("reply %d differs:\n  %s\n  %s" % (n, json.dumps(p)[:600], json.dumps(q)[:600]))
    sys.exit(1 if bad else 0)


def client(reqs, out):
    want = []
    for line in open(reqs, "rb").read().split(b"\n"):
        if not line.strip():
            continue
        try:
            # Go reads JSON 10,000 levels deep and no deeper. Python's limit varies.
            if line.count(b"[") + line.count(b"{") > 10000:
                raise ValueError("too deep")
            m = strict(line)
        except (ValueError, RecursionError):  # Not UTF-8, or not JSON: a parse error, which has no id.
            want.append((None, -32700))
            continue
        if isinstance(m, dict) and "id" in m:
            want.append((m["id"], None))
    got = replies(out)
    if len(got) != len(want):
        sys.exit("%d replies to %d requests" % (len(got), len(want)))
    for n, (r, (id, code)) in enumerate(zip(got, want), 1):
        ok = isinstance(r, dict) and r.get("jsonrpc") == "2.0" and "id" in r and r["id"] == id and ("result" in r) != ("error" in r)
        if ok and code:
            ok = r.get("error", {}).get("code") == code
        if ok and "error" in r:
            ok = isinstance(r["error"].get("code"), int) and isinstance(r["error"].get("message"), str)
        if ok and "content" in r.get("result", {}):
            c = r["result"]["content"]
            ok = len(c) == 1 and c[0]["type"] == "text" and isinstance(c[0]["text"], str) and r["result"].get("isError", True) is True
        if not ok:
            sys.exit("reply %d isn't what request %d needs (id %r): %s" % (n, n, id, json.dumps(r)[:400]))


def text(out, id):
    for r in replies(out):
        if r.get("id") == id:
            if "error" in r:
                sys.exit("RPC error: %s" % json.dumps(r["error"]))
            sys.stdout.buffer.write((("ERROR: " if r["result"].get("isError") else "") + r["result"]["content"][0]["text"] + "\n").encode())
            return
    sys.exit("no reply with id " + id)


def codes(out):
    print(" ".join(str(r["error"]["code"]) if "error" in r else "tool-error" if r["result"].get("isError") else "ok" for r in replies(out)))


def files(folders):
    lines = []
    for root in folders:
        for base, dirs, names in os.walk(root):
            dirs[:] = [d for d in dirs if d != ".git"]
            for name in names:
                full = os.path.join(base, name)
                shown = SAME_SECOND.sub(r"\1", CLOCK.sub("TIME", full))
                if os.path.islink(full):
                    lines.append("%s -> %s" % (shown, os.readlink(full)))
                    continue
                try:
                    with open(full, "rb") as f:
                        lines.append("%s %s" % (shown, hashlib.sha256(MINUTE.sub(b"TIME", CLOCK_BYTES.sub(b"TIME", f.read()))).hexdigest()))
                except OSError:
                    lines.append("%s unreadable" % shown)
    # Sorted once the clock is out of the names, or two runs a second apart differ.
    print("\n".join(sorted(lines)))


cmd, args = sys.argv[1], sys.argv[2:]
if cmd == "requests":
    requests(args[0])
elif cmd == "same":
    same(*args)
elif cmd == "client":
    client(*args)
elif cmd == "text":
    text(*args)
elif cmd == "codes":
    codes(*args)
elif cmd == "files":
    files(args)
else:
    sys.exit(__doc__)
PY
  MS="$T/mcp-same.py"
  # Both servers start from the same files: the two collections, and what wiki.sh
  # keeps about this machine.
  MKEPT="$FD|$CW|$HOME/.config/llm-wiki|$HOME/.local/state/llm-wiki"
  mcp_keep() {
    local i=0 d IFS='|'
    rm -rf "$T/mcp-kept"; mkdir -p "$T/mcp-kept"
    for d in $MKEPT; do i=$((i + 1)); [ ! -e "$d" ] || cp -Rp "$d" "$T/mcp-kept/$i"; done
  }
  mcp_back() {
    local i=0 d IFS='|'
    for d in $MKEPT; do i=$((i + 1)); rm -rf "$d"; [ ! -e "$T/mcp-kept/$i" ] || cp -Rp "$T/mcp-kept/$i" "$d"; done
  }
  # mcp_run <py|go> <batch>: one server's replies to a batch, in $T/mcp.<who>.out, its
  # stderr beside them, and what it left behind in $T/mcp.<who>.files. No locale is set,
  # as in the desktop app. The helper's is the spy, so $T/helper-ran says what else ran,
  # and $T/status-ran how each status the helper was asked for ended.
  mcp_run() {
    local who="$1" no=1 go="" d IFS='|'
    [ "$who" = py ] || { no=""; go="$T/bin/status-spy"; }
    mcp_back
    : > "$T/helper-ran"; : > "$T/status-ran"
    python3 "$MS" requests "$2" > "$T/mcp.req"
    (cd "$T" && env -u WIKIS_DIR -u LC_ALL -u LC_CTYPE -u LANG LLM_WIKI_NO_GO="$no" LLM_WIKI_GO="$go" "$W" mcp < "$T/mcp.req" > "$T/mcp.$who.out" 2> "$T/mcp.$who.err")
    # shellcheck disable=SC2086
    python3 "$MS" files $MKEPT > "$T/mcp.$who.files"
  }
  # mcp_same <check> <batch>: both servers answer a batch the same, and leave the same.
  mcp_same() {
    mcp_run py "$2"
    mcp_run go "$2"
    check "$1" python3 "$MS" same "$T/mcp.py.out" "$T/mcp.go.out"
    check "and every reply of the helper's is one line of UTF-8 JSON with the id it was sent, and nothing else" python3 "$MS" client "$T/mcp.req" "$T/mcp.go.out"
    if cmp -s "$T/mcp.py.files" "$T/mcp.go.files" && [ ! -s "$T/mcp.go.err" ]; then ok "and both leave the same files: $2"; else bad "and both leave the same files: $2" "$(diff "$T/mcp.py.files" "$T/mcp.go.files"; cat "$T/mcp.go.err")"; fi
  }
  printf 'carriage, with a return\r\nand a second line\rand a third\n' > "$FD/alpha/wiki/zz-crlf.md"
  # A character cut short in the middle of a line: one U+FFFD to Python, two to Go.
  printf 'brokenarrow: half an arrow \342\206 and on\n' > "$FD/alpha/wiki/zz-broken.md"
  python3 -c 'import sys; e = b"\xc3\xa9".decode(); open(sys.argv[1] + "/fits.md", "w", encoding="utf-8").write(e * 200000); open(sys.argv[1] + "/big.md", "w", encoding="utf-8").write(e * 200000 + "x and more")' "$FD/alpha/wiki"
  # The searches above have recorded that find was used. Not for these runs: each
  # server has to record it.
  MTIPS="$HOME/.config/llm-wiki/tips"
  cp "$MTIPS" "$T/mcp-tips" 2>/dev/null || true; grep -v '^used:find ' "$T/mcp-tips" > "$MTIPS" 2>/dev/null || true
  mcp_keep
  cp -Rp "$T/mcp-kept" "$T/mcp-first"
  # mcp_first: back to the files as they were before the first batch.
  mcp_first() { rm -rf "$T/mcp-kept"; cp -Rp "$T/mcp-first" "$T/mcp-kept"; mcp_back; }
  mcp_same "MCP, helper and Python: the same replies to every request and every tool" same
  check "and the helper's server answered them itself: no wiki.sh find, which, capture or feedback add" bash -c "grep -qx mcp '$T/helper-ran' && ! grep -q -x -e find -e which -e capture -e feedback-add '$T/helper-ran'"
  [ "$(sort -u "$T/status-ran")" = 0 ] && ok "and the helper made the table for each wiki_status" || bad "and the helper made the table for each wiki_status" "$(cat "$T/status-ran" "$T/helper-ran")"
  check "a long word is logged cut at 60 bytes and not inside a character, by the helper's server" grep -E -q ",global,search-none,x($(printf '\303\251')){29}\$" "$FD/stats.csv"
  check "and each search is logged once" bash -c "[ \"\$(grep -c ',search-found,twobyte$' '$FD/stats.csv')\" = 1 ] && [ \"\$(grep -c ',search-none,twobyte$' '$CW/stats.csv')\" = 1 ] && grep -qx \"used:find $(date -u +%Y-%m-%d)\" '$MTIPS'"
  # What a client is owed, whatever the two servers agree on.
  expect "the helper's search cuts a line before a character the 120th byte falls in" "    wiki/long.md: $(printf '%0111d' 0) canary:
notes:" python3 "$MS" text "$T/mcp.go.out" search-canary
  expect "and names each collection" "Collection work:
jobapp:
  also in pages:
    wiki/canary.md: The work canary." python3 "$MS" text "$T/mcp.go.out" search-canary
  expect "bytes that aren't UTF-8 reach a client as U+FFFD, in a search" "- [School](wiki/school.md): $(printf '\303\211cole normale, and caf\357\277\275 in Latin-1')" python3 "$MS" text "$T/mcp.go.out" search-latin
  expect "and in a page" "$(printf 'caf\357\277\275 au lait, in Latin-1')" python3 "$MS" text "$T/mcp.go.out" read-latin
  expect "a character cut short is one U+FFFD, as Python reads it, not one for each byte" "$(printf 'half an arrow \357\277\275 and on')" python3 "$MS" text "$T/mcp.go.out" read-broken
  [ "$(python3 "$MS" text "$T/mcp.go.out" read-crlf)" = "carriage, with a return
and a second line
and a third" ] && ok "a page's line ends reach a client as line feeds" || bad "a page's line ends reach a client as line feeds" "$(python3 "$MS" text "$T/mcp.go.out" read-crlf | od -c | head -n 5)"
  expect "wiki_list counts pages and names collections" "alpha (collection default): 19 page(s)" python3 "$MS" text "$T/mcp.go.out" list

  ln -s ../zlast.md "$FD/alpha/wiki/a/link.md"; echo "very secret" > "$T/secret.md"; ln -s "$T/secret.md" "$FD/alpha/wiki/out.md"
  ln -s "$FD/alpha/wiki/howto" "$FD/alpha/wiki/folder.md"; ln -s nowhere "$FD/alpha/wiki/broken.md"
  printf -- '- caf\351\n' >> "$CW/jobapp/repos.md"
  mcp_keep
  mcp_same "MCP, helper and Python: the same where the helper's server leaves it to wiki.sh" fallback
  check "and there wiki.sh did the search and the routing" bash -c "grep -qx find '$T/helper-ran' && grep -qx which '$T/helper-ran'"
  [ -s "$T/status-ran" ] && ! grep -qx 0 "$T/status-ran" && ok "and the Bash made the status table, with a link under wiki/" || bad "and the Bash made the status table, with a link under wiki/" "$(cat "$T/status-ran")"
  expect "a link inside the wiki is read" "canary, the sixth page, so never shown" python3 "$MS" text "$T/mcp.go.out" read-link
  expect "a link to a file counts as a page, and one to a folder doesn't" "alpha (collection default): 22 page(s)" python3 "$MS" text "$T/mcp.go.out" list
  expect "and a repos.md that isn't UTF-8 is read" "jobapp (collection work): 2 page(s), covers: jobapp-web jobapp-api $(printf 'caf\357\277\275')" python3 "$MS" text "$T/mcp.go.out" list
  expect "wiki_start still finds the collection" "/jobapp, for the repository jobapp-api" python3 "$MS" text "$T/mcp.go.out" start
  check "and wiki.sh logs a long word as the helper's server does" grep -E -q ",global,search-none,x($(printf '\303\251')){29}\$" "$CW/stats.csv"
  rm -f "$T/secret.md" "$T/jobapp-repos"

  mcp_first
  printf 'mode=notes\n' > "$HOME/.config/llm-wiki/feedback"
  # Not as git repositories: a push by the first server would reach the second through
  # its pull. The MCP section has both servers push.
  find "$FD" "$CW" -maxdepth 2 -name .git -prune -exec rm -rf {} +
  mcp_keep
  mcp_same "MCP, helper and Python: the same from the tools that write, and the same notes saved" write
  expect "the helper's wiki_capture saves a note" "-from-chat.md in ~/wikis/alpha" python3 "$MS" text "$T/mcp.go.out" capture
  check "and the note has what was sent" bash -c "grep -q 'With an arrow $(printf '\342\206\222').' '$FD'/alpha/raw/*-from-chat.md"
  expect "the helper's wiki_feedback saves a note" "feedback: saved" python3 "$MS" text "$T/mcp.go.out" feedback
  check "with the agent it was given" bash -c "grep -q '^Agent: Smoke, test model' '$HOME'/.local/state/llm-wiki/feedback/*.md"

  # Where the helper's server answers differently on purpose. Python stops at none of
  # these in the C locale, and answers them with its own exceptions' words.
  mcp_first
  mcp_run go differ
  check "what Python trips over, the helper's server answers as a client needs" python3 "$MS" client "$T/mcp.req" "$T/mcp.go.out"
  [ "$(python3 "$MS" codes "$T/mcp.go.out")" = "-32700 -32700 -32603 -32603 -32603 -32603 -32603 -32603 -32603 -32603 -32603 -32603 tool-error ok -32603 -32700 ok" ] && ok "a parse error for a line that isn't UTF-8 or JSON, an error for a wrong type, and the next request answered" || bad "a parse error for a line that isn't UTF-8 or JSON, an error for a wrong type, and the next request answered" "$(python3 "$MS" codes "$T/mcp.go.out")"
  check "and nothing on stderr" test ! -s "$T/mcp.go.err"
  mcp_first
  [ ! -f "$T/mcp-tips" ] || mv "$T/mcp-tips" "$MTIPS"
  rm -f "$FD/alpha/wiki/fits.md" "$FD/alpha/wiki/big.md" "$FD/alpha/wiki/zz-crlf.md" "$FD/alpha/wiki/zz-broken.md" "$T"/mcp.*.out "$T"/mcp.*.err "$T"/mcp.*.files "$T/mcp.req"; rm -rf "$T/mcp-kept" "$T/mcp-first"
  # capture, from the compiled helper and from the Bash: the same stdout, stderr and
  # exit code, and the same file in raw/, by name, permissions and bytes. The clock in
  # a name is written STAMP, since the two run a moment apart.
  printf '#!/bin/sh\n[ "$1" = capture ] || exec "%s" "$@"\n"%s" "$@"\nrc=$?\necho "$rc" >> "%s"\nexit $rc\n' "$T/bin/llm-wiki" "$T/bin/llm-wiki" "$T/capture-ran" > "$T/bin/capture-spy"
  chmod +x "$T/bin/capture-spy"
  rm -rf "$FD/alpha/raw"; mkdir -p "$FD/alpha/raw" "$T/cap"
  printf 'a note in a file\n' > "$T/cap/note.md"; printf 'Captured: 2020-01-02\n\nit came dated\n' > "$T/cap/dated.md"
  printf 'data\n' > "$T/cap/Two.Dots.TXT"; printf 'plain\n' > "$T/cap/noext"; printf 'KEY=1\n' > "$T/cap/.env"; printf 'x\n' > "$T/cap/end."
  printf '#!/bin/sh\n' > "$T/cap/run.sh"; chmod 755 "$T/cap/run.sh"; : > "$T/cap/empty.md"
  CSTAMP='s/[0-9]\{4\}-[0-9][0-9]-[0-9][0-9]-[0-9]\{6\}-/STAMP-/g'
  # crun <helper> <folder> <stdin's file> <capture's arguments>: capture there with that
  # helper, or with the Bash alone when none is named. Prints stdout, the exit code and
  # what raw/ holds, then empties raw/. stderr goes to $T/capture.err. With CLOCKED set,
  # raw/ can't be written in for the run.
  CLOCKED=""
  crun() {
    local go="$1" dir="$2" in="$3" no=1 f
    shift 3
    [ -z "$go" ] || no=""
    [ -z "$CLOCKED" ] || chmod 555 "$FD/alpha/raw"
    (cd "$dir" && env -u WIKIS_DIR LLM_WIKI_NO_GO="$no" LLM_WIKI_GO="$go" "$W" capture "$@" < "$in" 2>"$T/capture.raw-err"; echo "exit $?") | sed "$CSTAMP"
    sed "$CSTAMP" "$T/capture.raw-err" > "$T/capture.err"
    echo "raw:"
    for f in "$FD/alpha/raw"/*; do
      [ -e "$f" ] || continue
      printf '%s %s %s\n' "$(printf '%s' "${f##*/}" | sed "$CSTAMP")" "$(ls -l "$f" | cut -c1-10)" "$(cksum < "$f")"
    done
    chmod -R u+w "$FD/alpha/raw" 2>/dev/null; rm -rf "$FD/alpha/raw"; mkdir -p "$FD/alpha/raw"
  }
  # csame <check> <helper|bash> <folder> <stdin's file> <capture's arguments>: both say
  # and save the same, and with the helper on, the answer came from the one named.
  csame() {
    local name="$1" who="$2" a b ran
    shift 2
    : > "$T/capture-ran"
    a="$(crun "" "$@")"
    cp "$T/capture.err" "$T/capture.a"
    b="$(crun "$T/bin/capture-spy" "$@")"
    ran="$(cat "$T/capture-ran")"
    case "$who:$ran" in helper:0) ran=helper ;; helper:* | bash: | bash:0) ran="not the $who (the helper's capture ended: ${ran:-never ran})" ;; *) ran=bash ;; esac
    if [ "$a" = "$b" ] && cmp -s "$T/capture.a" "$T/capture.err" && [ "$ran" = "$who" ]; then
      ok "$name"
    else
      bad "$name" "$(printf 'answered by: %s\nBash: %s\n%s\nhelper: %s\n%s' "$ran" "$a" "$(cat "$T/capture.a")" "$b" "$(cat "$T/capture.err")")"
    fi
  }
  csame "capture, helper and Bash: a note on stdin" helper "$T" "$T/cap/note.md" alpha "Decided: Postgres, v2!"
  out="$(crun "$T/bin/capture-spy" "$T" "$T/cap/note.md" alpha "Decided: Postgres, v2!")"
  case "$out" in "captured: raw/STAMP-decided-postgres-v2.md in ~/wikis/alpha"*"exit 0"*"STAMP-decided-postgres-v2.md -rw-r--r-- "*) ok "and the helper names it by the clock and the slug, and dates it" ;; *) bad "and the helper names it by the clock and the slug, and dates it" "$out" ;; esac
  csame "a note that came with its Captured line, kept as it is" helper "$T" "$T/cap/dated.md" alpha dated
  csame "a note in a file" helper "$T/cap" /dev/null alpha from-file --file note.md
  csame "a copy, named for the file" helper "$T/cap" /dev/null alpha --copy Two.Dots.TXT
  csame "a copy with a slug of its own" helper "$T" /dev/null alpha given --copy "$T/cap/Two.Dots.TXT"
  csame "a copy of a file with no extension" helper "$T/cap" /dev/null alpha --copy noext
  csame "of one whose name starts with a dot" helper "$T/cap" /dev/null alpha --copy .env
  csame "of one whose name ends with a dot" helper "$T/cap" /dev/null alpha --copy end.
  csame "and of one that can be run, which the copy can too" helper "$T/cap" /dev/null alpha --copy run.sh
  csame "a wiki named by its path" helper "$T" "$T/cap/note.md" "$FD/alpha" by-path
  # shellcheck disable=SC2088
  csame "by a path from home" helper "$T" "$T/cap/note.md" "~/wikis/./alpha" by-home
  csame "and by a path from here, with dots" helper "$FD/alpha/wiki" "$T/cap/note.md" ../../alpha by-dots
  csame "a slug with letters that aren't ASCII, in a UTF-8 locale" helper "$T" "$T/cap/note.md" alpha "$(printf 'Caf\303\251 \303\211cole')"
  csame "and with a byte that isn't UTF-8" helper "$T" "$T/cap/note.md" alpha "$(printf 'caf\351 au lait')"
  csame "capture refuses, the same from both: no wiki" helper "$T" "$T/cap/note.md"
  csame "a folder that isn't a wiki" helper "$T" "$T/cap/note.md" nowiki slug
  csame "no slug" helper "$T" "$T/cap/note.md" alpha
  csame "a slug with no letters or digits" helper "$T" "$T/cap/note.md" alpha "!!!"
  csame "an empty note" helper "$T" /dev/null alpha empty
  csame "an empty file" helper "$T" /dev/null alpha empty --file "$T/cap/empty.md"
  csame "a file that isn't there" helper "$T" /dev/null alpha gone --file "$T/cap/gone.md"
  csame "a copy of one that isn't there" helper "$T" /dev/null alpha --copy "$T/cap/gone.md"
  csame "--file and --copy together" helper "$T" /dev/null alpha both --file "$T/cap/note.md" --copy "$T/cap/noext"
  csame "--file with nothing after it" helper "$T" /dev/null alpha slug --file
  csame "an option it doesn't have" helper "$T" /dev/null alpha slug --nope
  csame "a third name" helper "$T" "$T/cap/note.md" alpha one two
  csame "an empty name, which the next one fills" helper "$T" "$T/cap/note.md" "" alpha filled
  csame "a slug with a line break, which the Bash answers" bash "$T" "$T/cap/note.md" alpha "two
lines"
  if [ "$(id -u)" != 0 ]; then
    chmod 000 "$T/cap/dated.md"
    csame "a file it can't read, which the Bash answers" bash "$T" /dev/null alpha locked --file "$T/cap/dated.md"
    csame "and a copy of one" helper "$T" /dev/null alpha --copy "$T/cap/dated.md"
    chmod 644 "$T/cap/dated.md"
    CLOCKED=1
    csame "a raw folder it can't write in" helper "$T" "$T/cap/note.md" alpha sandboxed
    lacks "and neither says captured" "captured:" crun "$T/bin/capture-spy" "$T" "$T/cap/note.md" alpha sandboxed
    CLOCKED=""
  else
    skipped "capture where it can't read or write (running as root)"
  fi
  [ "$(crun "$T/bin/broken-helper" "$T" "$T/cap/note.md" alpha fallback)" = "$(crun "" "$T" "$T/cap/note.md" alpha fallback)" ] && ok "a helper that fails leaves capture to the Bash, with the note still on stdin" || bad "a helper that fails leaves capture to the Bash, with the note still on stdin"
  printf '#!/bin/sh\n[ "$1" = protocol ] && { sed -n "s/^GO_PROTOCOL=//p" "%s"; exit 0; }\necho "captured"\n' "$W" > "$T/bin/odd-helper"; chmod +x "$T/bin/odd-helper"
  [ "$(crun "$T/bin/odd-helper" "$T" "$T/cap/note.md" alpha odd)" = "$(crun "" "$T" "$T/cap/note.md" alpha odd)" ] && ok "and an answer with no line to print is passed over" || bad "and an answer with no line to print is passed over"
  rm -rf "$T/cap" "$T/bin/capture-spy" "$T/bin/odd-helper" "$T"/capture.* "$T/capture-ran"
  rm -rf "${FD:?}/alpha" "$FD/Beta" "$FD/notes" "$FD/stray"
  rm -f "$CW/jobapp/wiki/canary.md" "$FD/stats.csv" "$CW/stats.csv"
else
  skipped "the Go helper against the Bash for find (go isn't installed)"
fi
rm -f "$HOME/.config/llm-wiki/collections"
fi

if section "Bash 3.2 safety"; then
lacks "no loop is fed by process substitution, which can end the script on bash 3.2" "done < <(" grep -n "done < <(" "$REPO/wiki.sh" "$REPO/hooks/session-start.sh" "$REPO/hooks/pre-commit" "$REPO/scripts/migrate-to-plugin.sh"
fi

if section "Missing flag values"; then
while IFS= read -r args; do
  # A flag at the end of the line, with its value missing.
  # shellcheck disable=SC2086
  expect "wiki $args says what's missing" "${args##* } needs a value" "$W" $args
done <<EOF
standup --since
standup --save --max
capture demo a-slug --file
capture demo a-slug --copy
log demo ingest --created
log demo ingest --reported
sync demo -m
seed . --wiki
seed . --max
harvest --from
feedback add idea a-summary --agent
journal backfill --since
journal note --day
report --since
tips --repo
tips --mute
EOF
lacks "and every flag's arm in wiki.sh is guarded" "shift" bash -c "grep -E '^ +-[^ )]*\) .*\\\$\{2:-\}.*shift' '$REPO/wiki.sh' | grep -v 'need_value\|die \|die_usage \|needs a name'"
fi

if section "Update"; then
lacks "collections keeps its hint off stdout, for scripts" "Only the default" bash -c "'$W' collections 2>/dev/null"
git -C "$WIKIS_DIR" add -A >/dev/null 2>&1; git -C "$WIKIS_DIR" commit -qm "smoke: before update" >/dev/null 2>&1; git -C "$WIKIS_DIR" push -q >/dev/null 2>&1
set_version "$WIKIS_DIR/demo/AGENTS.md" 1
git -C "$WIKIS_DIR" commit -qam "smoke: an old handbook" >/dev/null 2>&1; git -C "$WIKIS_DIR" push -q >/dev/null 2>&1
out="$("$W" update --wikis-only </dev/null 2>&1)"
case "$out" in *"== Collection here"*"Upgraded"*"pushed"*) ok "update --wikis-only upgrades the collection and pushes" ;; *) bad "update --wikis-only upgrades the collection and pushes" "$out" ;; esac
check "and the upgrade reached the remote" bash -c "git --git-dir='$T/remote.git' log --oneline -1 | grep -q 'handbook v'"
case "$out" in *"paste this into each"*"Run wiki start in this repository"*) ok "update says how to bring open sessions up to date" ;; *) bad "update says how to bring open sessions up to date" "$out" ;; esac
set_version "$WIKIS_DIR/demo/AGENTS.md" 1
expect "upgrade says it too" "paste this into each" "$W" upgrade --all
# A clone: update pulls, then the new version, not the old, does the rest.
U="$T/upd-src"; mkdir -p "$U" && (cd "$REPO" && tar cf - --exclude .git --exclude tests .) | (cd "$U" && tar xf -)
git -C "$U" init -q && git -C "$U" add -A && git -C "$U" commit -qm v1
git clone -q "$U" "$T/upd-clone"
sed -i.bak 's/^update_wikis() {$/update_wikis() {\n  echo "NEW VERSION RAN"/' "$U/wiki.sh" && rm -f "$U/wiki.sh.bak"
git -C "$U" commit -qam v2
out="$("$T/upd-clone/wiki.sh" update </dev/null 2>&1)"
case "$out" in *"pulled"*"NEW VERSION RAN"*) ok "update in a clone pulls, then hands over to the new version" ;; *) bad "update in a clone pulls, then hands over to the new version" "$out" ;; esac
# With the plugin also installed, update refreshes its copy, which needs a restart.
mkdir -p "$HOME/.claude/plugins" "$HOME/.cursor"
printf '{"version":2,"plugins":{"llm-wiki@mk":[{"scope":"user","installPath":"%s"}]}}\n' "$T/upd-clone" > "$HOME/.claude/plugins/installed_plugins.json"
printf '#!/bin/sh\nexit 0\n' > "$T/bin/claude" && chmod +x "$T/bin/claude"
out="$(PATH="$T/bin:$PATH" "$T/upd-clone/wiki.sh" update </dev/null 2>&1)"
case "$out" in *"updated the installed plugin's copy (llm-wiki@mk)"*"Quit and reopen the Claude app and Cursor"*) ok "update in a clone refreshes the plugin's copy and says to restart Claude and Cursor" ;; *) bad "update in a clone refreshes the plugin's copy and says to restart Claude and Cursor" "$out" ;; esac
rm -rf "$HOME/.cursor" "$HOME/.claude/plugins/installed_plugins.json" "$T/bin/claude"

# setup microsoft-copilot, with a fake GitHub, gh, browser and Microsoft toolkit.
MC="$T/mc"; mkdir -p "$MC/bin"
cat > "$MC/github.py" <<'EOF'
import json, socketserver, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
class H(BaseHTTPRequestHandler):
    def log_message(self, *_): pass
    def do_POST(self):
        body = {"client_id": "Iv1.fakeid", "client_secret": "real-secret-4242", "slug": "fake-slug", "pem": "pem-4242", "webhook_secret": "hook-4242"}
        status = 201 if self.path == "/app-manifests/goodcode/conversions" else 404
        data = json.dumps(body if status == 201 else {}).encode()
        self.send_response(status); self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)
class S(HTTPServer):
    def server_bind(self):
        socketserver.TCPServer.server_bind(self)  # skip the reverse-DNS lookup HTTPServer does
s = S(("127.0.0.1", 0), H)
open(sys.argv[1], "w").write(str(s.server_address[1]))
s.serve_forever()
EOF
python3 "$MC/github.py" "$MC/port" & MC_PID=$!
i=0; while [ ! -s "$MC/port" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
# The fake browser does what GitHub would: reads the form, tries a wrong state, then redirects.
cat > "$MC/browser.py" <<'EOF'
import html, json, os, re, sys, urllib.error, urllib.parse, urllib.request
mc, url = sys.argv[1], sys.argv[2]
open(mc + "/opened", "a").write(url + "\n")
if not url.endswith("/start"):
    sys.exit(0)
page = urllib.request.urlopen(url).read().decode()
manifest = json.loads(html.unescape(re.search(r'name="manifest" value="([^"]*)"', page).group(1)))
json.dump(manifest, open(mc + "/manifest.json", "w"))
open(mc + "/action", "w").write(html.unescape(re.search(r'action="([^"]*)"', page).group(1)))
state = urllib.parse.parse_qs(urllib.parse.urlparse(html.unescape(re.search(r'action="([^"]*)"', page).group(1))).query)["state"][0]
try:
    urllib.request.urlopen(manifest["redirect_url"] + "?code=goodcode&state=wrong")
except urllib.error.HTTPError as e:
    open(mc + "/wrong-state", "w").write(str(e.code))
urllib.request.urlopen(manifest["redirect_url"] + "?code=goodcode&state=" + state)
EOF
printf '#!/bin/sh\nexec python3 "%s/browser.py" "%s" "$1"\n' "$MC" "$MC" > "$MC/open"; chmod +x "$MC/open"
cat > "$MC/bin/gh" <<'EOF'
#!/bin/sh
case "$*" in
  "repo view"*) echo '{"isPrivate": true}' ;;
  *git/trees*) [ -z "$MC_TREE" ] || { echo "$MC_TREE"; exit 0; }; echo '{"tree": [{"path": "index.md"}, {"path": "work/index.md"}, {"path": "work/wiki/a.md"}, {"path": "global/index.md"}, {"path": "journal/x.md"}, {"path": ".github/x"}]}' ;;
  "api users/"*) echo '{"type": "User"}' ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$MC/bin/gh"
cat > "$MC/atk" <<'EOF'
#!/bin/sh
echo "$*" >> "$MC/atk.log"
case "$1" in
  new)
    while [ $# -gt 0 ]; do case "$1" in -n) n="$2" ;; -f) f="$2" ;; esac; shift; done
    mkdir -p "$f/$n/appPackage" "$f/$n/env"
    printf 'SECRET_MCP_DA_OAUTH_CLIENT_SECRET_APIGITHUBC=crypto_abc\n' > "$f/$n/env/.env.dev.user"
    printf 'sample\n' > "$f/$n/appPackage/instruction.txt"
    printf '{"name": "x", "instructions": "$[file(%sinstruction.txt%s)]", "actions": [{"id": "a"}]}\n' "'" "'" > "$f/$n/appPackage/declarativeAgent.json"
    ;;
  provision)
    while [ $# -gt 0 ]; do [ "$1" = -f ] && p="$2"; shift; done
    cp "$p/env/.env.dev.user" "$MC/env-at-provision"
    [ -z "$MC_FAIL" ] || exit 1
    ;;
esac
EOF
chmod +x "$MC/atk"
mc_run() { env MC="$MC" MC_FAIL="${MC_FAIL:-}" MC_TREE="${MC_TREE:-}" PATH="$MC/bin:$PATH" LLM_WIKI_TEST_TTY=1 LLM_WIKI_OPEN="$MC/open" LLM_WIKI_ATK="$MC/atk" LLM_WIKI_GITHUB_API="http://127.0.0.1:$(cat "$MC/port")" LLM_WIKI_APP_WAIT=20 "$W" setup microsoft-copilot "$@"; }
out="$(env LLM_WIKI_ATK="$MC/atk" "$W" setup microsoft-copilot --repo a/b </dev/null 2>&1)" && bad "setup microsoft-copilot needs a terminal" "$out" || case "$out" in *"Agents: tell the user to run it"*) ok "setup microsoft-copilot needs a terminal" ;; *) bad "setup microsoft-copilot needs a terminal" "$out" ;; esac
out="$(printf 'n\n' | mc_run --repo acme/wikis --dir "$MC/a" 2>&1)"
case "$out" in *"could read: global, journal, work"*"Stopped. Nothing was changed."*) ok "it names what the agent could read, and a no stops it" ;; *) bad "it names what the agent could read, and a no stops it" "$out" ;; esac
check "a no opens nothing" test ! -e "$MC/opened"
check "a no generates nothing" test ! -e "$MC/a"
out="$(printf 'y\n\n' | mc_run --repo acme/wikis --wiki work --name notes --dir "$MC/a" 2>&1)"
case "$out" in *"Done. To try it"*"notesdev"*) ok "it runs through to the agent's name" ;; *) bad "it runs through to the agent's name" "$out" ;; esac
case "$out" in *real-secret-4242*|*pem-4242*|*hook-4242*) bad "it never prints the secrets" "$out" ;; *) ok "it never prints the secrets" ;; esac
check "the wrong state is refused" grep -qx 400 "$MC/wrong-state"
check "the app reads only, with no webhook, and stays private" python3 -c "import json,sys; m=json.load(open(sys.argv[1])); assert m['default_permissions']=={'contents':'read','metadata':'read'} and m['hook_attributes']['active'] is False and m['public'] is False and m['default_events']==[]" "$MC/manifest.json"
check "its callback is Microsoft's" python3 -c "import json,sys; assert json.load(open(sys.argv[1]))['callback_urls']==['https://teams.microsoft.com/api/platform/v1.0/oAuthRedirect']" "$MC/manifest.json"
check "it opens the app's install page" grep -q 'github.com/apps/fake-slug/installations/new' "$MC/opened"
check "the agent uses the read-only server" grep -q -- '--mcp-da-server-url https://api.githubcopilot.com/mcp/x/repos/readonly' "$MC/atk.log"
check "the toolkit gets the client ID" grep -q -- '--mcp-da-client-id Iv1.fakeid' "$MC/atk.log"
if grep -q 'real-secret-4242' "$MC/atk.log"; then bad "the secret stays off the command line" "$(cat "$MC/atk.log")"; else ok "the secret stays off the command line"; fi
check "provisioning sees the real secret" grep -qx 'SECRET_MCP_DA_OAUTH_CLIENT_SECRET_APIGITHUBC=real-secret-4242' "$MC/env-at-provision"
check "afterwards the secret is gone from disk, leaving a value the toolkit accepts" grep -qx 'SECRET_MCP_DA_OAUTH_CLIENT_SECRET_APIGITHUBC=cleared-after-provisioning' "$MC/a/notes/env/.env.dev.user"
if grep -rq -e 'pem-4242' -e 'hook-4242' "$MC/a"; then bad "the app's private key is never saved" "found"; else ok "the app's private key is never saved"; fi
check "the instructions name the repository and the wiki's index" grep -q 'repository acme/wikis.*' "$MC/a/notes/appPackage/instruction.txt"
check "they start from the wiki named" grep -q 'read work/index.md with get_file_contents' "$MC/a/notes/appPackage/instruction.txt"
check "the agent keeps its action" python3 -c "import json,sys; a=json.load(open(sys.argv[1])); assert a['actions'] and 'acme/wikis' in a['description']" "$MC/a/notes/appPackage/declarativeAgent.json"
expect "it won't overwrite a project" "already exists" bash -c "printf 'y\n\n' | env MC='$MC' PATH='$MC/bin:$PATH' LLM_WIKI_TEST_TTY=1 LLM_WIKI_ATK='$MC/atk' '$W' setup microsoft-copilot --repo acme/wikis --name notes --dir '$MC/a' 2>&1 || true"
out="$(printf 'y\n\n' | MC_FAIL=1 mc_run --repo acme/wikis --name failed --dir "$MC/a" 2>&1)" && bad "a failed provision says so" "$out" || case "$out" in *"Provisioning failed"*"provision --env dev"*) ok "a failed provision says how to retry" ;; *) bad "a failed provision says how to retry" "$out" ;; esac
check "a failed provision keeps the secret for the retry" grep -qx 'SECRET_MCP_DA_OAUTH_CLIENT_SECRET_APIGITHUBC=real-secret-4242' "$MC/a/failed/env/.env.dev.user"
check "only the owner can read that file" python3 -c "import os,stat,sys; assert stat.S_IMODE(os.stat(sys.argv[1]).st_mode)==0o600" "$MC/a/failed/env/.env.dev.user"
check "with no wiki named, it starts from the top index, not every index" grep -q 'read index.md with get_file_contents' "$MC/a/failed/appPackage/instruction.txt"
check "it names the other wikis" grep -q 'in its own folder with an index.md: global, work' "$MC/a/failed/appPackage/instruction.txt"
out="$(printf 'y\n\n' | MC_TREE='{"tree": [{"path": "global/index.md"}, {"path": "a/index.md"}, {"path": "b/index.md"}]}' mc_run --repo acme/wikis --name shared --dir "$MC/a" 2>&1)"
case "$out" in *"starts from: global/index.md."*) ok "with a shared wiki, it says it starts there" ;; *) bad "with a shared wiki, it says it starts there" "$out" ;; esac
check "with a shared wiki, it reads that index first" grep -q 'read global/index.md with get_file_contents' "$MC/a/shared/appPackage/instruction.txt"
check "the others are named, and never all read" grep -q 'index.md: a, b\. When a question is about one of them.*Never read every index' "$MC/a/shared/appPackage/instruction.txt"
printf 'y\n\n' | MC_TREE='{"tree": [{"path": "a/index.md"}, {"path": "b/index.md"}]}' mc_run --repo acme/wikis --name noshared --dir "$MC/a" >/dev/null 2>&1
check "with no shared wiki, it picks by the question" grep -q 'pick the wiki it.s about, and read only that wiki.s index.md' "$MC/a/noshared/appPackage/instruction.txt"
out="$(printf 'y\nIv1.byhand\nhand-secret-4242\n\n' | mc_run --repo acme/wikis --name byhand --dir "$MC/a" --manual 2>&1)"
case "$out" in *"contents=read"*"Done. To try it"*) ok "--manual prints the pre-filled link and takes pasted values" ;; *) bad "--manual prints the pre-filled link and takes pasted values" "$out" ;; esac
case "$out" in *hand-secret-4242*) bad "--manual doesn't echo the secret" "$out" ;; *) ok "--manual doesn't echo the secret" ;; esac
check "--manual uses the pasted client ID" grep -q -- '--mcp-da-client-id Iv1.byhand' "$MC/atk.log"
# --update: the same agent, with current instructions, no clicks and no new sign-in registration.
out="$(printf '\n' | mc_run --update --name missing --dir "$MC/a" 2>&1)" && bad "--update needs an agent to exist" "$out" || case "$out" in *"no agent at"*"machine that created it"*) ok "--update needs an agent to exist" ;; *) bad "--update needs an agent to exist" "$out" ;; esac
: > "$MC/opened"; : > "$MC/atk.log"
out="$(MC_TREE='{"tree": [{"path": "global/index.md"}, {"path": "a/index.md"}, {"path": "b/index.md"}, {"path": "newwiki/index.md"}]}' mc_run --update --name shared --dir "$MC/a" </dev/null 2>&1)"
case "$out" in *"Updating the agent for acme/wikis"*"Start a new chat from shareddev"*) ok "--update remembers the repository and finishes" ;; *) bad "--update remembers the repository and finishes" "$out" ;; esac
check "--update picks up a new wiki" grep -q 'index.md: a, b, newwiki\.' "$MC/a/shared/appPackage/instruction.txt"
if grep -q '^new ' "$MC/atk.log"; then bad "--update generates nothing new" "$(cat "$MC/atk.log")"; else ok "--update generates nothing new"; fi
check "--update provisions" grep -q '^provision ' "$MC/atk.log"
check "--update opens no pages" test ! -s "$MC/opened"
check "--update leaves no secret behind" grep -qx 'SECRET_MCP_DA_OAUTH_CLIENT_SECRET_APIGITHUBC=cleared-after-provisioning' "$MC/a/shared/env/.env.dev.user"
sed -i.bak 's/^\(SECRET_MCP_DA_OAUTH_CLIENT_SECRET_APIGITHUBC\)=.*/\1=/' "$MC/a/notes/env/.env.dev.user"; rm -f "$MC/a/notes/.llm-wiki.json"
out="$(mc_run --update --name notes --dir "$MC/a" </dev/null 2>&1)" && bad "an older agent asks for its repository once" "$out" || case "$out" in *"name its repository once with --repo"*) ok "an older agent asks for its repository once" ;; *) bad "an older agent asks for its repository once" "$out" ;; esac
mc_run --update --name notes --dir "$MC/a" --repo acme/wikis --wiki work </dev/null >/dev/null 2>&1
check "provisioning an older agent sees a value, not a blank" grep -qx 'SECRET_MCP_DA_OAUTH_CLIENT_SECRET_APIGITHUBC=cleared-after-provisioning' "$MC/env-at-provision"
check "--update saves settings for next time" python3 -c "import json,sys; s=json.load(open(sys.argv[1])); assert s=={'repo':'acme/wikis','wikis':['work']}" "$MC/a/notes/.llm-wiki.json"
expect "a second setup points at --update" "add --update" bash -c "printf 'y\n\n' | env MC='$MC' PATH='$MC/bin:$PATH' LLM_WIKI_TEST_TTY=1 LLM_WIKI_ATK='$MC/atk' '$W' setup microsoft-copilot --repo acme/wikis --name notes --dir '$MC/a' 2>&1 || true"
kill "$MC_PID" 2>/dev/null; wait "$MC_PID" 2>/dev/null || true
fi

if section "News"; then
N="$T/news"; mkdir -p "$N/state"
printf '# News\n\n## 2026-01-02: Second\n\nSecond body.\n\n- Do: second step.\n\n## 2026-01-01: First\n\nFirst body.\n' > "$N/NEWS.md"
news() { env XDG_STATE_HOME="$N/state" LLM_WIKI_NEWS_FILE="$N/NEWS.md" "$W" "$@"; }
out="$(news status 2>&1)"
case "$out" in *"llm-wiki: 1 new thing(s) to read about. Run: "*" news"*) ok "status says when there's news, with what to run" ;; *) bad "status says when there's news, with what to run" "$out" ;; esac
out="$(news news 2>&1)"
case "$out" in *"Second body"*"second step"*) ok "a first run prints the latest entry" ;; *) bad "a first run prints the latest entry" "$out" ;; esac
case "$out" in *"First body"*) bad "a first run skips the history" "$out" ;; *) ok "a first run skips the history" ;; esac
case "$(news status 2>&1)" in *"to read about"*) bad "status goes quiet once it's read" "" ;; *) ok "status goes quiet once it's read" ;; esac
expect "with nothing new, news says how to see it all" "Nothing new since you last looked" env XDG_STATE_HOME="$N/state" LLM_WIKI_NEWS_FILE="$N/NEWS.md" "$W" news
expect "--all prints the history" "First body" env XDG_STATE_HOME="$N/state" LLM_WIKI_NEWS_FILE="$N/NEWS.md" "$W" news --all
printf '# News\n\n## 2026-01-04: Fourth\n\nFourth body.\n\n## 2026-01-03: Third\n\nThird body.\n\n## 2026-01-02: Second\n\nSecond body.\n' > "$N/NEWS.md"
case "$(news status 2>&1)" in *"llm-wiki: 2 new thing(s)"*) ok "status counts what's new since the last read" ;; *) bad "status counts what's new since the last read" "$(news status 2>&1)" ;; esac
out="$(news update --wikis-only 2>&1 </dev/null)"
case "$out" in *"What's new in llm-wiki"*"Fourth body"*"Third body"*"== Next"*) ok "update prints what's new since the last read" ;; *) bad "update prints what's new since the last read" "$out" ;; esac
case "$out" in *"Second body"*) bad "update leaves out what's been read" "$out" ;; *) ok "update leaves out what's been read" ;; esac
case "$(news news 2>&1)" in *"Nothing new"*) ok "update marks it read" ;; *) bad "update marks it read" "" ;; esac
printf '# News\n\n## 2026-01-05: Renamed\n\nBody.\n' > "$N/NEWS.md"
case "$(news status 2>&1)" in *"to read about"*) bad "a heading that's gone counts as nothing new" "" ;; *) ok "a heading that's gone counts as nothing new" ;; esac
if [ "$(id -u)" != 0 ]; then
  printf '# News\n\n## 2026-01-06: Sixth\n\nBody.\n\n## 2026-01-05: Renamed\n\nBody.\n' > "$N/NEWS.md"
  news news >/dev/null 2>&1
  chmod 000 "$N/state/llm-wiki/news-seen"
  out="$(news status 2>&1)"
  case "$out" in *"ermission denied"* | *"to read about"*) bad "a marker it can't read counts as nothing new, with no raw error" "$out" ;; *) ok "a marker it can't read counts as nothing new, with no raw error" ;; esac
  chmod 644 "$N/state/llm-wiki/news-seen"
else
  skipped "a news marker that can't be read (root can read anything)"
fi
check "news without a NEWS.md stays quiet" env XDG_STATE_HOME="$N/none" LLM_WIKI_NEWS_FILE="$N/none.md" "$W" status
check "NEWS.md entries are dated, with different titles" python3 -c "
import re,sys
h=[l for l in open(sys.argv[1]) if l.startswith('## ')]
assert h and all(re.match(r'## \d{4}-\d\d-\d\d: \S', l) for l in h) and len(set(h))==len(h)
d=[l[3:13] for l in h]
assert d==sorted(d,reverse=True)" "$REPO/NEWS.md"
# wiki update prints every entry a user hasn't seen, as it is. An entry is one line for
# each change they would notice, and nothing else.
out="$(python3 -c "
import sys
entry, lines = None, {}
for l in open(sys.argv[1]):
    l = l.rstrip('\n')
    if l.startswith('## '):
        entry = l; lines[entry] = []
    elif entry and l:
        lines[entry].append(l)
for e, ls in lines.items():
    for l in ls:
        if not l.startswith('- '): print('not a one-line item, in %s: %s' % (e, l[:60]))
        elif len(l) > 160: print('%d characters, in %s: %s' % (len(l), e, l[:60]))
    if not ls: print('nothing under %s' % e)
    if len(ls) > 4: print('%d lines under %s' % (len(ls), e))
" "$REPO/NEWS.md")"
[ -z "$out" ] && ok "NEWS.md entries are one line per change, four at most" || bad "NEWS.md entries are one line per change, four at most" "$out"
fi

if section "Terminal style"; then
SW="$T/style"; mkdir -p "$SW/wikis"
sty() { env WIKIS_DIR="$SW/wikis" "$@"; }
"$W" new "$SW/wikis/demo" >/dev/null 2>&1
for i in 1 2 3 4 5 6; do printf 'note %s\n' "$i" > "$SW/wikis/demo/raw/2026-11-0$i-n$i.md"; done
ESC=$'\033'
strip() { sed "s/${ESC}\\[[0-9;]*m//g"; }
plain="$(sty LLM_WIKI_STYLE=off "$W" status 2>&1)"
styled="$(sty LLM_WIKI_STYLE=on LANG=en_US.UTF-8 "$W" status 2>&1)"
case "$styled" in *"${ESC}[1mWIKI"*) ok "forced on, status's header is bold" ;; *) bad "forced on, status's header is bold" "$styled" ;; esac
case "$styled" in *"${ESC}[33m  <- compile due${ESC}[0m"*) ok "the <- notes are yellow" ;; *) bad "the <- notes are yellow" "$styled" ;; esac
case "$styled" in *"${ESC}[1m${ESC}[33m!${ESC}[0m demo: 6 notes waiting."*) ok "a To do line starts with the bold yellow warning mark" ;; *) bad "a To do line starts with the bold yellow warning mark" "$styled" ;; esac
case "$styled" in *"Ask an agent: ${ESC}[36m\"compile demo\"${ESC}[0m"*"Run: ${ESC}[36m"*) ok "the quoted request and what follows Run: are cyan" ;; *) bad "the quoted request and what follows Run: are cyan" "$styled" ;; esac
case "$plain" in *"${ESC}"*) bad "off, status has no codes" "$plain" ;; *) ok "off, status has no codes" ;; esac
case "$(printf '%s' "$plain" | sty "$W" status 2>&1)" in *"${ESC}"*) bad "piped, status has no codes" ;; *) ok "piped, status has no codes" ;; esac
nomark="$(printf '%s\n' "$styled" | strip | sed 's/^! /- /')"
[ "$nomark" = "$plain" ] && ok "with the codes stripped, and the mark back to '- ', the words are the plain words" || bad "with the codes stripped, the words are the plain words" "$(diff <(printf '%s\n' "$nomark") <(printf '%s\n' "$plain"))"
out="$(sty LLM_WIKI_STYLE=on NO_COLOR=1 "$W" status 2>&1)"
case "$out" in *"${ESC}["*) ok "LLM_WIKI_STYLE=on wins over NO_COLOR" ;; *) bad "LLM_WIKI_STYLE=on wins over NO_COLOR" "$out" ;; esac
out="$(sty -u LLM_WIKI_STYLE NO_COLOR=1 TERM=xterm "$W" status 2>&1)"
case "$out" in *"${ESC}"*) bad "NO_COLOR alone keeps status plain" "$out" ;; *) ok "NO_COLOR alone keeps status plain" ;; esac
case "$(sty LLM_WIKI_STYLE=on LANG=en_US.UTF-8 "$W" status 2>&1)" in *"✓"*) bad "status has no tick to translate, only the warning mark" ;; *) ok "status has no tick to translate, only the warning mark" ;; esac
# An agent's shell can be a pseudo-terminal, so commands an agent reads ignore the override.
for c in "start demo" "find note" "which demo" "pending" "patterns" "capture demo --help" "report"; do
  out="$(sty LLM_WIKI_STYLE=on "$W" $c 2>&1 || true)"
  case "$out" in *"${ESC}["*) bad "'$c' stays plain even when style is forced on" "$out" ;; *) ok "'$c' stays plain even when style is forced on" ;; esac
done
out="$(sty LLM_WIKI_STYLE=on "$W" capture 2>&1 || true)"
case "$out" in *"${ESC}["*) bad "an error from an agent-read command stays plain" "$out" ;; *) ok "an error from an agent-read command stays plain" ;; esac
out="$(sty LLM_WIKI_STYLE=on "$W" stale x 2>&1 || true)"
case "$out" in *"${ESC}[31merror:${ESC}[0m"*) ok "an error from a command a person runs has error: in red" ;; *) bad "an error from a command a person runs has error: in red" "$out" ;; esac
out="$(sty LLM_WIKI_STYLE=off "$W" stale x 2>&1 || true)"
case "$out" in "error: "*) ok "off, an error is plain" ;; *) bad "off, an error is plain" "$out" ;; esac
# The tick: ✓ in a UTF-8 locale, + in any other.
blk="$(sed -n '/^# --- style helpers/,/^# --- end of style helpers/p' "$W")"
tick() { env "$@" LLM_WIKI_STYLE=on bash -c "$blk"$'\n''say_ok done' | strip; }
[ "$(tick LC_ALL=en_US.UTF-8)" = "✓ done" ] && ok "a UTF-8 locale gets ✓" || bad "a UTF-8 locale gets ✓" "$(tick LC_ALL=en_US.UTF-8)"
[ "$(tick LC_ALL=C)" = "+ done" ] && ok "a locale that isn't UTF-8 gets +" || bad "a locale that isn't UTF-8 gets +" "$(tick LC_ALL=C)"
[ "$(tick LC_ALL= LC_CTYPE= LANG=)" = "+ done" ] && ok "no locale set gets +" || bad "no locale set gets +" "$(tick LC_ALL= LC_CTYPE= LANG=)"
# wiki setup, in its forms. A mark goes in front of a line, after any indent. With the
# codes stripped and the marks taken off, what a terminal shows is the piped words.
nomarks() { strip | sed -E 's/(^|  )(✓|\+|!) /\1/'; }
UTF="LANG=en_US.UTF-8"
lplain="$(sty LLM_WIKI_STYLE=off "$W" setup --list 2>&1)"
lstyled="$(sty LLM_WIKI_STYLE=on "$W" setup --list 2>&1)"
case "$lstyled" in *"${ESC}[33m  <- new${ESC}[0m"*) ok "setup --list: the <- new markers are yellow" ;; *) bad "setup --list: the <- new markers are yellow" "$lstyled" ;; esac
case "$lstyled" in *"${ESC}[2m  (default)${ESC}[0m"*) ok "setup --list: (default) is dim, an aside" ;; *) bad "setup --list: (default) is dim, an aside" "$lstyled" ;; esac
case "$lstyled" in *"Change one:    ${ESC}[36m"*"git.identity${ESC}[0m"*) ok "setup --list: the commands on the Change one line are cyan" ;; *) bad "setup --list: the commands on the Change one line are cyan" "$lstyled" ;; esac
case "$lstyled" in *"Or a section:  ${ESC}[36m"*"microsoft-copilot${ESC}[0m"*) ok "setup --list: the Or a section line is cyan" ;; *) bad "setup --list: the Or a section line is cyan" "$lstyled" ;; esac
case "$lplain" in *"Run: "*) case "$lstyled" in *"Run: ${ESC}[36m"*) ok "setup --list: a Run: command is cyan" ;; *) bad "setup --list: a Run: command is cyan" "$lstyled" ;; esac ;; *) ok "setup --list: no Run: to be cyan on this machine" ;; esac
[ "$(printf '%s\n' "$lstyled" | strip)" = "$lplain" ] && ok "setup --list: with the codes stripped, the words are the plain words" || bad "setup --list: with the codes stripped, the words are the plain words" "$(diff <(printf '%s\n' "$lstyled" | strip) <(printf '%s\n' "$lplain"))"
case "$lplain" in *"${ESC}"*) bad "setup --list: off has no codes" ;; *) ok "setup --list: off has no codes" ;; esac
case "$(sty -u LLM_WIKI_STYLE "$W" setup --list 2>&1)" in *"${ESC}"*) bad "setup --list: piped has no codes" ;; *) ok "setup --list: piped has no codes" ;; esac
# A section: the heading is bold, a line that says something was done has the tick.
fplain="$(printf 'off\n' | sty LLM_WIKI_TEST_TTY=1 LLM_WIKI_STYLE=off "$W" setup feedback 2>&1)"
fstyled="$(printf 'off\n' | sty LLM_WIKI_TEST_TTY=1 LLM_WIKI_STYLE=on $UTF "$W" setup feedback 2>&1)"
case "$fstyled" in *"${ESC}[1m== Feedback on llm-wiki${ESC}[0m"*) ok "setup <section>: the heading is bold, with its ==" ;; *) bad "setup <section>: the heading is bold, with its ==" "$fstyled" ;; esac
case "$fstyled" in *"✓"*"feedback: off"*) bad "setup <section>: a no answer's off line has no tick" "$fstyled" ;; *"feedback: off"*) ok "setup <section>: a no answer's off line has no tick" ;; *) bad "setup <section>: a no answer's off line has no tick (no line)" "$fstyled" ;; esac
fyes="$(printf 'notes\n' | sty LLM_WIKI_TEST_TTY=1 LLM_WIKI_STYLE=on $UTF "$W" setup feedback 2>&1)"
case "$fyes" in *"${ESC}[32m✓${ESC}[0m feedback: notes"*) ok "setup <section>: what was written has a green tick" ;; *) bad "setup <section>: what was written has a green tick" "$fyes" ;; esac
printf 'off\n' | sty LLM_WIKI_TEST_TTY=1 LLM_WIKI_STYLE=off "$W" setup feedback >/dev/null 2>&1
case "$fstyled" in *"${ESC}[32m✓${ESC}[0m Done. "*) ok "setup <section>: the closing Done has the tick" ;; *) bad "setup <section>: the closing Done has the tick" "$fstyled" ;; esac
case "$fstyled" in *"Feedback [off]: "*) ok "setup <section>: a prompt keeps its words, the default undimmed" ;; *) bad "setup <section>: a prompt keeps its words, the default undimmed" "$fstyled" ;; esac
[ "$(printf '%s\n' "$fstyled" | nomarks)" = "$fplain" ] && ok "setup <section>: stripped, with the marks off, the words are the plain words" || bad "setup <section>: stripped, with the marks off, the words are the plain words" "$(diff <(printf '%s\n' "$fstyled" | nomarks) <(printf '%s\n' "$fplain"))"
case "$fplain" in *"${ESC}"*) bad "setup <section>: off has no codes" ;; *) ok "setup <section>: off has no codes" ;; esac
case "$(printf 'off\n' | sty -u LLM_WIKI_STYLE LLM_WIKI_TEST_TTY=1 "$W" setup feedback 2>&1)" in *"${ESC}"*) bad "setup <section>: piped has no codes" ;; *) ok "setup <section>: piped has no codes" ;; esac
# A failure has the warning mark, and the command that fixes it is cyan.
SG="$T/style-git"; mkdir -p "$SG"
git -C "$SG" init -q && git -C "$SG" config user.name t && git -C "$SG" config --local user.email t@example.test
git -C "$SG" commit -q --allow-empty -m x && git -C "$SG" remote add origin "$T/no-such-remote.git"
gplain="$(printf '\ny\n' | sty WIKIS_DIR="$SG" LLM_WIKI_TEST_TTY=1 LLM_WIKI_STYLE=off "$W" setup git.identity 2>&1)"
gstyled="$(printf '\ny\n' | sty WIKIS_DIR="$SG" LLM_WIKI_TEST_TTY=1 LLM_WIKI_STYLE=on $UTF "$W" setup git.identity 2>&1)"
case "$gstyled" in *"  ${ESC}[1m${ESC}[33m!${ESC}[0m push failed:"*) ok "setup: a failure has the bold yellow warning mark" ;; *) bad "setup: a failure has the bold yellow warning mark" "$gstyled" ;; esac
case "$gstyled" in *"Then run the test again: ${ESC}[36mwiki setup git.identity${ESC}[0m"* | *"Then run the test again: ${ESC}[36m"*"setup git.identity${ESC}[0m"*) ok "setup: the command that fixes it is cyan" ;; *) bad "setup: the command that fixes it is cyan" "$gstyled" ;; esac
[ "$(printf '%s\n' "$gstyled" | nomarks)" = "$gplain" ] && ok "setup git.identity: stripped, with the marks off, the words are the plain words" || bad "setup git.identity: stripped, with the marks off, the words are the plain words" "$(diff <(printf '%s\n' "$gstyled" | nomarks) <(printf '%s\n' "$gplain"))"
# A setting, and the whole walkthrough and --new, each on a fresh machine and the same answers.
walk() { # walk <style> <args...>: setup on a new HOME with the answers all Enter
  local st="$1"; shift
  rm -rf "$SW/walk"; mkdir -p "$SW/walk/home"
  printf '[user]\n\tname = t\n\temail = t@example.test\n' > "$SW/walk/home/.gitconfig"
  printf '%.0s\n' $(seq 1 200) | env -u WIKIS_DIR HOME="$SW/walk/home" XDG_CONFIG_HOME="$SW/walk/home/.config" XDG_STATE_HOME="$SW/walk/state" \
    PATH="/usr/bin:/bin" LLM_WIKI_NO_GO=1 LLM_WIKI_TEST_TTY=1 LLM_WIKI_STYLE="$st" $UTF "$W" setup "$@" 2>&1
}
for form in "" "--new" "format"; do
  wplain="$(walk off $form)"; wstyled="$(walk on $form)"
  [ -n "$wplain" ] && [ "$(printf '%s\n' "$wstyled" | nomarks)" = "$wplain" ] && ok "setup ${form:-(everything)}: stripped, with the marks off, the words are the plain words" || bad "setup ${form:-(everything)}: stripped, with the marks off, the words are the plain words" "$(diff <(printf '%s\n' "$wstyled" | nomarks) <(printf '%s\n' "$wplain") | head -n 20)"
  case "$wstyled" in *"${ESC}[1m== "*) ok "setup ${form:-(everything)}: headings are bold" ;; *) [ "$form" = format ] && ok "setup format has no heading to style" || bad "setup ${form:-(everything)}: headings are bold" "$wstyled" ;; esac
  case "$wplain" in *"${ESC}"*) bad "setup ${form:-(everything)}: off has no codes" ;; *) ok "setup ${form:-(everything)}: off has no codes" ;; esac
done
# wiki update, with a wiki that has a remote, an old handbook and a NEWS entry to print.
UW="$T/style-up"; mkdir -p "$UW"
git init -q --bare "$UW/remote.git"
mkdir -p "$UW/wikis"; "$W" new "$UW/wikis/demo" >/dev/null 2>&1
git -C "$UW/wikis" init -q && git -C "$UW/wikis" config user.name t && git -C "$UW/wikis" config user.email t@example.test
git -C "$UW/wikis" add -A && git -C "$UW/wikis" commit -qm start && git -C "$UW/wikis" remote add origin "$UW/remote.git" && git -C "$UW/wikis" push -q -u origin HEAD 2>/dev/null
printf '# News\n\n## 2026-01-02: Second `entry`\n\nBody with `ticks`.\n\n- Do: run `wiki x`.\n' > "$UW/NEWS.md"
up_prep() { set_version "$UW/wikis/demo/AGENTS.md" 1; git -C "$UW/wikis" commit -qam old; rm -rf "$UW/state"; }
upd() { sty WIKIS_DIR="$UW/wikis" XDG_STATE_HOME="$UW/state" LLM_WIKI_NEWS_FILE="$UW/NEWS.md" LLM_WIKI_NO_GO=1 "$@" "$W" update --wikis-only </dev/null 2>&1; }
up_prep; uplain="$(upd LLM_WIKI_STYLE=off)"
up_prep; upstyled="$(upd LLM_WIKI_STYLE=on $UTF)"
upmarks() { strip | sed -E 's/^(✓|\+|!) /- /'; }
case "$upstyled" in *"${ESC}[1m== Collection "*"${ESC}[1m== What changed${ESC}[0m"*"${ESC}[1m== What's new in llm-wiki${ESC}[0m"*"${ESC}[1m== Next${ESC}[0m"*) ok "update: the headings are bold, with their ==" ;; *) bad "update: the headings are bold, with their ==" "$upstyled" ;; esac
case "$upstyled" in *"${ESC}[32m✓${ESC}[0m pushed "*" commit(s)"*) ok "update: a step that succeeded has the tick in place of the dash" ;; *) bad "update: a step that succeeded has the tick in place of the dash" "$upstyled" ;; esac
case "$upstyled" in *"${ESC}[1m${ESC}[33m!${ESC}[0m New settings to look at: ${ESC}[36m"*"setup --new${ESC}[0m"*) ok "update: what is left has the warning mark, its command cyan" ;; *) bad "update: what is left has the warning mark, its command cyan" "$upstyled" ;; esac
case "$upstyled" in *"${ESC}[1m${ESC}[33m!${ESC}[0m Sessions already open"*"paste this into each:"*) ok "update: the note about open sessions has the warning mark" ;; *) bad "update: the note about open sessions has the warning mark" "$upstyled" ;; esac
case "$upstyled" in *"${ESC}[1m## 2026-01-02: Second \`entry\`${ESC}[0m"*) ok "update: a NEWS title is bold" ;; *) bad "update: a NEWS title is bold" "$upstyled" ;; esac
printf '%s\n' "$upstyled" | grep -qxF 'Body with `ticks`.' && printf '%s\n' "$upstyled" | grep -qxF -- '- Do: run `wiki x`.' && ok "update: a NEWS entry's body is printed exactly as written" || bad "update: a NEWS entry's body is printed exactly as written" "$upstyled"
[ "$(printf '%s\n' "$upstyled" | upmarks)" = "$uplain" ] && ok "update: stripped, with the marks back to '- ', the words are the plain words" || bad "update: stripped, with the marks back to '- ', the words are the plain words" "$(diff <(printf '%s\n' "$upstyled" | upmarks) <(printf '%s\n' "$uplain"))"
case "$uplain" in *"${ESC}"*) bad "update: off has no codes" ;; *) ok "update: off has no codes" ;; esac
up_prep; case "$(upd -u LLM_WIKI_STYLE)" in *"${ESC}"*) bad "update: piped has no codes" ;; *) ok "update: piped has no codes" ;; esac
# A push that fails says what to run, and the command is cyan.
git -C "$UW/wikis" config remote.origin.pushurl "$UW/no-such-remote.git"
up_prep; uplain="$(upd LLM_WIKI_STYLE=off)"
up_prep; upstyled="$(upd LLM_WIKI_STYLE=on $UTF)"
case "$upstyled" in *"${ESC}[1m${ESC}[33m!${ESC}[0m the push failed. Run: ${ESC}[36mgit -C "*" push${ESC}[0m"*) ok "update: a failed push has the warning mark and its Run: command is cyan" ;; *) bad "update: a failed push has the warning mark and its Run: command is cyan" "$upstyled" ;; esac
[ "$(printf '%s\n' "$upstyled" | upmarks)" = "$uplain" ] && ok "update: the failed push's words are the plain words too" || bad "update: the failed push's words are the plain words too" "$(diff <(printf '%s\n' "$upstyled" | upmarks) <(printf '%s\n' "$uplain"))"
# update in a clone, with the plugin installed too: it pulls, refreshes the plugin's copy, and says to restart.
UU="$UW/src"; mkdir -p "$UU" "$UW/bin" "$HOME/.cursor"
(cd "$REPO" && tar cf - --exclude .git --exclude tests .) | (cd "$UU" && tar xf -)
git -C "$UU" init -q && git -C "$UU" add -A && git -C "$UU" commit -qm v1 && git clone -q "$UU" "$UW/clone"
mkdir -p "$HOME/.claude/plugins"
printf '{"version":2,"plugins":{"llm-wiki@mk":[{"scope":"user","installPath":"%s"}]}}\n' "$UW/clone" > "$HOME/.claude/plugins/installed_plugins.json"
printf '#!/bin/sh\nexit 0\n' > "$UW/bin/claude" && chmod +x "$UW/bin/claude"
cl() { rm -rf "$UW/state"; env XDG_STATE_HOME="$UW/state" LLM_WIKI_NEWS_FILE="$UW/NEWS.md" LLM_WIKI_NO_GO=1 PATH="$UW/bin:$PATH" "$@" "$UW/clone/wiki.sh" update </dev/null 2>&1; }
cplain="$(cl LLM_WIKI_STYLE=off)"; cstyled="$(cl LLM_WIKI_STYLE=on $UTF)"
case "$cstyled" in *"${ESC}[1m== Updating llm-wiki${ESC}[0m"*) ok "update in a clone: the first heading is bold" ;; *) bad "update in a clone: the first heading is bold" "$cstyled" ;; esac
case "$cstyled" in *"${ESC}[32m✓${ESC}[0m pulled "*"${ESC}[32m✓${ESC}[0m updated the installed plugin's copy (llm-wiki@mk) too"*) ok "update in a clone: the pull and the plugin's refresh have the tick" ;; *) bad "update in a clone: the pull and the plugin's refresh have the tick" "$cstyled" ;; esac
case "$cstyled" in *"${ESC}[1m${ESC}[33m!${ESC}[0m Quit and reopen the Claude app and Cursor"*) ok "update in a clone: the restart has the warning mark" ;; *) bad "update in a clone: the restart has the warning mark" "$cstyled" ;; esac
[ "$(printf '%s\n' "$cstyled" | upmarks)" = "$cplain" ] && ok "update in a clone: the words are the plain words" || bad "update in a clone: the words are the plain words" "$(diff <(printf '%s\n' "$cstyled" | upmarks) <(printf '%s\n' "$cplain"))"
printf '#!/bin/sh\nexit 1\n' > "$UW/bin/claude"
cstyled="$(cl LLM_WIKI_STYLE=on $UTF)"
case "$cstyled" in *"${ESC}[1m${ESC}[33m!${ESC}[0m couldn't update the installed plugin's copy (llm-wiki@mk): ${ESC}[36mclaude plugin update llm-wiki@mk${ESC}[0m"*) ok "update in a clone: a failed plugin refresh has the mark and its command in cyan" ;; *) bad "update in a clone: a failed plugin refresh has the mark and its command in cyan" "$cstyled" ;; esac
rm -rf "$HOME/.cursor" "$HOME/.claude/plugins/installed_plugins.json"
# One text, two scripts: the guide's block is the one wiki.sh runs.
doc="$(sed -n '/^# --- style helpers/,/^# --- end of style helpers/p' "$REPO/docs/conventions.md")"
[ -n "$blk" ] && [ "$blk" = "$doc" ] && ok "the helper block in wiki.sh is the block in docs/conventions.md, byte for byte" || bad "the helper block in wiki.sh is the block in docs/conventions.md, byte for byte"
# A step of setup piped a two-line message into head -n 1. When head left first, the second
# line's write failed and setup stopped midway: seen once in CI, on Linux.
lacks "setup doesn't pipe a message of several lines into head" "cmd_claude | head" cat "$W"
case "$(head -n 1 "$REPO/docs/conventions.md")" in "Conventions version "[0-9]*) ok "the guide's first line gives its version" ;; *) bad "the guide's first line gives its version" ;; esac
v="$(head -n 1 "$REPO/docs/conventions.md" | sed 's/^Conventions version \([0-9]*\).*/\1/')"
case "$blk" in "# --- style helpers: docs/conventions.md, version $v. "*) ok "and the helper block names the same version" ;; *) bad "and the helper block names the same version" "$v" ;; esac
# Version 2: what a usage error exits with, and warnings on standard error.
exits() { local want="$1"; shift; "$@" >/dev/null 2>&1; [ "$?" -eq "$want" ]; }
check "an unknown command exits 2: called wrongly, not tried and failed" exits 2 sty "$W" nosuchcommand
check "an unknown option exits 2" exits 2 sty "$W" status --bogus
check "a missing argument exits 2" exits 2 sty "$W" pages
check "an option a command doesn't know exits 2" exits 2 sty "$W" pages demo --json
check "a failure exits 1: a wiki that isn't there" exits 1 sty "$W" pages nosuchwiki
check "an extension's own usage error exits 2" exits 2 env WIKIS_DIR="$SW/wikis" LLM_WIKI="$W" "$REPO/extensions/wiki-confluence" delete
check "and its failure exits 1" exits 1 env WIKIS_DIR="$SW/wikis" LLM_WIKI="$W" "$REPO/extensions/wiki-confluence" publish nosuchwiki
expect "a usage error still says error:" "error: no command called nosuchcommand" sty "$W" nosuchcommand
# A warning on standard error follows standard error, whatever standard output is.
werr() { bash -c "$blk"$'\n'"STYLE=$1 STYLE_ERR=$2; style_set; say_warn_err \"careful: \$(typed_err 'wiki status')\"; say_warn \"plain: \$(typed 'wiki open')\"" 2>"$SW/err" >"$SW/out"; }
werr no yes
case "$(cat "$SW/err")" in "${ESC}[1m${ESC}[33m!${ESC}[0m careful: ${ESC}[36mwiki status${ESC}[0m") ok "say_warn_err and typed_err are styled when standard error is" ;; *) bad "say_warn_err and typed_err are styled when standard error is" "$(cat -v "$SW/err")" ;; esac
case "$(cat "$SW/out")" in *"$ESC"*) bad "while standard output, which isn't, stays plain" "$(cat -v "$SW/out")" ;; *) ok "while standard output, which isn't, stays plain" ;; esac
werr yes no
[ "$(cat "$SW/err")" = "careful: wiki status" ] && ok "sent to a file, a warning on standard error has no codes, though the terminal's output has" || bad "sent to a file, a warning on standard error has no codes" "$(cat -v "$SW/err")"
case "$(cat "$SW/out")" in *"${ESC}[36mwiki open${ESC}[0m"*) ok "and standard output keeps its own" ;; *) bad "and standard output keeps its own" "$(cat -v "$SW/out")" ;; esac
out="$(bash -c "$blk"$'\n''style_off; say_warn_err x' 2>&1)"
[ "$out" = x ] && ok "style_off covers it" || bad "style_off covers it" "$out"
out="$(LLM_WIKI_STYLE=on bash -c "$blk"$'\n''die_usage wrong' 2>&1; echo "code $?")"
case "$out" in "${ESC}[31merror:${ESC}[0m wrong"*"code 2") ok "die_usage says error: in red and exits 2" ;; *) bad "die_usage says error: in red and exits 2" "$(printf '%s' "$out" | cat -v)" ;; esac
check "the guide says what a usage error exits with" grep -q '2 called wrongly' "$REPO/docs/conventions.md"
check "that --yes isn't owed where the question is the safeguard" grep -q 'a tool may have no `--yes` where the question is the safeguard' "$REPO/docs/conventions.md"
check "and gives the same pair in Python" grep -q 'def warn_err' "$REPO/docs/conventions.md"
grep -q 'docs/conventions.md' "$REPO/AGENTS.md" && ok "AGENTS.md points at the guide" || bad "AGENTS.md points at the guide"
fi

if section "What moved to llm-relay"; then
expect "wiki relay says where it went" "https://github.com/broxgit/llm-relay" "$W" relay
expect "and what to run instead" "Then use: relay scan --branch main" "$W" relay scan --branch main
refuse "and fails" "$W" relay run t/d
refuse "even for help" "$W" relay --help
expect "setup copilot-cowork says where it went" "relay setup, from https://github.com/broxgit/llm-relay" "$W" setup copilot-cowork
refuse "and fails" "$W" setup copilot-cowork --dir "$T"
check "and copies nothing" test ! -e "$T/Documents/Cowork"
lacks "completion doesn't offer relay" "relay" "$W" __complete 1 ""
lacks "or the setup section" "copilot-cowork" "$W" __complete 2 setup ""
lacks "the usage doesn't list it" "relay run" "$W" --help
lacks "and setup --help doesn't" "copilot-cowork" "$W" setup --help
lacks "and setup --list doesn't" "copilot-cowork" "$W" setup --list
check "the relay's files are gone" test ! -e "$REPO/scripts/relay.sh" -a ! -e "$REPO/cowork"
fi

if section "Extensions"; then
# An extension is an executable named wiki-<name> in a folder on this machine.
XD="$HOME/.local/share/llm-wiki/extensions"
lacks "with none of your own, extensions lists only what ships" "(no description)" "$W" extensions
check "and the message for an empty machine is still there" grep -q 'No extensions on this machine' "$W"
expect "and names the folder they go in" "wiki-<name>" "$W" extensions
check "extensions path prints the folder" test "$("$W" extensions path)" = "$XD"
refuse "extensions takes nothing else" "$W" extensions install
mkdir -p "$XD"
cat > "$XD/wiki-hello" <<'EXT'
#!/bin/sh
# wiki-extension: Says hello, for the smoke test.
printf 'args:'; for a in "$@"; do printf ' [%s]' "$a"; done; printf '\n'
printf 'api=%s dir=%s\n' "$LLM_WIKI_EXTENSION" "$WIKIS_DIR"
printf 'nested: '; "$LLM_WIKI" extensions path
[ "${1:-}" != fail ] || exit 7
EXT
chmod +x "$XD/wiki-hello"
out="$("$W" hello one "two words" --all -x 2>&1)"
case "$out" in *"args: [one] [two words] [--all] [-x]"*) ok "wiki <name> runs the extension with its arguments as given" ;; *) bad "wiki <name> runs the extension with its arguments as given" "$out" ;; esac
case "$out" in *"api=3 dir=$WIKIS_DIR"*) ok "and tells it the contract's version and the collection" ;; *) bad "and tells it the contract's version and the collection" "$out" ;; esac
case "$out" in *"nested: $XD"*) ok "and how to run the wiki command" ;; *) bad "and how to run the wiki command" "$out" ;; esac
"$W" hello fail >/dev/null 2>&1
code=$?
[ "$code" -eq 7 ] && ok "the extension's exit code is the command's" || bad "the extension's exit code is the command's" "exit $code"
expect "extensions lists it with its description" "Says hello, for the smoke test." "$W" extensions
expect "the first word completes to it" "hello" "$W" __complete 1 he
expect "and to extensions" "extensions" "$W" __complete 1 ex
expect "extensions completes to path" "path" "$W" __complete 2 extensions ""
expect "the usage names the command" "extensions [path | add <name> | remove <name> | setup <name> | log <name> | tick | every ...]" "$W" --help
# A command of llm-wiki's own always wins.
printf '#!/bin/sh\necho HIJACK\n' > "$XD/wiki-news"
printf '#!/bin/sh\necho HIJACK\n' > "$XD/wiki-relay"
chmod +x "$XD/wiki-news" "$XD/wiki-relay"
lacks "an extension can't take a built-in command's name" "HIJACK" "$W" news
lacks "or a hidden one's" "HIJACK" "$W" relay
expect "and extensions says it is ignored" "ignored: news is a command of llm-wiki's own" "$W" extensions
rm "$XD/wiki-news" "$XD/wiki-relay"
printf '#!/bin/sh\necho ran\n' > "$XD/wiki-asleep"
refuse "a file that isn't executable doesn't run" "$W" asleep
expect "and the error says how to fix it" "chmod +x" "$W" asleep
expect "and so does the list" "not executable" "$W" extensions
lacks "completion leaves it out" "asleep" "$W" __complete 1 ""
rm "$XD/wiki-asleep"
printf '#!/bin/sh\necho ran\n' > "$XD/wiki-Bad_Name"
chmod +x "$XD/wiki-Bad_Name"
refuse "a name that isn't lowercase letters, digits and dashes doesn't run" "$W" Bad_Name
expect "and is listed as ignored" "ignored: a name is lowercase letters, digits and dashes" "$W" extensions
expect "with the file to rename" "Rename " "$W" extensions
expect "and running it says why it can't be a command" "Bad_Name can't be a command: an extension's name is lowercase letters, digits and dashes. Rename " "$W" Bad_Name
rm "$XD/wiki-Bad_Name"
refuse "an unknown command still fails" "$W" nosuchcommand
out="$("$W" nosuchcommand 2>&1)"
[ "$out" = "error: no command called nosuchcommand. $W --help lists the commands, and $W extensions lists yours." ] && ok "in one line that names the word, not a page of usage" || bad "in one line that names the word, not a page of usage" "$out"
mkdir -p "$T/ext2"
printf '#!/bin/sh\necho elsewhere\n' > "$T/ext2/wiki-there"
chmod +x "$T/ext2/wiki-there"
expect "LLM_WIKI_EXTENSIONS_DIR names another folder" "elsewhere" env LLM_WIKI_EXTENSIONS_DIR="$T/ext2" "$W" there
check "the docs say what an extension is given" grep -q 'LLM_WIKI_EXTENSION' "$REPO/docs/extensions.md"
# An extension that needs setting up says so, and is never on, unready and silent.
cat > "$XD/wiki-prep" <<'EXT'
#!/bin/sh
# wiki-extension: Needs setting up, for the smoke test.
# wiki-events: tick
# wiki-setup: yes
case "${1:-}" in
  --wiki-ready) [ -f "$HOME/prep-ready" ] && exit 0; echo "no prep file yet"; exit 1 ;;
  --wiki-setup) printf 'Make it? '; read -r a; [ "$a" != make ] || : > "$HOME/prep-ready"; exit 0 ;;
  --wiki-event) echo ticked >> "$HOME/prep-ticks"; exit 0 ;;
esac
echo ran
EXT
chmod +x "$XD/wiki-prep"
expect "status lists an extension that says it isn't set up, with the command that sets it up" "extension prep: on, but not ready: no prep file yet. Run: " "$W" status
expect "and that command is extensions setup" "extensions setup prep" "$W" status
expect "the list of extensions says it too" "not ready: no prep file yet" "$W" extensions
expect "an event doesn't run it while it isn't set up" "prep: not set up" env LLM_WIKI_EVENTS=wait "$W" extensions tick
check "at all" test ! -e "$HOME/prep-ticks"
out="$(printf 'no\n' | "$W" extensions setup prep 2>&1)"
case "$out" in *"Make it?"*"prep isn't set up yet: no prep file yet. Run: "*) ok "extensions setup asks its questions, and says when it still isn't set up" ;; *) bad "extensions setup asks its questions, and says when it still isn't set up" "$out" ;; esac
expect "and when it is" "prep is set up." bash -c "printf 'make\n' | '$W' extensions setup prep"
lacks "status then says nothing about it" "extension prep" "$W" status
expect "and events run it" "prep: ok" env LLM_WIKI_EVENTS=wait "$W" extensions tick
rm "$HOME/prep-ready"
expect "an extension that stops being ready is caught by the next event" "prep: not set up" env LLM_WIKI_EVENTS=wait "$W" extensions tick
expect "and status says so again" "extension prep: on, but not ready" "$W" status
expect "one with nothing to set up says that" "hello has nothing to set up." "$W" extensions setup hello
refuse "extensions setup needs an extension that is on" "$W" extensions setup nosuch
printf '#!/bin/sh\n# wiki-extension: Slow to say.\n# wiki-setup: yes\n[ "$1" != --wiki-ready ] || sleep 30\n' > "$XD/wiki-slow"
chmod +x "$XD/wiki-slow"
expect "one that doesn't answer in time counts as not ready, and status doesn't wait for it" "extension slow: on, but not ready: it didn't say whether it is set up." env LLM_WIKI_READY_SECONDS=1 "$W" status
rm "$XD/wiki-slow" "$XD/wiki-prep"
# An extension written in something this machine doesn't have.
printf '#!/usr/bin/env nosuchlang\n# wiki-extension: In a language this machine lacks.\nprint("hi")\n' > "$XD/wiki-alien"
chmod +x "$XD/wiki-alien"
expect "running one whose language is missing says what it needs" "alien needs nosuchlang, which isn't on this machine. Do: install nosuchlang" "$W" alien
refuse "and fails" "$W" alien
expect "status says so too" "extension alien: on, but not ready: it needs nosuchlang" "$W" status
rm "$XD/wiki-alien"
expect "completion offers setup" "setup" "$W" __complete 2 extensions ""
check "the docs give the contract's third version" grep -q 'wiki-setup' "$REPO/docs/extensions.md"
rm -rf "$XD"
fi

if section "Jira extension"; then
# An extension that ships with llm-wiki is off until turned on, on each machine.
expect "a shipped extension is listed as off" "jira           off." "$W" extensions
expect "with how to turn it on" "extensions add jira" "$W" extensions
refuse "and doesn't run while it is off" "$W" jira --help
expect "the error says how to turn it on" "extensions add jira" "$W" jira check
lacks "completion leaves it out while it is off" "jira" "$W" __complete 1 ""
expect "setup --list marks it as new" "on: none  <- new" bash -c "'$W' setup --list | grep '^extensions'"
expect "setup --new would ask about it" "Turn on" bash -c "printf 'n\nn\n' | LLM_WIKI_TEST_TTY=1 '$W' setup extensions"
lacks "a no is remembered" "<- new" bash -c "'$W' setup --list | grep '^extensions'"
refuse "it is still off" "$W" jira --help
refuse "extensions add refuses a name that doesn't ship" "$W" extensions add nosuch
refuse "and needs a name" "$W" extensions add
expect "extensions add turns it on" "on: jira" "$W" extensions add jira
"$W" extensions remove jira >/dev/null
expect "and says at once that it isn't set up, with the command that does it" "jira isn't set up yet: no Atlassian site yet. Run: " "$W" extensions add jira
expect "status lists an extension that is on and not set up" "extension jira: on, but not ready: no Atlassian site yet. Run: " "$W" status
expect "and so does the list of extensions" "not ready: no Atlassian site yet" "$W" extensions
check "the extension says itself what it lacks, in one line" test "$(env WIKIS_DIR="$WIKIS_DIR" "$REPO/extensions/wiki-jira" --wiki-ready)" = "no Atlassian site yet"
refuse "and fails while it lacks it" "$REPO/extensions/wiki-jira" --wiki-ready
expect "and it runs" "Usage: " "$W" jira --help
expect "setup --list names it" "on: jira" bash -c "'$W' setup --list | grep '^extensions'"
expect "completion offers it" "jira" "$W" __complete 1 ji
expect "extensions add completes to shipped names" "jira" "$W" __complete 3 extensions add ""
lacks "the list no longer says off" "jira           off." "$W" extensions
expect "setup extensions keeps a yes" "on." bash -c "printf 'n\ny\n' | LLM_WIKI_TEST_TTY=1 '$W' setup extensions"
refuse "and a no for another leaves that one off" "$W" confluence --help
mkdir -p "$HOME/.local/share/llm-wiki/extensions"
printf '#!/bin/sh\necho MINE\n' > "$HOME/.local/share/llm-wiki/extensions/wiki-jira"
chmod +x "$HOME/.local/share/llm-wiki/extensions/wiki-jira"
expect "a file of your own wins over a shipped one" "MINE" "$W" jira
rm -rf "$HOME/.local/share/llm-wiki/extensions"

# A stand-in for Jira: two tickets, one done, and a record of each sign-in.
J="$T/jira"
mkdir -p "$J"
cat > "$J/server.py" <<'PY'
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
D = sys.argv[1]
T = {"PROJ-1": {"summary": "Release propm", "status": {"name": "Done", "statusCategory": {"key": "done"}}, "resolutiondate": "2026-11-08T10:00:00.000+0000"},
     "PROJ-2": {"summary": "Second step", "status": {"name": "In Progress", "statusCategory": {"key": "indeterminate"}}, "resolutiondate": None}}
def tk(summary, status, cat, **more):
    return dict({"summary": summary, "status": {"name": status, "statusCategory": {"key": cat}}, "resolutiondate": None}, **more)
T.update({"PROJ-3": tk("Dropped", "Closed", "done", resolution={"name": "Won't Do"}, resolutiondate="2026-11-09T10:00:00.000+0000"),
          "PROJ-4": tk("Stuck", "Blocked", "indeterminate"),
          "PROJ-5": tk("Flagged", "In Progress", "indeterminate", customfield_10021=[{"value": "Impediment"}]),
          "PROJ-6": tk("Nearly out", "Ready for Release", "done"),
          "PROJ-7": tk("Back again", "In Progress", "indeterminate")})
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        auth = self.headers.get("Authorization", "")
        open(D + "/auth.log", "a").write(auth + "\n")
        body, code = {}, 404
        if "bad" in auth: code = 401
        elif self.path == "/rest/api/2/myself": body, code = {"displayName": "Smoke Tester"}, 200
        elif self.path == "/rest/api/2/field": body, code = [{"id": "customfield_10000", "name": "Sprint"}, {"id": "customfield_10021", "name": "Flagged"}], 200
        elif self.path.startswith("/rest/api/2/issue/"):
            k = self.path.split("/")[-1].split("?")[0]
            if k in T: body, code = {"key": k, "fields": T[k]}, 200
        self.send_response(code); self.send_header("Content-Type", "application/json"); self.end_headers()
        self.wfile.write(json.dumps(body).encode())
import socketserver
class S(HTTPServer):
    # HTTPServer's own bind looks the host's name up, which can take seconds on a Mac.
    def server_bind(self):
        socketserver.TCPServer.server_bind(self)
        self.server_name, self.server_port = "localhost", self.server_address[1]
s = S(("127.0.0.1", 0), H)
open(D + "/port", "w").write(str(s.server_address[1]))
s.serve_forever()
PY
python3 "$J/server.py" "$J" &
JPID=$!
i=0; while [ ! -s "$J/port" ] && [ "$i" -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
check "the stand-in Jira server started" test -s "$J/port"
JW="$T/jwikis"
WIKIS_DIR="$JW" "$W" new jdemo >/dev/null 2>&1
cat > "$JW/jdemo/open.md" <<'OPEN'
# Open

## Release PROJ-1 to production
- kind: waiting
- who: Katherine
- status: open
- from: 2026-11-09 raw/a.md

## Ship PROJ-2 after PROJ-1
- kind: waiting
- who: Katherine
- status: open
- from: 2026-11-09 raw/a.md

## Old PROJ-1 cleanup
- kind: waiting
- who: user
- status: done 2026-11-01
- from: 2026-10-30 raw/b.md

## Read the UTF-8 report
- kind: due
- due: 2026-12-01
- status: open
- from: 2026-11-09 raw/a.md
OPEN
jira() { WIKIS_DIR="$JW" JIRA_URL="http://127.0.0.1:$(cat "$J/port")" JIRA_EMAIL=me@example.com JIRA_API_TOKEN=smoke-token "$W" jira "$@"; }
expect "with no sign-in, jira says so and what to run" "Jira isn't set up: no Atlassian site yet. Run: " env WIKIS_DIR="$JW" "$W" jira
refuse "and fails, where it used to say there was nothing to do" env WIKIS_DIR="$JW" "$W" jira
expect "show says the same" "extensions setup jira" env WIKIS_DIR="$JW" "$W" jira show PROJ-1
expect "with no token, it says that" "no API token" env WIKIS_DIR="$JW" JIRA_URL=http://127.0.0.1:1 "$W" jira
out="$(jira check 2>&1)"
case "$out" in *"== jdemo"*"Release PROJ-1 to production"*"PROJ-1       Done, resolved 2026-11-08"*) ok "jira says a ticket an open item names is done" ;; *) bad "jira says a ticket an open item names is done" "$out" ;; esac
case "$out" in *"PROJ-2       In Progress"*) ok "and where one that isn't done stands" ;; *) bad "and where one that isn't done stands" "$out" ;; esac
case "$out" in *"1 open item(s) have every ticket done"*"jira check --close"*) ok "an item counts as done only when all its tickets are" ;; *) bad "an item counts as done only when all its tickets are" "$out" ;; esac
case "$out" in *"Old PROJ-1"* | *"UTF-8"*) bad "closed items and words that only look like keys are left out" "$out" ;; *) ok "closed items and words that only look like keys are left out" ;; esac
check "nothing was written by a plain check" test -z "$(find "$JW/jdemo/raw" -name '*jira-done*' 2>/dev/null)"
check "with an email, the sign-in is Jira Cloud's" grep -qxF "Basic $(printf 'me@example.com:smoke-token' | base64)" "$J/auth.log"
: > "$J/auth.log"
WIKIS_DIR="$JW" JIRA_URL="http://127.0.0.1:$(cat "$J/port")" JIRA_API_TOKEN=smoke-token "$W" jira >/dev/null 2>&1
check "without one, the token is a Data Center access token" grep -qxF "Bearer smoke-token" "$J/auth.log"
printf 'url = http://127.0.0.1:%s\nemail = me@example.com  # cloud\ntoken_cmd = echo file-token\n' "$(cat "$J/port")" > "$HOME/.config/llm-wiki/jira"
: > "$J/auth.log"
expect "settings come from the file too, the token from a command" "Signed in as Smoke Tester" env WIKIS_DIR="$JW" "$W" jira config
check "and that token was the one sent" grep -qxF "Basic $(printf 'me@example.com:file-token' | base64)" "$J/auth.log"
lacks "config never prints the token" "file-token" env WIKIS_DIR="$JW" "$W" jira config
rm "$HOME/.config/llm-wiki/jira"
# One sign-in for every Atlassian extension, in a file they share.
printf 'site = http://127.0.0.1:%s\nemail = shared@example.com\ntoken_cmd = echo shared-token\n' "$(cat "$J/port")" > "$HOME/.config/llm-wiki/atlassian"
: > "$J/auth.log"
out="$(env WIKIS_DIR="$JW" "$W" jira config 2>&1)"
case "$out" in *"Signed in as Smoke Tester"*) ok "jira signs in from the shared Atlassian file alone" ;; *) bad "jira signs in from the shared Atlassian file alone" "$out" ;; esac
check "with its email and token" grep -qxF "Basic $(printf 'shared@example.com:shared-token' | base64)" "$J/auth.log"
case "$out" in *"url       http://127.0.0.1:"*"(from the shared file)"*"email     shared@example.com  (from the shared file)"*"token     from token_cmd in the shared file"*) ok "and config says where each came from" ;; *) bad "and config says where each came from" "$out" ;; esac
case "$out" in *shared-token*) bad "still without printing the token" "$out" ;; *) ok "still without printing the token" ;; esac
printf 'email = own@example.com\ntoken_cmd = echo own-token\n' > "$HOME/.config/llm-wiki/jira"
: > "$J/auth.log"
env WIKIS_DIR="$JW" "$W" jira config >/dev/null 2>&1
check "jira's own settings win over the shared file, one value at a time" grep -qxF "Basic $(printf 'own@example.com:own-token' | base64)" "$J/auth.log"
: > "$J/auth.log"
env ATLASSIAN_API_TOKEN=env-shared WIKIS_DIR="$JW" "$W" jira config >/dev/null 2>&1
check "ATLASSIAN_API_TOKEN wins over both files" grep -qxF "Basic $(printf 'own@example.com:env-shared' | base64)" "$J/auth.log"
: > "$J/auth.log"
env ATLASSIAN_API_TOKEN=env-shared JIRA_API_TOKEN=env-own WIKIS_DIR="$JW" "$W" jira config >/dev/null 2>&1
check "and JIRA_API_TOKEN over that" grep -qxF "Basic $(printf 'own@example.com:env-own' | base64)" "$J/auth.log"
rm "$HOME/.config/llm-wiki/jira" "$HOME/.config/llm-wiki/atlassian"
expect "with neither file, jira names the one command that sets it up" "extensions setup jira" env WIKIS_DIR="$JW" "$W" jira
expect "a sign-in Jira refuses is said plainly" "refused the sign-in" env WIKIS_DIR="$JW" JIRA_URL="http://127.0.0.1:$(cat "$J/port")" JIRA_API_TOKEN=bad "$W" jira
refuse "and fails" env WIKIS_DIR="$JW" JIRA_URL="http://127.0.0.1:$(cat "$J/port")" JIRA_API_TOKEN=bad "$W" jira
expect "projects limits which keys count, and says which it left out" "No open item names a ticket in OPS. 3 other key(s) are left out by projects" env JIRA_PROJECTS=OPS WIKIS_DIR="$JW" JIRA_URL="http://127.0.0.1:$(cat "$J/port")" JIRA_API_TOKEN=smoke-token "$W" jira
expect "show gives a ticket's status and summary" "In Progress  Second step" jira show proj-2
refuse "show fails for a ticket Jira doesn't know" jira show NOPE-9
refuse "jira refuses an option it doesn't know" jira check --force
refuse "and a wiki that isn't there" jira check nosuchwiki
expect "saying it is neither a wiki nor a command" "nosuchwiki isn't a wiki here, and isn't something jira does" jira check nosuchwiki
# An address that answers, but isn't Jira: every ticket comes back unknown.
out="$(env WIKIS_DIR="$JW" JIRA_URL="http://127.0.0.1:$(cat "$J/port")/nonsense" JIRA_API_TOKEN=smoke-token "$W" jira 2>&1)"
code=$?
case "$out" in *"doesn't answer as Jira: none of "*" ticket(s) could be looked up"*"extensions setup jira"*) ok "an address that isn't Jira is said to be so, where it used to say nothing was open" ;; *) bad "an address that isn't Jira is said to be so" "$out" ;; esac
[ "$code" -ne 0 ] && ok "and jira fails, so a run by itself is a failure too" || bad "and jira fails, so a run by itself is a failure too" "exit $code"
expect "check --close notes the item as done" "jdemo: noted 1 item(s) as done" jira check --close
note="$(ls "$JW/jdemo/raw"/*-jira-done.md 2>/dev/null | head -n 1)"
check "the note has the Done line the compile matches" grep -qxF "Done: Release PROJ-1 to production" "$note"
check "and names its source" grep -q "PROJ-1 \"Release propm\": Done, resolved 2026-11-08. http://127.0.0.1:" "$note"
lacks "and no Done line for the item still waiting" "Done: Ship" cat "$note"
expect "a second --close doesn't note it again" "already noted, waiting for a compile" jira check --close
check "so there is one note" test "$(find "$JW/jdemo/raw" -name '*jira-done*' | wc -l | tr -d ' ')" = 1
# What a ticket's state means. Only a change that alters what someone should do is noted.
JS="$T/jstates"
WIKIS_DIR="$JS" "$W" new sdemo >/dev/null 2>&1
TODAY="$(date -u +%Y-%m-%d)"
cat > "$JS/sdemo/open.md" <<OPEN
# Open

## Use PROJ-3 once it lands
- kind: waiting
- who: Katherine
- status: open
- from: 2026-11-10 raw/a.md

## Wait for PROJ-4
- kind: waiting
- who: Katherine
- status: open
- from: 2026-11-10 raw/a.md

## Wait for flagged PROJ-5
- kind: waiting
- who: user
- status: open
- from: 2026-11-10 raw/a.md

## Jira: PROJ-5 is blocked, holding up "Wait for flagged PROJ-5"
- kind: waiting
- who: user
- status: open
- from: 2026-11-10 raw/2026-11-10-000000-jira-done.md

## Cut over at PROJ-6
- kind: waiting
- who: user
- status: open
- from: 2026-11-10 raw/a.md

## Jira: PROJ-2 is blocked, holding up "Old thing"
- kind: waiting
- who: user
- status: open
- from: 2026-11-10 raw/2026-11-10-000000-jira-done.md

## Shipped PROJ-7
- kind: waiting
- who: Katherine
- status: done $TODAY
- from: 2026-11-10 raw/2026-11-10-000000-jira-done.md

## Hand-closed PROJ-2
- kind: waiting
- who: user
- status: done $TODAY
- from: 2026-11-10 raw/b.md
OPEN
jst() { WIKIS_DIR="$JS" JIRA_URL="http://127.0.0.1:$(cat "$J/port")" JIRA_EMAIL=me@example.com JIRA_API_TOKEN=smoke-token "$W" jira "$@"; }
out="$(jst check 2>&1)"
case "$out" in *"PROJ-3       Closed as Won't Do, without the work done"*) ok "a ticket closed without the work is said to be so" ;; *) bad "a ticket closed without the work is said to be so" "$out" ;; esac
case "$out" in *"PROJ-4       Blocked"*"PROJ-5       In Progress, flagged"*) ok "a blocked status and a flagged ticket both read as blocked" ;; *) bad "a blocked status and a flagged ticket both read as blocked" "$out" ;; esac
case "$out" in *"1 open item(s) have every ticket done."*"4 other change(s) to note: 1 closed without the work, 1 blocked, 1 no longer so, 1 reopened."*) ok "check counts what would be noted, by kind" ;; *) bad "check counts what would be noted, by kind" "$out" ;; esac
case "$out" in *"  Jira: PROJ"*) bad "items the extension opened itself aren't listed" "$out" ;; *) ok "items the extension opened itself aren't listed" ;; esac
lacks "done_statuses decides what done means" "have every ticket done" env JIRA_DONE_STATUSES="Released, Deployed" WIKIS_DIR="$JS" JIRA_URL="http://127.0.0.1:$(cat "$J/port")" JIRA_API_TOKEN=smoke-token "$W" jira check
expect "and config shows it" "done      released, deployed" env JIRA_DONE_STATUSES="Released, Deployed" WIKIS_DIR="$JS" JIRA_URL="http://127.0.0.1:$(cat "$J/port")" JIRA_API_TOKEN=smoke-token "$W" jira config
expect "check --close notes each kind of change" "sdemo: noted 5 change(s): 1 done, 1 closed without the work, 1 blocked, 1 no longer so, 1 reopened." jst check --close
note="$(ls "$JS/sdemo/raw"/*-jira-done.md 2>/dev/null | tail -n 1)"
check "a ticket closed without the work leaves its item open and asks the user" grep -qxF "Waiting: user | Jira: PROJ-3 was closed as Won't Do, and \"Use PROJ-3 once it lands\" still waits on it" "$note"
lacks "and doesn't close the item" "Done: Use PROJ-3" cat "$note"
check "a blocked ticket opens an item for whoever was waiting" grep -qxF "Waiting: Katherine | Jira: PROJ-4 is blocked, holding up \"Wait for PROJ-4\"" "$note"
lacks "once: a blocked ticket that already has its item gets no second" "PROJ-5 is blocked" cat "$note"
check "an item about a block closes when the ticket is no longer blocked" grep -qxF "Done: Jira: PROJ-2 is blocked, holding up \"Old thing\"" "$note"
check "a ticket reopened after its item closed opens the item again" grep -qxF "Waiting: Katherine | Shipped PROJ-7" "$note"
lacks "but not an item someone else closed" "Hand-closed" cat "$note"
lacks "and an item about a block isn't itself reported as blocked" "holding up \"Jira:" cat "$note"
check "an item whose tickets are done still closes" grep -qxF "Done: Cut over at PROJ-6" "$note"
check "the note says where each ticket stood" grep -q "PROJ-3 \"Dropped\": Closed as Won't Do, without the work done." "$note"
expect "a second --close notes nothing again" "already noted, waiting for a compile" jst check --close
# Its guided setup: the shared sign-in, a test of it, then Jira's own settings.
JH="$T/jhome"
mkdir -p "$JH"
jsetup() { env HOME="$JH" WIKIS_DIR="$JW" ATLASSIAN_API_TOKEN=smoke-token "$W" extensions setup jira; }
HOME="$JH" "$W" extensions add jira >/dev/null 2>&1
out="$(printf 'http://127.0.0.1:%s\nme@example.com\nPROJ, OPS\ny\n' "$(cat "$J/port")" | jsetup 2>&1)"
case "$out" in *"share one Atlassian sign-in"*"Site, such as"*"Email of your Atlassian account"*) ok "setup asks for the site and the email" ;; *) bad "setup asks for the site and the email" "$out" ;; esac
case "$out" in *"Signed in to Jira as Smoke Tester."*) ok "then tests the sign-in and says who it signed in as" ;; *) bad "then tests the sign-in and says who it signed in as" "$out" ;; esac
case "$out" in *"Close open items by themselves?"*"jira is set up."*) ok "asks about closing items by itself, and ends by saying it is set up" ;; *) bad "asks about closing items by itself, and ends by saying it is set up" "$out" ;; esac
check "the sign-in went to the shared file" grep -qx "site = http://127.0.0.1:$(cat "$J/port")" "$JH/.config/llm-wiki/atlassian"
check "with the email" grep -qx "email = me@example.com" "$JH/.config/llm-wiki/atlassian"
check "and Jira's own answers to Jira's file" grep -qx "projects = PROJ, OPS" "$JH/.config/llm-wiki/jira"
check "the yes included" grep -qx "auto_close = yes" "$JH/.config/llm-wiki/jira"
lacks "status then has nothing to say about it" "extension jira" env HOME="$JH" WIKIS_DIR="$JW" ATLASSIAN_API_TOKEN=smoke-token "$W" status
out="$(printf '\n\n\n\n\n' | jsetup 2>&1)"
case "$out" in *"The Atlassian sign-in is already set"*"Change it?"*) ok "a second run says the sign-in is set, and asks before changing it" ;; *) bad "a second run says the sign-in is set, and asks before changing it" "$out" ;; esac
check "and Enter keeps every answer" grep -qx "projects = PROJ, OPS" "$JH/.config/llm-wiki/jira"
printf 'y\n\n\n-\nn\n' | jsetup >/dev/null 2>&1
lacks "a dash clears a value, and a no turns the setting off" "projects\|auto_close" cat "$JH/.config/llm-wiki/jira"
out="$(printf 'y\nnot-an-address\n\n' | jsetup 2>&1)"
case "$out" in *"not-an-address isn't an address, so it wasn't saved"*) ok "an answer that isn't an address is refused, and the old one kept" ;; *) bad "an answer that isn't an address is refused, and the old one kept" "$out" ;; esac
check "which it was" grep -q "^site = http://127.0.0.1:" "$JH/.config/llm-wiki/atlassian"
out="$(printf 'http://127.0.0.1:%s\nme@example.com\n' "$(cat "$J/port")" | env HOME="$T/jhome2" WIKIS_DIR="$JW" "$W" extensions setup jira 2>&1 || true)"
case "$out" in *"jira is off. Turn it on: "*"extensions add jira"*) ok "setup of an extension that is off says how to turn it on" ;; *) bad "setup of an extension that is off says how to turn it on" "$out" ;; esac
mkdir -p "$T/jhome2"
HOME="$T/jhome2" "$W" extensions add jira >/dev/null 2>&1
out="$(printf 'http://127.0.0.1:%s\nme@example.com\n' "$(cat "$J/port")" | env HOME="$T/jhome2" WIKIS_DIR="$JW" "$W" extensions setup jira 2>&1)"
case "$out" in *"id.atlassian.com/manage-profile/security/api-tokens"*) ok "with no token anywhere, setup says where to make one" ;; *) bad "with no token anywhere, setup says where to make one" "$out" ;; esac
case "$out" in *smoke-token*) bad "and never asks for the token itself" "$out" ;; *) ok "and never asks for the token itself" ;; esac
mkdir -p "$T/jhome3"
HOME="$T/jhome3" "$W" extensions add jira >/dev/null 2>&1
out="$(printf 'http://127.0.0.1:%s\n\n\n\n' "$(cat "$J/port")" | env HOME="$T/jhome3" WIKIS_DIR="$JW" ATLASSIAN_API_TOKEN=bad "$W" extensions setup jira 2>&1)"
case "$out" in *"refused the sign-in"*"The sign-in didn't work."*) ok "a sign-in Jira refuses is said during setup, and setup carries on" ;; *) bad "a sign-in Jira refuses is said during setup, and setup carries on" "$out" ;; esac
case "$out" in *"Close open items by themselves?"*) ok "to Jira's own questions" ;; *) bad "to Jira's own questions" "$out" ;; esac
# With no answer about the token, nothing is written that would look like one is set.
mkdir -p "$T/jhome5"
HOME="$T/jhome5" "$W" extensions add jira >/dev/null 2>&1
printf 'http://127.0.0.1:%s\nme@example.com\n' "$(cat "$J/port")" | env HOME="$T/jhome5" WIKIS_DIR="$JW" "$W" extensions setup jira >/dev/null 2>&1
lacks "setup cut short before the token leaves no token command behind" "token_cmd" cat "$T/jhome5/.config/llm-wiki/atlassian"
expect "so the extension still says it has no token" "no API token yet" env HOME="$T/jhome5" WIKIS_DIR="$JW" "$W" status
# Through wiki setup: a yes goes straight on to the extension's own questions.
mkdir -p "$T/jhome4"
out="$(printf 'n\ny\nhttp://127.0.0.1:%s\nme@example.com\n\nn\n\n6h\n' "$(cat "$J/port")" | env HOME="$T/jhome4" WIKIS_DIR="$JW" ATLASSIAN_API_TOKEN=smoke-token LLM_WIKI_TEST_TTY=1 "$W" setup extensions 2>&1)"
case "$out" in *"Turn on"*"jira?"*"share one Atlassian sign-in"*"Signed in to Jira as Smoke Tester."*"jira is set up."*"To go through this again:"*"extensions setup jira"*"tick: every 6h"*) ok "wiki setup turns it on, asks its questions, and carries on with its own" ;; *) bad "wiki setup turns it on, asks its questions, and carries on with its own" "$out" ;; esac
# With auto_close, the tick event does the same with nobody asking.
expect "jira asks for the tick event" "(runs on: tick)" "$W" extensions
jtick() { WIKIS_DIR="$JW" JIRA_URL="http://127.0.0.1:$(cat "$J/port")" JIRA_EMAIL=me@example.com JIRA_API_TOKEN=smoke-token LLM_WIKI_EVENTS=wait "$W" extensions tick; }
printf '\n## Announce PROJ-1\n- kind: waiting\n- who: user\n- status: open\n- from: 2026-11-10 raw/c.md\n' >> "$JW/jdemo/open.md"
expect "with auto_close off, the tick does nothing" "jira: ok" jtick
check "and says why in its log" grep -q "auto_close is off" "$HOME/.local/state/llm-wiki/extensions/jira/tick.log"
check "and saves no note" test "$(find "$JW/jdemo/raw" -name '*jira-done*' | wc -l | tr -d ' ')" = 1
expect "with auto_close on, the tick runs the check" "jira: ok" env JIRA_AUTO_CLOSE=yes WIKIS_DIR="$JW" JIRA_URL="http://127.0.0.1:$(cat "$J/port")" JIRA_EMAIL=me@example.com JIRA_API_TOKEN=smoke-token LLM_WIKI_EVENTS=wait "$W" extensions tick
check "and notes the finished item as done" grep -rqxF "Done: Announce PROJ-1" "$JW/jdemo/raw"
expect "config says auto is on" "check --close runs by itself" env JIRA_AUTO_CLOSE=yes WIKIS_DIR="$JW" JIRA_URL="http://127.0.0.1:$(cat "$J/port")" JIRA_API_TOKEN=smoke-token "$W" jira config
expect "a Jira out of reach during an event is for later, not a failure" "jira: later" env JIRA_AUTO_CLOSE=yes WIKIS_DIR="$JW" JIRA_URL="http://127.0.0.1:1" JIRA_API_TOKEN=smoke-token LLM_WIKI_EVENTS=wait "$W" extensions tick
lacks "so status says nothing" "extension jira" env WIKIS_DIR="$JW" "$W" status
expect "a sign-in Jira refuses during an event is a failure" "jira: failed" env JIRA_AUTO_CLOSE=yes WIKIS_DIR="$JW" JIRA_URL="http://127.0.0.1:$(cat "$J/port")" JIRA_API_TOKEN=bad LLM_WIKI_EVENTS=wait "$W" extensions tick
expect "and status says so" "extension jira: its last tick run failed" env WIKIS_DIR="$JW" "$W" status
kill "$JPID" 2>/dev/null
wait "$JPID" 2>/dev/null
expect "extensions remove turns it off" "off: jira" "$W" extensions remove jira
expect "and says so when it already was" "jira is already off." "$W" extensions remove jira
expect "a command about an extension that is off says how to turn it on" "jira is off. Turn it on: " "$W" extensions log jira
expect "every too" "jira is off. Turn it on: " "$W" extensions every jira 2h
refuse "and it no longer runs" "$W" jira --help
check "the docs say how to set it up" grep -q 'token_cmd' "$REPO/docs/extensions.md"
fi

if section "Confluence extension"; then
expect "the Confluence extension ships turned off" "confluence     off." "$W" extensions
"$W" extensions add confluence >/dev/null
expect "and runs once it is on" "Usage: " "$W" confluence --help
refuse "with no command it fails, with the usage" "$W" confluence
refuse "and refuses a command it doesn't know" "$W" confluence delete

# The markdown converter, on a page with one of everything.
C="$T/confluence"
mkdir -p "$C"
cat > "$C/page.md" <<'MD'
---
title: Demo
updated: 2026-11-01
---

# Demo

Some **bold**, *em*, `a <b>`, an [ext](https://example.com/a?b=1&c=2) and a snake_case_word.

1. One
   - nested
2. Two

- Bullet

> **Check:** wrong.

| A | B |
|---|---|
| 1 < 2 | x \| y |

```sh
echo "]]>" && true
```
MD
out="$("$W" confluence render "$C/page.md" 2>&1)"
check "render gives markup that parses" python3 -c "import sys, xml.dom.minidom; xml.dom.minidom.parseString('<r xmlns:ac=\"a\" xmlns:ri=\"r\">' + sys.argv[1] + '</r>')" "$out"
case "$out" in *"<strong>bold</strong>"*"<em>em</em>"*"<code>a &lt;b&gt;</code>"*'<a href="https://example.com/a?b=1&amp;c=2">ext</a>'*"snake_case_word"*) ok "inline markdown is converted, and markup in text is escaped" ;; *) bad "inline markdown is converted, and markup in text is escaped" "$out" ;; esac
case "$out" in *"<ol><li>One<ul><li>nested</li></ul></li><li>Two</li></ol><ul><li>Bullet</li></ul>"*) ok "lists nest, and a bulleted list after a numbered one is its own" ;; *) bad "lists nest, and a bulleted list after a numbered one is its own" "$out" ;; esac
case "$out" in *"<blockquote><p><strong>Check:</strong> wrong.</p></blockquote>"*"<th>A</th><th>B</th>"*"<td>1 &lt; 2</td><td>x | y</td>"*) ok "block quotes and tables are converted" ;; *) bad "block quotes and tables are converted" "$out" ;; esac
case "$out" in *'ac:name="code"><ac:parameter ac:name="language">sh</ac:parameter>'*'echo "]]]]><![CDATA[>" && true'*) ok "a code fence becomes a code macro, with its text kept whole" ;; *) bad "a code fence becomes a code macro, with its text kept whole" "$out" ;; esac
case "$out" in *"<h1>Demo</h1>"* | *"title: Demo"*) bad "the frontmatter and the page's own title are left out" "$out" ;; *) ok "the frontmatter and the page's own title are left out" ;; esac
expect "and the page says it is a copy" "Changes made here are overwritten" "$W" confluence render "$C/page.md"
expect "with its dates" "Updated 2026-11-01" "$W" confluence render "$C/page.md"

# A stand-in for Confluence: pages in memory, written out after every change.
cat > "$C/server.py" <<'PY'
import json, sys, urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer
D = sys.argv[1]
P = {"900": {"id": "900", "title": "Team home", "space": "ENG", "parent": "", "labels": [], "n": 1, "msg": "", "body": ""},
     "901": {"id": "901", "title": "cdemo: Taken", "space": "ENG", "parent": "900", "labels": [], "n": 1, "msg": "", "body": "by hand"}}
NEXT = [1000]
def view(p):
    return {"id": p["id"], "title": p["title"], "version": {"number": p["n"], "message": p["msg"], "when": p.get("when", "2026-11-01T00:00:00.000Z"), "by": {"displayName": "Ann Author"}},
            "body": {"storage": {"value": p["body"]}},
            "metadata": {"labels": {"results": [{"name": l} for l in p["labels"]]}}, "_links": {"webui": "/spaces/%s/pages/%s" % (p["space"], p["id"])}}
def save():
    json.dump(P, open(D + "/state.json", "w"), indent=1)
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def reply(self, code, body):
        self.send_response(code); self.send_header("Content-Type", "application/json"); self.end_headers()
        self.wfile.write(json.dumps(body).encode())
    def body(self):
        return json.loads(self.rfile.read(int(self.headers.get("Content-Length") or 0)) or b"null")
    def handle_one(self, method):
        if "bad" in self.headers.get("Authorization", ""): return self.reply(401, {"message": "no"})
        u = urllib.parse.urlparse(self.path); q = urllib.parse.parse_qs(u.query); parts = u.path.strip("/").split("/")
        if method != "GET": open(D + "/writes.log", "a").write(method + " " + u.path + "\n")
        if parts[:2] != ["rest", "api"]: return self.reply(404, {"message": "not here"})
        if method == "GET" and parts[2:] == ["user", "current"]: return self.reply(200, {"displayName": "Smoke Tester"})
        if method == "POST" and parts[2:] == ["__set"]:
            b = self.body(); P[b["id"]].update({k: v for k, v in b.items() if k != "id"})
            save(); return self.reply(200, {})
        if method == "GET" and parts[2:] == ["content", "search"]:
            import re
            m = re.search(r'space = "([^"]+)"', q.get("cql", [""])[0])
            return self.reply(200, {"results": [view(p) for p in P.values() if m and p["space"] == m.group(1)]})
        if method == "GET" and len(parts) == 6 and parts[4:] == ["state", "available"]:
            return self.reply(200, {"spaceContentStates": [{"name": "In progress"}, {"name": "Verified"}], "customContentStates": []})
        if method == "GET" and len(parts) == 5 and parts[4] == "state":
            if parts[3] not in P: return self.reply(404, {"message": "no such page"})
            return self.reply(200, {"contentState": {"name": P[parts[3]]["state"]}} if P[parts[3]].get("state") else {})
        if method == "GET" and len(parts) == 4 and parts[3].isdigit():
            if parts[3] not in P: return self.reply(404, {"message": "no such page"})
            return self.reply(200, view(P[parts[3]]))
        if method == "GET" and parts[2:] == ["content"]:
            if q.get("spaceKey", [""])[0] == "NOPE": return self.reply(404, {"message": "No space with key NOPE"})
            return self.reply(200, {"results": [view(p) for p in P.values() if p["space"] == q["spaceKey"][0] and p["title"] == q["title"][0]]})
        if method == "GET" and len(parts) == 6 and parts[4:] == ["child", "page"]:
            kids = [view(p) for p in P.values() if p["parent"] == parts[3]]
            start = int(q.get("start", ["0"])[0])
            return self.reply(200, {"results": kids[start:start + 100]})
        if method == "POST" and parts[2:] == ["content"]:
            b = self.body()
            if any(p["space"] == b["space"]["key"] and p["title"] == b["title"] for p in P.values()):
                return self.reply(400, {"message": "A page with this title already exists: " + b["title"]})
            i = str(NEXT[0]); NEXT[0] += 1
            P[i] = {"id": i, "title": b["title"], "space": b["space"]["key"], "parent": (b.get("ancestors") or [{"id": ""}])[0]["id"],
                    "labels": [], "n": 1, "msg": b.get("version", {}).get("message", ""), "body": b["body"]["storage"]["value"]}
            save(); return self.reply(200, view(P[i]))
        if method == "POST" and len(parts) == 5 and parts[4] == "label":
            P[parts[3]]["labels"] += [l["name"] for l in self.body()]
            save(); return self.reply(200, {})
        if method == "PUT" and len(parts) == 4 and parts[3] in P:
            b = self.body(); p = P[parts[3]]
            if b["version"]["number"] != p["n"] + 1: return self.reply(409, {"message": "Version must be incremented"})
            import datetime
            p.update(title=b["title"], n=b["version"]["number"], msg=b["version"].get("message", ""), body=b["body"]["storage"]["value"],
                     when=datetime.datetime.now(datetime.timezone.utc).isoformat())
            save(); return self.reply(200, view(p))
        self.reply(404, {"message": "not here"})
    def do_GET(self): self.handle_one("GET")
    def do_POST(self): self.handle_one("POST")
    def do_PUT(self): self.handle_one("PUT")
import socketserver
class S(HTTPServer):
    # HTTPServer's own bind looks the host's name up, which can take seconds on a Mac.
    def server_bind(self):
        socketserver.TCPServer.server_bind(self)
        self.server_name, self.server_port = "localhost", self.server_address[1]
s = S(("127.0.0.1", 0), H)
open(D + "/port", "w").write(str(s.server_address[1]))
s.serve_forever()
PY
python3 "$C/server.py" "$C" &
CPID=$!
i=0; while [ ! -s "$C/port" ] && [ "$i" -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
check "the stand-in Confluence server started" test -s "$C/port"
CW="$T/cwikis"
WIKIS_DIR="$CW" "$W" new cdemo >/dev/null 2>&1
mkdir -p "$CW/cdemo/wiki/concepts" "$CW/cdemo/wiki/how-to"
printf -- '---\ntitle: Alpha\n---\n\n# Alpha\n\nSee [the steps](../how-to/beta.md) and [a note](../../raw/x.md).\n' > "$CW/cdemo/wiki/concepts/alpha.md"
printf -- '---\ntitle: Beta\n---\n\nSteps.\n' > "$CW/cdemo/wiki/how-to/beta.md"
printf -- '---\ntitle: Alpha\n---\n\nAnother Alpha.\n' > "$CW/cdemo/wiki/how-to/alpha.md"
printf -- '---\ntitle: Taken\n---\n\nA title someone used.\n' > "$CW/cdemo/wiki/concepts/taken.md"
printf '# Index\n\n- [Alpha](wiki/concepts/alpha.md)\n' > "$CW/cdemo/index.md"
conf() { WIKIS_DIR="$CW" CONFLUENCE_URL="http://127.0.0.1:$(cat "$C/port")" CONFLUENCE_EMAIL=me@example.com CONFLUENCE_API_TOKEN=smoke-token "$W" confluence "$@"; }
state() { python3 -c "
import json, sys
P = json.load(open(sys.argv[1]))
$2" "$C/state.json"; }
expect "config tests the sign-in" "Signed in as Smoke Tester" conf config
expect "and says when nothing is chosen yet" "Nothing is chosen yet: no pages to watch, and no space to publish into. Run: " conf config
expect "publish needs a space" "no space to publish cdemo into" conf publish cdemo
expect "and says the command that sets one" "extensions setup confluence" conf publish cdemo
expect "with no sign-in, publish says that first" "Confluence isn't set up: no Confluence address yet. Run: " env WIKIS_DIR="$CW" "$W" confluence publish cdemo
check "with a sign-in and nothing chosen, confluence says so itself" test "$(env WIKIS_DIR="$CW" CONFLUENCE_URL=http://127.0.0.1:1 CONFLUENCE_API_TOKEN=x "$REPO/extensions/wiki-confluence" --wiki-ready)" = "nothing chosen yet: no pages to watch, and no space to publish into"
CH="$T/chome"
mkdir -p "$CH"
HOME="$CH" "$W" extensions add confluence >/dev/null 2>&1
expect "status lists confluence while it has no sign-in" "extension confluence: on, but not ready: no Confluence address yet. Run: " env HOME="$CH" WIKIS_DIR="$CW" "$W" status
out="$(printf 'http://127.0.0.1:%s\nme@example.com\nhttp://127.0.0.1:%s\n\n\ny\nENG\ncdemo\n' "$(cat "$C/port")" "$(cat "$C/port")" | env -u CONFLUENCE_SPACE HOME="$CH" WIKIS_DIR="$CW" ATLASSIAN_API_TOKEN=smoke-token "$W" extensions setup confluence 2>&1)"
case "$out" in *"Confluence's own address is needed"*"Signed in to Confluence as Smoke Tester."*"Key of the space to publish into"*"confluence is set up."*) ok "confluence's setup asks for its address where the site isn't Cloud, the space, and tests the sign-in" ;; *) bad "confluence's setup asks for its address where the site isn't Cloud, the space, and tests the sign-in" "$out" ;; esac
case "$out" in *"to everyone who can read that space"*"Set up publishing?"*"Key of the space to publish into"*) ok "and says who can read what is published, before asking whether to publish at all" ;; *) bad "and says who can read what is published, before asking whether to publish at all" "$out" ;; esac
check "the space is saved" grep -qx "space = ENG" "$CH/.config/llm-wiki/confluence"
check "and the wikis to publish by themselves" grep -qx "auto = cdemo" "$CH/.config/llm-wiki/confluence"
lacks "status then has nothing to say about it" "extension confluence" env -u CONFLUENCE_SPACE HOME="$CH" WIKIS_DIR="$CW" ATLASSIAN_API_TOKEN=smoke-token "$W" status
refuse "and a wiki that is there" env CONFLUENCE_SPACE=ENG WIKIS_DIR="$CW" CONFLUENCE_URL="http://127.0.0.1:$(cat "$C/port")" CONFLUENCE_API_TOKEN=smoke-token "$W" confluence publish nosuch
expect "a space Confluence doesn't know is said plainly" "can't read the space NOPE" env CONFLUENCE_SPACE=NOPE WIKIS_DIR="$CW" CONFLUENCE_URL="http://127.0.0.1:$(cat "$C/port")" CONFLUENCE_API_TOKEN=smoke-token "$W" confluence publish cdemo
export CONFLUENCE_SPACE=ENG
out="$(conf publish cdemo --dry-run 2>&1)"
case "$out" in *"Would publish 5 page(s) of cdemo to the space ENG"*"would create: cdemo wiki"*"would create: cdemo: Beta"*"4 to create, 0 to update, 0 unchanged"*) ok "a dry run says what would be created" ;; *) bad "a dry run says what would be created" "$out" ;; esac
case "$out" in *"not published: cdemo: Taken: a page of that name is already in the space"*"Rename that page in Confluence, or change this page's title in the wiki."*) ok "and sees a title someone else has, with what to do about it" ;; *) bad "and sees a title someone else has, with what to do about it" "$out" ;; esac
case "$out" in *"would create: cdemo: Taken"*) bad "without saying it would create that page" "$out" ;; *) ok "without saying it would create that page" ;; esac
check "and writes nothing" test ! -e "$C/writes.log"
out="$(conf publish cdemo 2>&1)"
code=$?
case "$out" in *"created: cdemo wiki"*"created: cdemo: Beta"*"cdemo: 4 created, 0 updated, 0 unchanged."*) ok "publish creates the index and the pages" ;; *) bad "publish creates the index and the pages" "$out" ;; esac
case "$out" in *"not published: cdemo: Taken: a page of that name is already in the space"*"Rename that page in Confluence"*) ok "a title someone else used is reported with its fix, and the rest still go" ;; *) bad "a title someone else used is reported with its fix, and the rest still go" "$out" ;; esac
case "$out" in *"created: cdemo: Taken"*) bad "and a page that wasn't created isn't said to be" "$out" ;; *) ok "and a page that wasn't created isn't said to be" ;; esac
[ "$code" -eq 1 ] && ok "and publish fails, so it is noticed" || bad "and publish fails, so it is noticed" "exit $code"
case "$out" in *"/spaces/ENG/pages/1000"*) ok "it ends with the address of the wiki's page" ;; *) bad "it ends with the address of the wiki's page" "$out" ;; esac
check "the index is the parent of the pages" state x "
top = [p for p in P.values() if p['title'] == 'cdemo wiki'][0]
kids = sorted(p['title'] for p in P.values() if p['parent'] == top['id'])
assert kids == ['cdemo: Alpha (concepts/alpha)', 'cdemo: Alpha (how-to/alpha)', 'cdemo: Beta'], kids"
check "every page it made carries its label" state x "
assert all(p['labels'] == ['llm-wiki'] for p in P.values() if int(p['id']) >= 1000)"
check "a link between pages points at the page's title in Confluence" state x "
a = [p for p in P.values() if p['title'] == 'cdemo: Alpha (concepts/alpha)'][0]['body']
assert '<ri:page ri:content-title=\"cdemo: Beta\"/><ac:link-body>the steps</ac:link-body>' in a, a
assert 'raw/x.md' not in a and 'a note' in a, a"
check "the page someone else made is as it was" state x "assert P['901']['body'] == 'by hand' and P['901']['n'] == 1"
: > "$C/writes.log"
expect "a second publish finds nothing changed" "0 created, 0 updated, 4 unchanged" conf publish cdemo
check "and writes only its try at the taken title" test "$(grep -c . "$C/writes.log")" = 1
printf -- '---\ntitle: Beta\n---\n\nSteps, revised.\n' > "$CW/cdemo/wiki/how-to/beta.md"
expect "a changed page is updated, and only it" "0 created, 1 updated, 3 unchanged" conf publish cdemo
check "as the page's next version" state x "
b = [p for p in P.values() if p['title'] == 'cdemo: Beta'][0]
assert b['n'] == 2 and 'revised' in b['body'], b"
rm "$CW/cdemo/wiki/how-to/beta.md" "$CW/cdemo/wiki/concepts/taken.md"
out="$(conf publish cdemo 2>&1)"
code=$?
case "$out" in *"no longer in the wiki, left in Confluence: cdemo: Beta"*) ok "a page gone from the wiki is reported and left in Confluence" ;; *) bad "a page gone from the wiki is reported and left in Confluence" "$out" ;; esac
[ "$code" -eq 0 ] && ok "and with no title taken, publish succeeds" || bad "and with no title taken, publish succeeds" "exit $code: $out"
check "nothing was deleted" state x "assert any(p['title'] == 'cdemo: Beta' for p in P.values())"
WIKIS_DIR="$CW" "$W" new other >/dev/null 2>&1
printf 'space.other = ENG\nparent.other = 900\nspace = ENG\n' > "$HOME/.config/llm-wiki/confluence"
expect "parent puts a wiki's pages under a page you name" "created: other wiki" conf publish other
check "under that page" state x "assert [p for p in P.values() if p['title'] == 'other wiki'][0]['parent'] == '900'"
printf 'url = https://acme.atlassian.net\nemail = j@example.com\ntoken_cmd = echo jira-token\n' > "$HOME/.config/llm-wiki/jira"
out="$(env -u CONFLUENCE_SPACE WIKIS_DIR="$CW" "$W" confluence config 2>&1 || true)"
case "$out" in *"url       https://acme.atlassian.net/wiki"*"email     j@example.com"*"token     from token_cmd"*) ok "the sign-in falls back to the Jira extension's settings" ;; *) bad "the sign-in falls back to the Jira extension's settings" "$out" ;; esac
case "$out" in *jira-token*) bad "and the token is never printed" "$out" ;; *) ok "and the token is never printed" ;; esac
printf 'site = https://shared.atlassian.net\nemail = shared@example.com\ntoken_cmd = echo shared-token\n' > "$HOME/.config/llm-wiki/atlassian"
out="$(env -u CONFLUENCE_SPACE WIKIS_DIR="$CW" "$W" confluence config 2>&1 || true)"
case "$out" in *"url       https://shared.atlassian.net/wiki  (from the shared file)"*"email     shared@example.com  (from the shared file)"*"token     from token_cmd in the shared file"*) ok "confluence takes its sign-in from the shared Atlassian file, before Jira's" ;; *) bad "confluence takes its sign-in from the shared Atlassian file, before Jira's" "$out" ;; esac
printf 'site = https://jira.example.com\nemail = shared@example.com\ntoken_cmd = echo shared-token\n' > "$HOME/.config/llm-wiki/atlassian"
rm "$HOME/.config/llm-wiki/jira"
out="$(env -u CONFLUENCE_SPACE WIKIS_DIR="$CW" "$W" confluence config 2>&1 || true)"
case "$out" in *"url       not set"*"email     shared@example.com"*) ok "a site that isn't Atlassian Cloud gives no Confluence address, since a server's differs" ;; *) bad "a site that isn't Atlassian Cloud gives no Confluence address, since a server's differs" "$out" ;; esac
printf 'x = y\n' > "$HOME/.config/llm-wiki/jira"
rm "$HOME/.config/llm-wiki/atlassian"
rm "$HOME/.config/llm-wiki/jira" "$HOME/.config/llm-wiki/confluence"
WIKIS_DIR="$CW" "$W" new "team" >/dev/null 2>&1
python3 - "$C" <<'PY3'
import json, sys, urllib.request
port = open(sys.argv[1] + "/port").read()
req = urllib.request.Request("http://127.0.0.1:%s/rest/api/content" % port, method="POST", headers={"Content-Type": "application/json"},
    data=json.dumps({"title": "team wiki", "space": {"key": "ENG"}, "body": {"storage": {"value": "ours, by hand"}}}).encode())
urllib.request.urlopen(req).read()
PY3
expect "a page with the wiki's own title that someone else made stops the publish" "that llm-wiki didn't make" conf publish team
refuse "and it fails" conf publish team
expect "a sign-in Confluence refuses is said plainly" "refused the sign-in" env WIKIS_DIR="$CW" CONFLUENCE_URL="http://127.0.0.1:$(cat "$C/port")" CONFLUENCE_API_TOKEN=bad "$W" confluence publish cdemo
# With auto, a sync that changes a wiki's pages publishes it, with nobody asking.
expect "confluence asks for the sync and tick events" "(runs on: sync, tick)" "$W" extensions
CA="$T/cauto"
WIKIS_DIR="$CA" "$W" init --git >/dev/null 2>&1
WIKIS_DIR="$CA" "$W" new pub >/dev/null 2>&1
mkdir -p "$CA/pub/wiki/concepts"
printf -- '---\ntitle: Auto\n---\n\nFirst.\n' > "$CA/pub/wiki/concepts/auto.md"
cauto() { WIKIS_DIR="$CA" CONFLUENCE_URL="http://127.0.0.1:$(cat "$C/port")" CONFLUENCE_EMAIL=me@example.com CONFLUENCE_API_TOKEN=smoke-token LLM_WIKI_EVENTS=wait "$W" "$@"; }
cauto sync pub -m "a page" >/dev/null 2>&1
check "with auto empty, a sync publishes nothing" state x "assert not any(p['title'] == 'pub wiki' for p in P.values())"
printf -- '---\ntitle: Auto\n---\n\nSecond.\n' > "$CA/pub/wiki/concepts/auto.md"
CONFLUENCE_AUTO=other cauto sync pub -m "a page" >/dev/null 2>&1
check "nor for a wiki that auto doesn't name" state x "assert not any(p['title'] == 'pub wiki' for p in P.values())"
printf -- '---\ntitle: Auto\n---\n\nThird.\n' > "$CA/pub/wiki/concepts/auto.md"
CONFLUENCE_AUTO="other, pub" cauto sync pub -m "a page" >/dev/null 2>&1
check "a sync that changes a page of a wiki in auto publishes it" state x "
a = [p for p in P.values() if p['title'] == 'pub: Auto']
assert a and 'Third.' in a[0]['body'], a"
: > "$C/writes.log"
echo "a note" | cauto capture pub note >/dev/null
CONFLUENCE_AUTO=pub cauto sync pub >/dev/null 2>&1
check "a sync that changed only notes reaches for nothing" test ! -s "$C/writes.log"
check "and its log says why" grep -q "no page of pub changed" "$HOME/.local/state/llm-wiki/extensions/confluence/sync-pub.log"
printf -- '---\ntitle: Auto\n---\n\nFourth.\n' > "$CA/pub/wiki/concepts/auto.md"
expect "the tick catches up on a page no sync published" "confluence: ok" env CONFLUENCE_AUTO=pub WIKIS_DIR="$CA" CONFLUENCE_URL="http://127.0.0.1:$(cat "$C/port")" CONFLUENCE_EMAIL=me@example.com CONFLUENCE_API_TOKEN=smoke-token LLM_WIKI_EVENTS=wait "$W" extensions tick
check "with the page as it is on disk" state x "assert 'Fourth.' in [p for p in P.values() if p['title'] == 'pub: Auto'][0]['body']"
printf -- '---\ntitle: Auto\n---\n\nFifth.\n' > "$CA/pub/wiki/concepts/auto.md"
out="$(env CONFLUENCE_AUTO="gone, pub" WIKIS_DIR="$CA" CONFLUENCE_URL="http://127.0.0.1:$(cat "$C/port")" CONFLUENCE_EMAIL=me@example.com CONFLUENCE_API_TOKEN=smoke-token LLM_WIKI_EVENTS=wait "$W" extensions tick 2>&1 || true)"
case "$out" in *"confluence: failed"*) ok "auto naming a wiki that isn't here fails the run" ;; *) bad "auto naming a wiki that isn't here fails the run" "$out" ;; esac
check "and its log says which, and to take it out" grep -q "auto names gone, which isn't a wiki here. Take it out of auto in" "$HOME/.local/state/llm-wiki/extensions/confluence/tick.log"
check "while the wikis after it are still published" state x "assert 'Fifth.' in [p for p in P.values() if p['title'] == 'pub: Auto'][0]['body']"
expect "config says so too" "auto names gone, which isn't a wiki here" env CONFLUENCE_AUTO="gone, pub" WIKIS_DIR="$CA" CONFLUENCE_URL="http://127.0.0.1:$(cat "$C/port")" CONFLUENCE_API_TOKEN=smoke-token "$W" confluence config
env CONFLUENCE_AUTO=pub WIKIS_DIR="$CA" CONFLUENCE_URL="http://127.0.0.1:$(cat "$C/port")" CONFLUENCE_EMAIL=me@example.com CONFLUENCE_API_TOKEN=smoke-token LLM_WIKI_EVENTS=wait "$W" extensions tick >/dev/null 2>&1
printf 'site = https://jira.example.com\ntoken_cmd = echo t\n' > "$HOME/.config/llm-wiki/atlassian"
expect "a site that isn't Atlassian Cloud says Confluence needs its own address, not to set the site" "jira.example.com isn't on Atlassian Cloud, so Confluence's own address is needed" env -u CONFLUENCE_SPACE WIKIS_DIR="$CA" "$W" confluence publish pub
rm "$HOME/.config/llm-wiki/atlassian"
expect "a space Confluence can't read ends with what to check" "Check space in" env CONFLUENCE_SPACE=NOPE WIKIS_DIR="$CW" CONFLUENCE_URL="http://127.0.0.1:$(cat "$C/port")" CONFLUENCE_API_TOKEN=smoke-token "$W" confluence publish cdemo
expect "config names the wikis in auto" "auto      pub" env CONFLUENCE_AUTO=pub WIKIS_DIR="$CA" CONFLUENCE_URL="http://127.0.0.1:$(cat "$C/port")" CONFLUENCE_API_TOKEN=smoke-token "$W" confluence config
expect "a Confluence out of reach during an event is for later" "confluence: later" env CONFLUENCE_AUTO=pub WIKIS_DIR="$CA" CONFLUENCE_URL="http://127.0.0.1:1" CONFLUENCE_API_TOKEN=smoke-token LLM_WIKI_EVENTS=wait "$W" extensions tick
lacks "so status says nothing" "extension confluence" env WIKIS_DIR="$CA" "$W" status
# Watching: a wiki hears when a Confluence page it names changes, or its status does.
WW="$T/wwikis"
WIKIS_DIR="$WW" "$W" new wdemo >/dev/null 2>&1
cport="$(cat "$C/port")"
wch() { env -u CONFLUENCE_SPACE WIKIS_DIR="$WW" CONFLUENCE_URL="http://127.0.0.1:$cport" CONFLUENCE_EMAIL=me@example.com CONFLUENCE_API_TOKEN=smoke-token "$W" confluence "$@"; }
# cset <id> <field> <value>, and cput <id> <body>: change a page on the stand-in.
cset() { python3 -c "
import json, sys, urllib.request
urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:$cport/rest/api/__set', method='POST', data=json.dumps({'id': sys.argv[1], sys.argv[2]: sys.argv[3]}).encode())).read()" "$@"; }
cput() { python3 -c "
import json, sys, urllib.request
base = 'http://127.0.0.1:$cport/rest/api/content/' + sys.argv[1]
p = json.load(urllib.request.urlopen(base))
urllib.request.urlopen(urllib.request.Request(base, method='PUT', headers={'Content-Type': 'application/json'}, data=json.dumps({'title': p['title'], 'version': {'number': p['version']['number'] + 1}, 'body': {'storage': {'value': sys.argv[2]}}}).encode())).read()" "$@"; }
body="$(for i in 1 2 3 4 5 6 7 8 9 10 11 12; do printf '<p>Line %s of the plan.</p>' "$i"; done)"
cput 900 "<h1>Plan</h1>$body"
expect "with a sign-in and nothing to watch, check says how to choose" "No wiki watches a page yet. Run: " wch check
printf 'watch.wdemo = http://127.0.0.1/wiki/spaces/ENG/pages/900/Team+home\n' > "$HOME/.config/llm-wiki/confluence"
out="$(wch check 2>&1)"
case "$out" in *"== wdemo"*"Team home"*"version 2"*"first read"*"1 change(s) to note. To note them in the wiki: "*) ok "check reads a watched page, named by its address, and says it is new to the wiki" ;; *) bad "check reads a watched page, named by its address, and says it is new to the wiki" "$out" ;; esac
check "and saves nothing" test -z "$(find "$WW/wdemo/raw" -name '*-confluence.md')"
expect "check --save notes it in the wiki" "wdemo: noted 1 change(s). The next compile works them into the wiki." wch check --save
note="$(ls "$WW/wdemo/raw"/*-confluence.md | tail -n 1)"
check "the note has the page's title and address" grep -q "^- page: http://127.0.0.1:$cport/spaces/ENG/pages/900" "$note"
check "its text, as plain text" grep -qx "Line 7 of the plan." "$note"
check "and the line the next check reads the version from" grep -qx "Confluence-page: 900 | version 2 | status " "$note"
out="$(wch check 2>&1)"
case "$out" in *"Team home"*"unchanged"*"Nothing changed."*) ok "a second check finds nothing changed, from the wiki's own notes" ;; *) bad "a second check finds nothing changed, from the wiki's own notes" "$out" ;; esac
lacks "and a second --save saves no second note" "noted" wch check --save
cput 900 "<h1>Plan</h1>$(printf '%s' "$body" | sed 's/Line 7 of the plan/Line 7, rewritten/')"
expect "a page whose text changed is said to be, with who and when" "changed by Ann Author on " wch check
wch check --save >/dev/null 2>&1
note="$(grep -l "What changed in the page's text" "$WW/wdemo/raw"/*.md | head -n 1)"
check "the note then carries only what changed" grep -qx "+Line 7, rewritten." "$note"
lacks "and not the lines that didn't" "Line 2 of the plan." cat "$note"
cset 900 state Verified
expect "a page whose status changed is said to be, though its text didn't" "status changed" wch check
wch check --save >/dev/null 2>&1
note="$(grep -l "change: status changed" "$WW/wdemo/raw"/*.md | head -n 1)"
check "the note says the old status and the new" grep -qx -- "- status: Verified (was none)" "$note"
lacks "and has no text, since none changed" "The page's text" cat "$note"
# An open item whose heading links a page closes when the page's status means finished.
printf '# Open\n\n## Sign off the plan http://127.0.0.1/wiki/spaces/ENG/pages/900/Team+home\n- kind: waiting\n- who: Katherine\n- status: open\n- from: 2026-11-10 raw/a.md\n\n## Read page 901 http://127.0.0.1/wiki/spaces/ENG/pages/901/x\n- kind: waiting\n- who: user\n- status: open\n- from: 2026-11-10 raw/a.md\n' > "$WW/wdemo/open.md"
out="$(wch check 2>&1)"
case "$out" in *"open item: Sign off the plan"*"its page is Verified, which means finished: the item closes"*) ok "an open item that links a finished page is said to close" ;; *) bad "an open item that links a finished page is said to close" "$out" ;; esac
case "$out" in *"open item: Read page 901"*) bad "and not one whose page has no such status" "$out" ;; *) ok "and not one whose page has no such status" ;; esac
wch check --save >/dev/null 2>&1
check "check --save notes the item as done" grep -rqx "Done: Sign off the plan http://127.0.0.1/wiki/spaces/ENG/pages/900/Team+home" "$WW/wdemo/raw"
expect "and not a second time, while the first waits for a compile" "already noted as done, waiting for a compile" wch check --save
lacks "so nothing more is saved" "noted 1" wch check --save
printf 'watch.wdemo = 900\ndone_states = Approved\n' > "$HOME/.config/llm-wiki/confluence"
rm "$WW/wdemo/raw"/*-confluence.md
lacks "done_states decides which statuses mean finished" "the item closes" wch check
# A whole space, from now on.
printf 'watch.wdemo = space:ENG\n' > "$HOME/.config/llm-wiki/confluence"
expect "a space is watched from now on, and its old pages aren't read" "space ENG: watched from now on." wch check --save
lacks "so the first check of a space notes nothing" "first read" wch check
cput 901 "<p>Edited after the watch began.</p>"
out="$(wch check 2>&1)"
case "$out" in *"space ENG: 1 page(s) changed since "*"cdemo: Taken"*"first read"*) ok "a page changed in a watched space after that is found" ;; *) bad "a page changed in a watched space after that is found" "$out" ;; esac
# What can't be read is said, with its fix, and fails the check.
printf 'watch.wdemo = 99999, nope\nwatch.gone = 900\n' > "$HOME/.config/llm-wiki/confluence"
out="$(wch check 2>&1)"
code=$?
case "$out" in *"99999 isn't a page you can read. Take it out of watch.wdemo in "*) ok "a page that can't be read is said, with what to change" ;; *) bad "a page that can't be read is said, with what to change" "$out" ;; esac
case "$out" in *"nope isn't a page's address, an id, or space:KEY. Fix watch.wdemo in "*) ok "and a word that is no page" ;; *) bad "and a word that is no page" "$out" ;; esac
case "$out" in *"watch.gone names a wiki that isn't here. Take it out of "*) ok "and a wiki that isn't here" ;; *) bad "and a wiki that isn't here" "$out" ;; esac
[ "$code" -eq 1 ] && ok "and check fails, so a run by itself is noticed" || bad "and check fails, so a run by itself is noticed" "exit $code"
# By itself: the tick event does check --save.
printf 'watch.wdemo = 900\n' > "$HOME/.config/llm-wiki/confluence"
cput 900 "<p>Changed for the tick.</p>"
expect "with pages to watch, the tick event checks them by itself" "confluence: ok" env -u CONFLUENCE_SPACE WIKIS_DIR="$WW" CONFLUENCE_URL="http://127.0.0.1:$cport" CONFLUENCE_EMAIL=me@example.com CONFLUENCE_API_TOKEN=smoke-token LLM_WIKI_EVENTS=wait "$W" extensions tick
check "and notes the change" grep -rq "Changed for the tick." "$WW/wdemo/raw"
expect "config shows what is watched and which statuses mean finished" "watch     wdemo: 900" wch config
expect "and that publishing is off" "Publishing is off: no space is set." wch config
# The guided setup says what each choice does, checks each page as it is named, and ends with what is set.
WH="$T/whome"
mkdir -p "$WH"
HOME="$WH" "$W" extensions add confluence >/dev/null 2>&1
out="$(printf 'http://127.0.0.1:%s\n\nhttp://127.0.0.1:%s\nwdemo\n900, 99999, nope, space:ENG\nn\n\nn\n' "$cport" "$cport" | env -u CONFLUENCE_SPACE HOME="$WH" WIKIS_DIR="$WW" ATLASSIAN_API_TOKEN=smoke-token "$W" extensions setup confluence 2>&1)"
case "$out" in *"It can do two separate things. Neither happens until you choose it here."*"Watch "*"Reads Confluence."*"Publish "*"Writes to Confluence."*) ok "setup opens by saying the two things it can do, and that neither happens unasked" ;; *) bad "setup opens by saying the two things it can do" "$out" ;; esac
case "$out" in *"== Step 1 of 3: sign in"*"== Step 2 of 3: watch pages"*"== Step 3 of 3: publish (optional)"*) ok "in three numbered steps" ;; *) bad "in three numbered steps" "$out" ;; esac
case "$out" in *"What it does "*"When it runs "*"What it costs "*"What it sends"*"Nothing. Watching only reads."*) ok "watching is explained before it is asked about: what it does, when, the cost, and that it sends nothing" ;; *) bad "watching is explained before it is asked about" "$out" ;; esac
case "$out" in *"Your wikis: wdemo"*) ok "it lists your wikis to choose from" ;; *) bad "it lists your wikis to choose from" "$out" ;; esac
case "$out" in *"Team home (version "*", Verified)"*"99999 isn't a page you can read, so it was left out."*"nope isn't a page's address, an id, or space:KEY, so it was left out."*"space ENG: every page in it, from now on"*) ok "each page is checked as it is named: its title and status, or why it was left out" ;; *) bad "each page is checked as it is named" "$out" ;; esac
check "and only what could be read is saved" grep -qx "watch.wdemo = 900, space:ENG" "$WH/.config/llm-wiki/confluence"
case "$out" in *"Statuses your Confluence offers: In progress, Verified"*) ok "it shows the statuses your Confluence has, before asking which mean finished" ;; *) bad "it shows the statuses your Confluence has" "$out" ;; esac
case "$out" in *"What it sends"*"The wiki's pages, to everyone who can read that space."*"Set up publishing?"*"Publishing stays off. Nothing of yours goes to Confluence."*) ok "publishing is explained, then asked as a yes or no, and a no says nothing is sent" ;; *) bad "publishing is explained, then asked as a yes or no" "$out" ;; esac
lacks "and a no saves no space" "space =" cat "$WH/.config/llm-wiki/confluence"
case "$out" in *"What is set"*"Watching     wdemo hears about 1 page(s) and the space ENG"*"Finished is  Verified"*"Publishing   off"*"What happens now"*"confluence check"*) ok "it ends with what is set, a line for each choice, and what happens now" ;; *) bad "it ends with what is set and what happens now" "$out" ;; esac
case "$out" in *"confluence is set up."*) ok "and with pages to watch, it is set up without a space" ;; *) bad "and with pages to watch, it is set up without a space" "$out" ;; esac
rm "$HOME/.config/llm-wiki/confluence"
unset CONFLUENCE_SPACE
kill "$CPID" 2>/dev/null
wait "$CPID" 2>/dev/null
"$W" extensions remove confluence >/dev/null
check "the docs say who can read what is published" grep -q 'Everyone who can read the space' "$REPO/docs/extensions.md"
fi

if section "Extension events"; then
# An extension that asks for events is run when they happen, with nobody asking.
XD="$HOME/.local/share/llm-wiki/extensions"
XS="$HOME/.local/state/llm-wiki/extensions"
EW="$T/ewikis"
REC="$T/rec"
mkdir -p "$XD" "$REC"
WIKIS_DIR="$EW" "$W" init --git >/dev/null 2>&1
WIKIS_DIR="$EW" "$W" new edemo >/dev/null 2>&1
ew() { WIKIS_DIR="$EW" LLM_WIKI_EVENTS=wait "$W" "$@"; }
ew sync edemo -m "start" >/dev/null 2>&1
cat > "$XD/wiki-rec" <<EXT
#!/bin/sh
# wiki-extension: Records the events it is given, for the smoke test.
# wiki-events: sync tick
echo "\$*|api=\$LLM_WIKI_EXTENSION|in=\$LLM_WIKI_IN_EVENT|changed=\$(tr '\n' ' ' < "\${LLM_WIKI_CHANGED:-/dev/null}")" >> "$REC/log"
echo "said on the way"
[ ! -f "$REC/sleep" ] || sleep 30
[ ! -f "$REC/sync-again" ] || { rm "$REC/sync-again"; echo nested | "\$LLM_WIKI" capture edemo nested >/dev/null; "\$LLM_WIKI" sync edemo >/dev/null; }
exit "\$(cat "$REC/exit" 2>/dev/null || echo 0)"
EXT
printf '#!/bin/sh\n# wiki-extension: Asks for nothing.\necho called >> "%s/quiet"\n' "$REC" > "$XD/wiki-quiet"
chmod +x "$XD/wiki-rec" "$XD/wiki-quiet"
expect "extensions says which events one runs on" "(runs on: sync, tick)" ew extensions
# A comment that asks for something that will never happen is said, not left silent.
printf '#!/bin/sh\n# wiki-extension: Misspelled.\n# wiki-events: ticks\necho x\n' > "$XD/wiki-typo"
printf '#!/bin/sh\n# wiki-extension: Too far down.\n#\n#\n#\n#\n#\n#\n#\n#\n#\n#\n# wiki-events: tick\necho x\n' > "$XD/wiki-late"
chmod +x "$XD/wiki-typo" "$XD/wiki-late"
expect "an event that doesn't exist is said in the list" "no event is called ticks, so it is never run for it. The events are sync and tick." ew extensions
expect "and a comment past the first ten lines" "its wiki- comment on line 13 is past the first ten lines, so it is not read. Move it up." ew extensions
rm "$XD/wiki-typo" "$XD/wiki-late"
lacks "and nothing for one that asks for none" "quiet          Asks for nothing. (runs on" ew extensions
echo "a note" | ew capture edemo first >/dev/null
ew sync edemo -m "a note" >/dev/null 2>&1
out="$(cat "$REC/log" 2>/dev/null)"
case "$out" in "--wiki-event sync edemo|api=3|in=1|changed=raw/"*"-first.md "*) ok "a sync that changed a wiki runs the extension, with the paths it changed" ;; *) bad "a sync that changed a wiki runs the extension, with the paths it changed" "$out" ;; esac
check "what it printed is in its log" grep -q "said on the way" "$XS/rec/sync-edemo.log"
check "and the run is recorded as fine" grep -q "^ok" "$XS/rec/sync-edemo.status"
check "an extension that asks for no events is never run" test ! -e "$REC/quiet"
ew sync edemo >/dev/null 2>&1
check "a sync that changed nothing runs nothing" test "$(grep -c . "$REC/log")" = 1
# A run that is still going takes the next sync's paths when it ends.
mkdir "$XS/rec/sync-edemo.running"
echo "second" | ew capture edemo second >/dev/null
ew sync edemo >/dev/null 2>&1
check "while one run is going, another isn't started" test "$(grep -c . "$REC/log")" = 1
rmdir "$XS/rec/sync-edemo.running"
echo "third" | ew capture edemo third >/dev/null
ew sync edemo >/dev/null 2>&1
out="$(sed -n 2p "$REC/log")"
case "$out" in *"-second.md"*"-third.md"* | *"-third.md"*"-second.md"*) ok "and the paths it missed come with the next" ;; *) bad "and the paths it missed come with the next" "$out" ;; esac
# tick, from session start, once per interval.
: > "$REC/log"
ew start >/dev/null 2>&1
expect "session start runs the tick event" "--wiki-event tick|api=3" cat "$REC/log"
ew start >/dev/null 2>&1
check "and not again within the interval" test "$(grep -c . "$REC/log")" = 1
expect "extensions tick runs it now" "rec: ok" ew extensions tick
check "whatever the interval" test "$(grep -c . "$REC/log")" = 2
# How often the tick comes is a setting: one for all extensions, and one of its own for any.
expect "the tick comes every 24 hours unless set" "tick: every 24h" ew extensions every
expect "extensions every sets it, as a length of time" "tick: every 4h" ew extensions every 4h
expect "in days" "tick: every 2d" ew extensions every 2d
expect "or weeks" "tick: every 3w" ew extensions every 3w
expect "or minutes" "tick: every 90m" ew extensions every 90m
refuse "it wants a number and a unit" ew extensions every soon
expect "and says so for a bare number" "such as 4h or 2d" ew extensions every 4
refuse "which fails" ew extensions every 4
refuse "no less than five minutes" ew extensions every 2m
refuse "and no more than a year" ew extensions every 99w
expect "a refused value changes nothing" "tick: every 90m" ew extensions every
ew extensions every 4h >/dev/null
age() { python3 -c "import os, sys, time; t = time.time() - float(sys.argv[2]) * 3600; os.utime(sys.argv[1], (t, t))" "$XS/rec/tick.stamp" "$1"; }
age 3
ew start >/dev/null 2>&1
check "at every 4h, a tick 3 hours old isn't due" test "$(grep -c . "$REC/log")" = 2
age 5
ew start >/dev/null 2>&1
check "and one 5 hours old is" test "$(grep -c . "$REC/log")" = 3
ew extensions every 24h >/dev/null
age 5
ew start >/dev/null 2>&1
check "back at every 24h, it isn't" test "$(grep -c . "$REC/log")" = 3
# One extension's own interval wins over the one for all.
expect "an extension can have an interval of its own" "rec: every 1h" ew extensions every rec 1h
age 2
ew start >/dev/null 2>&1
check "and it wins: at 1h, a tick 2 hours old is due though the rest wait 24h" test "$(grep -c . "$REC/log")" = 4
out="$(ew extensions every 2>&1)"
case "$out" in *"tick: every 24h"*"rec: every 1h"*) ok "extensions every lists the one for all and each of its own" ;; *) bad "extensions every lists the one for all and each of its own" "$out" ;; esac
expect "and one extension's on request" "rec: every 1h" ew extensions every rec
expect "setup --list shows both" "every 24h; rec 1h" bash -c "WIKIS_DIR='$EW' '$W' setup --list | grep '^extensions'"
expect "and so does the list of extensions" "every 24h; rec 1h" ew extensions
ew extensions every 2d >/dev/null
expect "changing the one for all leaves an extension's own alone" "rec: every 1h" ew extensions every rec
ew extensions every 24h >/dev/null
expect "default gives an extension back the one for all" "rec: every 24h, the same as the rest" ew extensions every rec default
age 2
ew start >/dev/null 2>&1
check "and then a tick 2 hours old isn't due" test "$(grep -c . "$REC/log")" = 4
refuse "an interval needs an extension that is on" ew extensions every nosuch 4h
refuse "and a length of time it can read" ew extensions every rec often
out="$(printf 'n\nn\n6h\n' | WIKIS_DIR="$EW" LLM_WIKI_TEST_TTY=1 "$W" setup extensions 2>&1)"
case "$out" in *"Time between runs"*"tick: every 6h"*) ok "setup asks how often, and keeps the answer" ;; *) bad "setup asks how often, and keeps the answer" "$out" ;; esac
out="$(printf 'n\nn\nsoon\n' | WIKIS_DIR="$EW" LLM_WIKI_TEST_TTY=1 "$W" setup extensions 2>&1)"
case "$out" in *"isn't a length of time"*"tick: every 6h"*) ok "an answer that isn't a length of time changes nothing" ;; *) bad "an answer that isn't a length of time changes nothing" "$out" ;; esac
ew extensions every 24h >/dev/null
expect "completion offers every" "every" "$W" __complete 2 extensions ""
expect "and the extensions that are on, after it" "rec" "$W" __complete 3 extensions every ""
# How a run ends.
lacks "a run that went fine leaves status alone" "extension rec" ew status
echo 75 > "$REC/exit"
expect "exit 75 means not now" "rec: later" ew extensions tick
lacks "and status says nothing about it" "extension rec" ew status
echo 3 > "$REC/exit"
expect "any other failure is one" "rec: failed" ew extensions tick
expect "status says so, with the fix" "extension rec: its last tick run failed (exit 3). Run: " ew status
out="$(ew extensions log rec 2>&1)"
case "$out" in *"tick: failed (exit 3)"*"said on the way"*) ok "extensions log shows how each run ended and what it printed" ;; *) bad "extensions log shows how each run ended and what it printed" "$out" ;; esac
refuse "extensions log needs a name it knows" ew extensions log nosuch
refuse "extensions tick fails when a run did, for cron" ew extensions tick
expect "and says where to read why" "extensions log rec shows why" ew extensions tick
expect "extensions log ends with what to run once it is fixed" "Once that is fixed, run it again with: " ew extensions log rec
# Put off three times in a row is no longer "not now": a mistyped address looks like this.
echo 75 > "$REC/exit"
ew extensions tick >/dev/null 2>&1
ew extensions tick >/dev/null 2>&1
lacks "a run put off twice is still nothing to report" "extension rec" ew status
expect "extensions tick says a run was put off, and where to read why" "it could not run now." ew extensions tick
expect "put off three times in a row, status says so" "extension rec: its last tick run couldn't be made, 3 times in a row. Run: " ew status
# And a tick that was put off is tried again in half an hour, not a whole interval later.
later() { python3 -c "import os, sys, time; t = time.time() - float(sys.argv[2]) * 60; os.utime(sys.argv[1], (t, t))" "$XS/rec/tick.retry" "$1"; }
n="$(grep -c . "$REC/log")"
ew start >/dev/null 2>&1
check "a tick put off isn't tried again at the very next session start" test "$(grep -c . "$REC/log")" = "$n"
later 31
ew start >/dev/null 2>&1
check "but is after half an hour, though the interval is a day" test "$(grep -c . "$REC/log")" = "$((n + 1))"
rm "$REC/exit"
ew extensions tick >/dev/null 2>&1
lacks "after a run that works, status is quiet again" "extension rec" ew status
: > "$REC/sleep"
expect "a run past its time limit is stopped" "rec: stopped after 1 second(s)" env LLM_WIKI_EVENT_SECONDS=1 WIKIS_DIR="$EW" LLM_WIKI_EVENTS=wait "$W" extensions tick
expect "and status says so" "extension rec: its last tick run was stopped" ew status
rm "$REC/sleep"
ew extensions tick >/dev/null 2>&1
# A sync an extension makes during an event starts no event.
: > "$REC/log"
: > "$REC/sync-again"
ew extensions tick >/dev/null 2>&1
check "a sync made inside an event runs no event" test "$(grep -c . "$REC/log")" = 1
check "though the note it saved is there" test -n "$(find "$EW/edemo/raw" -name '*-nested.md')"
# For real, it runs in the background and sync doesn't wait.
: > "$REC/log"
echo "fourth" | WIKIS_DIR="$EW" "$W" capture edemo fourth >/dev/null
WIKIS_DIR="$EW" "$W" sync edemo >/dev/null 2>&1
i=0; while ! grep -q "sync edemo" "$REC/log" 2>/dev/null && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
expect "without being told to wait, sync starts it in the background" "--wiki-event sync edemo" cat "$REC/log"
i=0; while [ -d "$XS/rec/sync-edemo.running" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
expect "completion offers log and tick" "tick" "$W" __complete 2 extensions ""
check "the docs give the contract's second version" grep -q 'wiki-event' "$REPO/docs/extensions.md"
rm -rf "$XD" "$XS"
fi

if section "Content as data"; then
# A wiki's open items and pages, in a plain form a program reads, so an extension
# doesn't parse the wiki's files itself.
DW="$T/dwikis"
WIKIS_DIR="$DW" "$W" new alpha >/dev/null 2>&1
WIKIS_DIR="$DW" "$W" new beta >/dev/null 2>&1
dw() { WIKIS_DIR="$DW" "$W" "$@"; }
TB="$(printf '\t')"
lacks "with nothing open, open --data prints nothing" "." dw open --data
cat > "$DW/alpha/open.md" <<'OPEN'
# Open

## Release PROJ-1 to production
- kind: waiting
- who: Katherine Nieman
- status: open
- from: 2026-11-09 raw/a.md
- from: 2026-11-10 raw/b.md

## Look at the trial
- kind: due
- due: 2020-01-01
- status: open
- from: 2026-11-09 raw/a.md

## Shipped the thing
- kind: waiting
- who: user
- status: done 2026-11-10
- from: 2026-11-10 raw/2026-11-10-000000-jira-done.md
OPEN
printf '# Open\n\n## Beta thing\n- kind: due\n- due: 2099-01-01\n- status: open\n- from: 2026-11-09 raw/a.md\n' > "$DW/beta/open.md"
out="$(dw open --data)"
want="alpha${TB}open${TB}waiting${TB}Katherine Nieman${TB}${TB}open${TB}2026-11-09 raw/a.md; 2026-11-10 raw/b.md${TB}Release PROJ-1 to production
alpha${TB}overdue${TB}due${TB}${TB}2020-01-01${TB}open${TB}2026-11-09 raw/a.md${TB}Look at the trial
alpha${TB}done${TB}waiting${TB}user${TB}${TB}done 2026-11-10${TB}2026-11-10 raw/2026-11-10-000000-jira-done.md${TB}Shipped the thing
beta${TB}open${TB}due${TB}${TB}2099-01-01${TB}open${TB}2026-11-09 raw/a.md${TB}Beta thing"
[ "$out" = "$want" ] && ok "open --data gives every entry of every wiki, one a line, tab separated" || bad "open --data gives every entry of every wiki, one a line, tab separated" "$out"
check "open --data <wiki> gives one wiki's" test "$(dw open --data beta | wc -l | tr -d ' ')" = 1
refuse "and fails for a wiki that isn't there" dw open --data nosuch
refuse "open still takes nothing else" dw open alpha
expect "open without it is still the list for people" "Release PROJ-1 to production (waiting on Katherine Nieman)" dw open
expect "open --help names it" "open --data" dw open --help
ESC=$'\033'
case "$(LLM_WIKI_STYLE=on WIKIS_DIR="$DW" "$W" open --data)" in *"$ESC"*) bad "open --data stays plain when style is forced on" ;; *) ok "open --data stays plain when style is forced on" ;; esac
# Pages.
mkdir -p "$DW/alpha/wiki/concepts" "$DW/alpha/wiki/how-to" "$DW/alpha/wiki/.hidden"
printf -- '---\ntitle: "Quoted: a title"\nsummary: s\nupdated: 2026-11-01\nverified: 2026-11-02\n---\n\n# Ignored heading\n\nBody.\n' > "$DW/alpha/wiki/concepts/a.md"
printf '# From the *heading*\n\nBody.\n' > "$DW/alpha/wiki/concepts/b.md"
printf 'No heading here.\n\n# Too late\n' > "$DW/alpha/wiki/how-to/c d.md"
printf -- '---\ntitle: Hidden\n---\n' > "$DW/alpha/wiki/.hidden/h.md"
printf 'not markdown\n' > "$DW/alpha/wiki/concepts/notes.txt"
out="$(dw pages alpha --data | grep -v "^wiki/conventions.md")"
want="wiki/concepts/a.md${TB}2026-11-01${TB}2026-11-02${TB}Quoted: a title
wiki/concepts/b.md${TB}${TB}${TB}From the heading
wiki/how-to/c d.md${TB}${TB}${TB}c d"
[ "$out" = "$want" ] && ok "pages --data gives each page's path, dates and title: from the frontmatter, the first heading, or the file's name" || bad "pages --data gives each page's path, dates and title" "$out"
expect "pages without it is a list for people" "Quoted: a title" dw pages alpha
refuse "pages needs a wiki" dw pages
refuse "that is there" dw pages nosuch --data
expect "and says how to see which wikis there are" "status lists the wikis here." dw pages nosuch --data
expect "a wiki with no pages says so to a person" "No pages yet." dw pages beta
lacks "and nothing to a program" "." dw pages beta --data
expect "open --data with no collection says how to make one" "Run: " env WIKIS_DIR="$T/nowikis" "$W" open --data
refuse "and refuses an option it doesn't know" dw pages alpha --json
case "$(LLM_WIKI_STYLE=on WIKIS_DIR="$DW" "$W" pages alpha --data)" in *"$ESC"*) bad "pages --data stays plain when style is forced on" ;; *) ok "pages --data stays plain when style is forced on" ;; esac
expect "the usage names pages" "pages <wiki> [--data]" "$W" --help
expect "completion offers pages" "pages" "$W" __complete 1 pa
expect "and its flag" "--data" "$W" __complete 3 pages alpha ""
expect "and open's" "--data" "$W" __complete 2 open ""
# The extensions read these, and no longer the wiki's files.
lacks "the Jira extension doesn't open open.md itself" 'open(os.path.join(root, "open.md")' cat "$REPO/extensions/wiki-jira"
lacks "nor the Confluence extension walk wiki/" "os.walk" cat "$REPO/extensions/wiki-confluence"
expect "run without llm-wiki, jira says how to run it" "Run this as: wiki jira" env -u LLM_WIKI WIKIS_DIR="$DW" JIRA_URL=http://127.0.0.1:1 JIRA_API_TOKEN=x "$REPO/extensions/wiki-jira" check
check "the docs say how an extension reads a wiki" grep -q 'open --data' "$REPO/docs/extensions.md"
fi

if section "A folder of clones"; then
# Some people start a session in a folder for a ticket, which is not a repository and
# holds clones of the repositories the ticket touches. The wikis of those clones are the
# session's, and it says so: nothing is guessed silently.
TF="$T/tickets/INFRA-17937"
mkdir -p "$TF/docs"
for r in tfalpha tfbeta tfgamma; do git init -q "$TF/$r"; done
"$W" new tfalpha >/dev/null 2>&1
"$W" new tfbeta >/dev/null 2>&1
out="$(cd "$TF" && "$W" start 2>&1)"
[ "$(printf '%s\n' "$out" | head -n 1)" = "wiki: $WIKIS_DIR/tfalpha" ] && ok "started in a folder of clones, the first clone's wiki is the session's" || bad "started in a folder of clones, the first clone's wiki is the session's" "$out"
case "$out" in *"This folder isn't a git repository. It holds clones of tfalpha and tfbeta, so their wikis are this session's"*) ok "and start says why, naming the clones" ;; *) bad "and start says why, naming the clones" "$out" ;; esac
case "$out" in *"Tell the user, in one line, which wikis you are using and why, and that they can say so if that is wrong."*) ok "and has the agent tell the user, and how to say it is wrong" ;; *) bad "and has the agent tell the user, and how to say it is wrong" "$out" ;; esac
case "$out" in *"===== $WIKIS_DIR/tfalpha/index.md"*"===== $WIKIS_DIR/tfbeta/index.md (also in this folder)"*) ok "the other clone's index is printed too" ;; *) bad "the other clone's index is printed too" "$out" ;; esac
case "$out" in *"tfgamma has no wiki yet"*"new tfgamma"*) ok "a clone with no wiki is named, with how to make one" ;; *) bad "a clone with no wiki is named, with how to make one" "$out" ;; esac
case "$out" in *"$WIKIS_DIR/tfbeta: nothing waiting"*) ok "and what waits to be compiled covers every wiki in use" ;; *) bad "and what waits to be compiled covers every wiki in use" "$out" ;; esac
out="$(cd "$TF/tfalpha" && "$W" start 2>&1)"
case "$out" in "wiki: $WIKIS_DIR/tfalpha, for the repository tfalpha"*) ok "started inside one of the clones, it is that repository's wiki, as before" ;; *) bad "started inside one of the clones, it is that repository's wiki, as before" "$out" ;; esac
case "$out" in *"isn't a git repository"*) bad "with nothing said about folders" "$out" ;; *) ok "with nothing said about folders" ;; esac
mkdir -p "$T/tickets/EMPTY/notes"
out="$(cd "$T/tickets/EMPTY" && "$W" start 2>&1)"
case "$out" in "wiki: $WIKIS_DIR/global"*"This folder isn't a git repository, and holds none, so the shared wiki is this session's. Tell the user so in one line, and ask whether they want llm-wiki used for this work, and if so which wiki it belongs to."*) ok "a folder with no repository in it gets the shared wiki, says so, and has the agent ask" ;; *) bad "a folder with no repository in it gets the shared wiki, says so, and has the agent ask" "$out" ;; esac
mkdir -p "$T/tickets/NOWIKI"
git init -q "$T/tickets/NOWIKI/tfgamma"
out="$(cd "$T/tickets/NOWIKI" && "$W" start 2>&1)"
case "$out" in "wiki: $WIKIS_DIR/global"*"It holds a clone of tfgamma, which has no wiki yet, so the shared wiki is this session's."*) ok "clones that have no wikis yet are named, and the shared wiki is used" ;; *) bad "clones that have no wikis yet are named, and the shared wiki is used" "$out" ;; esac
# One clone, two clones without a wiki, and two clones of one wiki read as a person would say them.
mkdir -p "$T/tickets/ONE" "$T/tickets/LACK2"
git init -q "$T/tickets/ONE/tfalpha"
out="$(cd "$T/tickets/ONE" && "$W" start 2>&1)"
case "$out" in *"It holds a clone of tfalpha, so its wiki is this session's: tfalpha."*) ok "one clone is said in the singular" ;; *) bad "one clone is said in the singular" "$out" ;; esac
for r in tfalpha tfgamma tfomega; do git init -q "$T/tickets/LACK2/$r"; done
out="$(cd "$T/tickets/LACK2" && "$W" start 2>&1)"
case "$out" in *"tfgamma and tfomega have no wikis yet: create one with"*) ok "two clones with no wiki have none, not has" ;; *) bad "two clones with no wiki have none, not has" "$out" ;; esac
case "$out" in *"That is "*) bad "and no one command is offered for two" "$out" ;; *) ok "and no one command is offered for two" ;; esac
out="$(env -C "$HOME" "$W" workflows check "$HOME" 2>&1)"
case "$out" in "~ is not a folder a session is placed in"*) ok "workflows check writes the home folder as ~" ;; *) bad "workflows check writes the home folder as ~" "$out" ;; esac
# A session that was compacted or resumed is told not to ask a second time.
for src in compact resume; do
  out="$(hook "$TF" "{\"source\":\"$src\"}")"
  case "$out" in *"No pattern of theirs covers this folder yet."*"if you asked already, don't ask again."*) ok "after a $src the hook says not to ask again" ;; *) bad "after a $src the hook says not to ask again" "$out" ;; esac
done
lacks "and a new session is not told that" "if you asked already" hook "$TF" '{"source":"startup"}'
# Two clones one wiki covers count once, and more than three wikis are named, not all printed.
"$W" cover tfalpha tfdelta >/dev/null 2>&1
git init -q "$TF/tfdelta"
out="$(cd "$TF" && "$W" start 2>&1)"
case "$out" in *"so their wikis are this session's: tfalpha and tfbeta."*) ok "and the sentence still names each wiki once" ;; *) bad "and the sentence still names each wiki once" "$out" ;; esac
check "two clones that one wiki covers load it once" test "$(printf '%s\n' "$out" | grep -c "^===== $WIKIS_DIR/tfalpha/index.md")" = 1
for r in tfc1 tfc2 tfc3; do "$W" new "$r" >/dev/null 2>&1; git init -q "$TF/$r"; done
out="$(cd "$TF" && "$W" start 2>&1)"
check "at most three wikis are printed in full" test "$(printf '%s\n' "$out" | grep -c "^===== .*index.md" | tr -d ' ')" -le 4
case "$out" in *"Also in this folder, and not printed here: tfc2 and tfc3."*) ok "and the rest are named, with how to read one" ;; *) bad "and the rest are named, with how to read one" "$out" ;; esac
# The Claude Code session hook says the same.
out="$(hook "$T/tickets/EMPTY" '{"source":"startup"}')"
case "$out" in *"isn't a git repository, and holds none"*"ask whether they want llm-wiki used for this work"*) ok "the session hook says a folder couldn't be placed, and has the agent ask" ;; *) bad "the session hook says a folder couldn't be placed, and has the agent ask" "$out" ;; esac
out="$(hook "$T/tickets/NOWIKI" '{"source":"startup"}')"
case "$out" in *"It holds a clone of tfgamma, which has no wiki yet"*) ok "and names clones that have no wikis" ;; *) bad "and names clones that have no wikis" "$out" ;; esac
# Clones with no wikis yet: the layout is known, so the question is about using their
# wikis as they get them, and a yes is kept as "inside". A no can be kept too.
case "$out" in *"Ask once whether folders like this one should use the wikis of the repositories inside, as those get wikis."*"workflows add '"*"/tickets/NOWIKI' inside"*"workflows add '"*"/tickets/NOWIKI' none"*) ok "and has the agent ask once, with inside and none to record" ;; *) bad "and has the agent ask once, with inside and none to record" "$out" ;; esac
case "$out" in *"ask how the folder is laid out"*) bad "and doesn't ask how a folder of clones is laid out" "$out" ;; *) ok "and doesn't ask how a folder of clones is laid out" ;; esac
mkdir -p "$HOME/jobs/INFRA-400"
git init -q "$HOME/jobs/INFRA-400/tfgamma"; git init -q "$HOME/jobs/INFRA-400/tfomega"
out="$("$W" workflows check "$HOME/jobs/INFRA-400" 2>&1)"
case "$out" in *"clones of tfgamma and tfomega, which have no wikis yet"*"record it: \`"*"workflows add '~/jobs/*-[0-9]*' inside\`. If only this folder does: \`"*"workflows add '~/jobs/INFRA-400' inside\`."*"workflows add '~/jobs/*-[0-9]*' none"*) ok "a ticket folder of clones with no wikis is offered the wildcard, inside first" ;; *) bad "a ticket folder of clones with no wikis is offered the wildcard, inside first" "$out" ;; esac
# shellcheck disable=SC2088
"$W" workflows add '~/jobs/*-[0-9]*' inside >/dev/null 2>&1
expect "and once that is recorded, a session there recognises it and asks nothing" "says the wikis of the repositories inside, but it holds no clone that has a wiki" "$W" workflows check "$HOME/jobs/INFRA-400"
lacks "with no question left" "Ask once" "$W" workflows check "$HOME/jobs/INFRA-400"
# shellcheck disable=SC2088
"$W" workflows remove '~/jobs/*-[0-9]*' >/dev/null 2>&1
out="$(hook "$T/tickets/EMPTY" '{"source":"startup"}')"
case "$out" in *"ask how the folder is laid out"*"/tickets/EMPTY' none"*) ok "a folder with nothing in it is still asked how it is laid out" ;; *) bad "a folder with nothing in it is still asked how it is laid out" "$out" ;; esac
out="$(hook "$TF" '{"source":"startup"}')"
case "$out" in *"knowledge wiki is "*"/tfalpha"*"It holds clones of"*"so their wikis are this session's"*) ok "and in a folder of clones, the hook gives the first clone's wiki and names the others" ;; *) bad "and in a folder of clones, the hook gives the first clone's wiki and names the others" "$out" ;; esac
lacks "the hook no longer falls back without saying why" "isn't in a repository, so the shared wiki is its wiki" hook "$TF" '{"source":"startup"}'
# The home folder is where a hook lands with no folder to go on. The MCP server's
# checks cover the temporary folder it runs from.
mkdir -p "$HOME/somerepo" && git init -q "$HOME/somerepo"
out="$(env -C "$HOME" "$W" start 2>&1)"
case "$out" in *"isn't a git repository"*) bad "nothing is read into what the home folder holds" "$out" ;; *"Not in a repository, so the shared wiki is this session's."*) ok "nothing is read into what the home folder holds" ;; *) bad "nothing is read into what the home folder holds" "$out" ;; esac
rm -rf "$HOME/somerepo"
rm -rf "$T/tickets"
fi

# The patterns below are written with a ~ on purpose: it is kept as typed.
# shellcheck disable=SC2088
if section "Patterns for where a session is"; then
# What a person says about a kind of folder is kept as a line in the shared wiki's
# workflows.md, so the question is asked once. Session start reads it.
PF="$HOME/repos"
WFILE="$WIKIS_DIR/global/workflows.md"
mkdir -p "$PF/INFRA-100/notes" "$PF/INFRA-200" "$PF/scratch" "$PF/other" "$HOME/notesdir"
"$W" new pfalpha >/dev/null 2>&1
"$W" new pfbeta >/dev/null 2>&1
for r in pfalpha pfbeta; do git init -q "$PF/INFRA-100/$r"; git init -q "$PF/INFRA-200/$r"; done
expect "with no patterns, workflows says so and how to add one" "No patterns yet" "$W" workflows
out="$(env -C "$PF/INFRA-100" "$W" start 2>&1)"
case "$out" in *"No pattern of theirs covers this folder yet. Ask once whether folders like this one always work this way."*"workflows add '~/repos/*-[0-9]*' inside"*) ok "a good guess with no pattern has the agent ask once, with a pattern to record" ;; *) bad "a good guess with no pattern has the agent ask once, with a pattern to record" "$out" ;; esac
out="$(env -C "$PF/other" "$W" start 2>&1)"
case "$out" in *"No pattern of theirs covers this folder yet. If they want llm-wiki here, ask how the folder is laid out and whether to remember it"*"workflows add '~/repos/other' none"*) ok "no guess and no pattern has the agent ask about the layout, and offers to remember a no" ;; *) bad "no guess and no pattern has the agent ask about the layout, and offers to remember a no" "$out" ;; esac
out="$("$W" workflows add '~/repos/*-[0-9]*' inside 2>&1)"
case "$out" in "added: in \`~/repos/*-[0-9]*\`: the wikis of the repositories inside."*) ok "workflows add records a pattern" ;; *) bad "workflows add records a pattern" "$out" ;; esac
check "as one line of a fixed shape in the shared wiki's workflows.md" grep -qxF -- '- in `~/repos/*-[0-9]*`: the wikis of the repositories inside.' "$WFILE"
expect "and workflows lists it" 'in `~/repos/*-[0-9]*`: the wikis of the repositories inside.' "$W" workflows
out="$(env -C "$PF/INFRA-200" "$W" start 2>&1)"
[ "$(printf '%s\n' "$out" | head -n 1)" = "wiki: $WIKIS_DIR/pfalpha" ] && ok "another folder of that kind gets the wikis of its clones" || bad "another folder of that kind gets the wikis of its clones" "$out"
case "$out" in *'This folder matches your pattern `~/repos/*-[0-9]*`'*"Tell the user in one line that you recognised the pattern and which wikis you are using, and that they can say so if it is wrong."*) ok "and the session says which pattern it recognised, and how to say it is wrong" ;; *) bad "and the session says which pattern it recognised, and how to say it is wrong" "$out" ;; esac
case "$out" in *"Ask once"*|*"No pattern of theirs"*) bad "and nothing is asked again" "$out" ;; *) ok "and nothing is asked again" ;; esac
case "$out" in *"===== $WIKIS_DIR/pfbeta/index.md (also in this folder)"*) ok "and the other clone's index is printed" ;; *) bad "and the other clone's index is printed" "$out" ;; esac
out="$(env -C "$PF/INFRA-100/notes" "$W" start 2>&1)"
case "$out" in *"matches your pattern"*) bad "a * stops at a slash, so a folder inside one is not matched" "$out" ;; *) ok "a * stops at a slash, so a folder inside one is not matched" ;; esac
# A named wiki, and no wiki.
"$W" workflows add '~/notesdir' pfbeta >/dev/null 2>&1
out="$(env -C "$HOME/notesdir" "$W" start 2>&1)"
case "$out" in "wiki: $WIKIS_DIR/pfbeta"*'matches your pattern `~/notesdir`'*"which names the wiki pfbeta"*) ok "a pattern can name one wiki" ;; *) bad "a pattern can name one wiki" "$out" ;; esac
"$W" workflows add '~/repos/scratch' none >/dev/null 2>&1
out="$(env -C "$PF/scratch" "$W" start 2>&1)"
[ "$(printf '%s\n' "$out" | head -n 1)" = "wiki: none" ] && ok "a pattern can say no wiki, and start names none" || bad "a pattern can say no wiki, and start names none" "$out"
case "$out" in *"llm-wiki isn't used in this session"*"Tell the user so in one line, and that they can say so if it is wrong."*) ok "and says llm-wiki isn't used, and to tell the user" ;; *) bad "and says llm-wiki isn't used, and to tell the user" "$out" ;; esac
case "$out" in *"====="*) bad "and prints no index" "$out" ;; *) ok "and prints no index" ;; esac
# A path with no wildcard goes before the patterns, since the first match wins.
"$W" workflows add '~/repos/INFRA-200' pfbeta >/dev/null 2>&1
out="$(env -C "$PF/INFRA-200" "$W" start 2>&1)"
case "$out" in "wiki: $WIKIS_DIR/pfbeta"*) ok "one folder's own line wins over a pattern that also fits" ;; *) bad "one folder's own line wins over a pattern that also fits" "$out" ;; esac
# Adding the same pattern again changes its line.
out="$("$W" workflows add '~/repos/INFRA-200' none 2>&1)"
case "$out" in "changed: in \`~/repos/INFRA-200\`: no wiki."*) ok "adding a pattern that is there changes it" ;; *) bad "adding a pattern that is there changes it" "$out" ;; esac
check "and leaves one line for it" test "$(grep -c 'INFRA-200' "$WFILE")" = 1
out="$("$W" workflows remove '~/repos/INFRA-200' 2>&1)"
case "$out" in "removed: in \`~/repos/INFRA-200\`"*) ok "workflows remove takes a pattern out" ;; *) bad "workflows remove takes a pattern out" "$out" ;; esac
check "and the line is gone" test "$(grep -c 'INFRA-200' "$WFILE")" = 0
"$W" workflows remove '~/nowhere' >/dev/null 2>&1; rc=$?
check "removing a pattern that isn't there fails" test "$rc" = 1
# Calling it wrongly.
"$W" workflows add 'repos/*' inside >/dev/null 2>&1; rc=$?
check "a pattern that isn't a full path is a usage error" test "$rc" = 2
"$W" workflows add '~/x' >/dev/null 2>&1; rc=$?
check "and so is a pattern with nothing to do" test "$rc" = 2
"$W" workflows add '~/x' nosuchwiki >/dev/null 2>&1; rc=$?
check "a pattern can't name a wiki that doesn't exist" test "$rc" = 1
expect "and the message says so" "there is no wiki nosuchwiki" "$W" workflows add '~/x' nosuchwiki
# That message sends the reader to list, which names the wikis and what each covers.
check "the command that message names exists" "$W" list
out="$("$W" list 2>&1)"
case "$out" in *"tfalpha"*"covers: tfdelta"*) ok "list names a wiki and the repositories it covers" ;; *) bad "list names a wiki and the repositories it covers" "$out" ;; esac
check "and a wiki that covers only itself is a bare name" sh -c 'printf "%s\n" "$1" | grep -qx tfbeta' _ "$out"
out="$("$W" list --names 2>&1)"
check "list --names prints one name a line and nothing else" test "$out" = "$(for d in "$WIKIS_DIR"/*/; do [ -f "$d/AGENTS.md" ] && [ -f "$d/index.md" ] && basename "$d"; done)"
"$W" list --bogus >/dev/null 2>&1; rc=$?
check "list with an option it doesn't know is a usage error" test "$rc" = 2
expect "list completes as a command" "list" "$W" __complete 1 li
expect "and so does workflows" "workflows" "$W" __complete 1 wo
check "an empty collection lists nothing with --names" test -z "$(WIKIS_DIR="$T/nowikis" "$W" list --names 2>&1)"
# A ticket folder with words after its number is one of its siblings too.
mkdir -p "$HOME/work/INFRA-300-fix-dns"
git init -q "$HOME/work/INFRA-300-fix-dns/tfalpha"
expect "a ticket folder named with words after the number is offered the wildcard" "workflows add '~/work/*-[0-9]*' inside" "$W" workflows check "$HOME/work/INFRA-300-fix-dns"
# A wiki that was removed after its pattern was written.
printf -- '- in `~/gone`: `vanished`.\n' >> "$WFILE"
mkdir -p "$HOME/gone"
out="$(env -C "$HOME/gone" "$W" start 2>&1)"
case "$out" in "wiki: $WIKIS_DIR/global"*"names the wiki vanished, and there is no such wiki"*) ok "a pattern naming a wiki that is gone falls back to the shared wiki, and says so" ;; *) bad "a pattern naming a wiki that is gone falls back to the shared wiki, and says so" "$out" ;; esac
expect "workflows check says what a session in a folder would be told" 'matches your pattern `~/repos/*-[0-9]*`' "$W" workflows check "$PF/INFRA-100"
# The Claude Code session hook follows the same patterns.
out="$(hook "$PF/INFRA-100" '{"source":"startup"}')"
case "$out" in *"knowledge wiki is "*"/pfalpha"*'matches your pattern `~/repos/*-[0-9]*`'*) ok "the session hook uses the pattern, and names it" ;; *) bad "the session hook uses the pattern, and names it" "$out" ;; esac
out="$(hook "$PF/scratch" '{"source":"startup"}')"
case "$out" in *"llm-wiki isn't used in this session"*) ok "and for a no-wiki pattern the hook says llm-wiki isn't used" ;; *) bad "and for a no-wiki pattern the hook says llm-wiki isn't used" "$out" ;; esac
case "$out" in *"knowledge wiki is"*|*"AGENTS.md"*) bad "and names no wiki and no handbook" "$out" ;; *) ok "and names no wiki and no handbook" ;; esac
lacks "lint has no finding for the shared wiki's workflows.md" "workflows.md" "$W" lint global
check "the workflows rule ships in the template" grep -q 'workflows add' "$REPO/template/rules/workflows.md"
check "and AGENTS.md points to it" grep -q 'rules/workflows.md' "$REPO/template/AGENTS.md"
rm -rf "$PF" "$HOME/notesdir" "$HOME/gone" "$WFILE"
fi

if section "Tour"; then
TH="$T/tour-home"
TD="$TH/tmp/llm-wiki-tour"
mkdir -p "$TH/tmp"
# shellcheck disable=SC2120
tour() { env -u WIKIS_DIR -u XDG_CONFIG_HOME -u XDG_STATE_HOME HOME="$TH" TMPDIR="$TH/tmp" "$W" tour "$@"; }
tour_again() { tour >/dev/null && find "$TD/wikis/harbor-api/raw" -name '*tour-note*' | grep -q .; }
tw() { env -u WIKIS_DIR "$TD/wiki" "$@"; }
out="$(tour)"
case "$out" in *"# The llm-wiki tour"*"$TD/wiki"*) ok "the tour prints its guide, naming the sandbox's command" ;; *) bad "the tour prints its guide, naming the sandbox's command" "$out" ;; esac
case "$out" in *"@DIR@"* | *"@W@"* | *"@REAL@"*) bad "and fills in every placeholder" "$out" ;; *) ok "and fills in every placeholder" ;; esac
check "the guide's sandbox has the code" test -f "$TD/code/harbor-api/delivery/retry.go"
expect "the sandbox's start finds the project" "Webhook retries" tw start harbor-api
n="$(tw pending harbor-api | grep -c '^raw/')"
if [ "$n" = 2 ]; then ok "two notes wait to be compiled"; else bad "two notes wait to be compiled ($n)"; fi
expect "the planted page is stale" "webhook-retries.md" tw stale
expect "lint finds the planted broken link" "on-call.md" tw lint harbor-api
lacks "and no orphan pages" "orphan" tw lint harbor-api
lacks "fixture placeholders are filled in" "@TODAY@\|@COMMIT@" grep -r '@TODAY@\|@COMMIT@' "$TD/wikis/harbor-api/wiki"
c="$(sed -n 's/^commit: //p' "$TD/wikis/harbor-api/wiki/concepts/webhook-retries.md")"
expect "the page's commit is from before the code changed" "maxAttempts = 6" git -C "$TD/code/harbor-api" show "$c:delivery/retry.go"
expect "the code now disagrees with the page" "maxAttempts = 8" cat "$TD/code/harbor-api/delivery/retry.go"
expect "a peer wiki holds what the page cites" "delivery.succeeded" cat "$TD/wikis/billing/wiki/concepts/invoice-events.md"
expect "the shared wiki turns up in a search" "Run Postgres locally" tw find postgres
expect "standup sees the sandbox's commits" "Raise the retry cap" tw standup --since today
expect "the planted pattern isn't ready before the compile" "0 ready" tw patterns
TP="$TD/wikis/harbor-api/patterns.md"
cp "$TP" "$T/tour-patterns"
echo "- seen: 2026-01-20 harbor-api raw/2026-01-20-153000-rate-limit-decision.md" >> "$TP"
expect "and the compile's sighting makes it ready, as the guide says" "READY" tw patterns
cp "$T/tour-patterns" "$TP"
case "$out" in *"Your coding agent forgets everything"*"1. A new session already knows why"*) ok "the guide opens with what llm-wiki is for, and what you get" ;; *) bad "the guide opens with what llm-wiki is for, and what you get" "$out" ;; esac
check "a capture works" tw capture harbor-api tour-note --file "$TD/code/harbor-api/README.md"
n="$(find "$TD/wikis/harbor-api/raw" -name '*tour-note*' -exec basename {} \;)"
tw log harbor-api ingest "Tour note" --source "raw/$n" >/dev/null
n="$(tw pending harbor-api | grep -c '^raw/')"
if [ "$n" = 2 ]; then ok "compiling one note leaves the planted ones waiting, as chapter 2 needs"; else bad "compiling one note leaves the planted ones waiting, as chapter 2 needs ($n)"; fi
expect "and a sync commits it, with no remote" "no remote" tw sync harbor-api -m "harbor-api: tour"
check "nothing is left uncommitted in the sandbox" test -z "$(git -C "$TD/wikis" status --porcelain)"
check "nothing lands in the home folder" test -z "$(find "$TH" -type f ! -path "$TD/*")"
mkdir -p "$TH/wikis" && cp -R "$TD/wikis/billing" "$TH/wikis/real-one"
expect "a real collection is there to find" "real-one" env -u WIKIS_DIR -u XDG_CONFIG_HOME -u XDG_STATE_HOME HOME="$TH" "$W" status
lacks "the sandbox's status doesn't see it" "real-one\|also:" tw status
lacks "and --collection can't reach it" "real-one" tw status --collection default
rm -rf "$TH/wikis"
check "a repeat keeps the sandbox, so a tour can pick up later" tour_again
mkdir -p "$T/not-a-tour" && echo keep > "$T/not-a-tour/keep"
expect "clean refuses a folder that isn't a sandbox" "isn't a tour's sandbox" tour --dir "$T/not-a-tour" --clean
expect "and the tour won't build in one" "already holds other files" tour --dir "$T/not-a-tour"
check "so it's still there" test -f "$T/not-a-tour/keep"
expect "--dir needs a folder" "--dir needs a value" tour --dir
expect "tour completes its options" "--clean" "$W" __complete 2 tour ""
expect "clean removes the sandbox" "Removed" tour --clean
check "and it's gone" test ! -e "$TD"
expect "clean with no sandbox says so" "No tour sandbox" tour --clean
expect "unknown options are refused" "tour options" tour --nope
fi

if section "The released helper"; then
# This section is about the helper itself, so it runs with the helper allowed
# even when the whole suite was started with LLM_WIKI_NO_GO=1.
unset LLM_WIKI_NO_GO
HSRC="$(sed -n 's/^source //p' "$REPO/helper.lock")"
HDIR="$HOME/.local/share/llm-wiki/helper"
sha() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d ' ' -f 1; else sha256sum "$1" | cut -d ' ' -f 1; fi; }
check "helper.lock is in step with the helper's source (if not: scripts/helper.sh lock)" test "$("$REPO/scripts/helper.sh" hash)" = "$HSRC"
# The repository as a release holds it: tracked and new files, and no bin/, so no
# helper built in the checkout stands in the way.
HR="$T/hrepo"
mkdir -p "$HR"
(cd "$REPO" && git ls-files -co --exclude-standard -z | tar --null -T - -cf - 2>/dev/null) | tar -xf - -C "$HR"
HW="$HR/wiki.sh"
HPLAT="$("$HW" helper | sed -n 's/.* for \([a-z0-9-]*\)\.$/\1/p')"
check "wiki.sh names this machine's platform" test -n "$HPLAT"
expect "with no helper anywhere, it says how to get one" "helper: none" "$HW" helper
out="$("$HW" helper)"
case "$out" in *"(report, standup)"*) bad "and doesn't list which commands are ported, a list that goes stale" "$out" ;; *) ok "and doesn't list which commands are ported, a list that goes stale" ;; esac
out="$("$HW" helper fetch 2>&1)" && bad "fetch fails when the release isn't published" "$out" || case "$out" in *"couldn't be downloaded"*) ok "fetch fails when the release isn't published" ;; *) bad "fetch fails when the release isn't published" "$out" ;; esac
check "and installs nothing" test ! -e "$HDIR/$HSRC/llm-wiki"
if command -v go >/dev/null 2>&1 && [ -n "$HPLAT" ]; then
  REL="$T/release/helper-$HSRC"
  check "the release build for this platform builds" "$REPO/scripts/helper.sh" build "$REL" "$HPLAT"
  check "and is byte for byte the one helper.lock names" test "$(sha "$REL/llm-wiki-$HPLAT")" = "$(sed -n "s/^$HPLAT //p" "$REPO/helper.lock")"
  expect "fetch installs a release that matches the lock" "helper $HSRC installed for $HPLAT" "$HW" helper fetch
  expect "and wiki.sh uses it" "helper: release $HSRC" "$HW" helper
  expect "setup --list shows it" "release $HSRC" "$HW" setup --list
  expect "a second fetch has nothing to do" "is already here" "$HW" helper fetch
  expect "LLM_WIKI_NO_GO still turns it off" "helper: off" env LLM_WIKI_NO_GO=1 "$HW" helper
  rm -f "$HDIR/$HSRC/llm-wiki"
  cp "$REL/llm-wiki-$HPLAT" "$T/release-good"
  printf 'tampered' >> "$REL/llm-wiki-$HPLAT"
  out="$("$HW" helper fetch 2>&1)" && bad "a download that doesn't match the lock is refused" "$out" || case "$out" in *"doesn't match helper.lock"*) ok "a download that doesn't match the lock is refused" ;; *) bad "a download that doesn't match the lock is refused" "$out" ;; esac
  check "and thrown away" test ! -e "$HDIR/$HSRC/llm-wiki"
  check "leaving no partial file" test -z "$(find "$HDIR/$HSRC" -name '.download*' 2>/dev/null)"
  # An older release that speaks the protocol is better than none.
  mkdir -p "$HDIR/0000older"
  cp "$T/release-good" "$HDIR/0000older/llm-wiki"
  expect "an older release that speaks the protocol is used meanwhile" "an older release that still speaks protocol" "$HW" helper
  printf '#!/bin/sh\necho 0\n' > "$HDIR/0000older/llm-wiki"
  expect "but not one that speaks another" "helper: none" "$HW" helper
  cp "$T/release-good" "$REL/llm-wiki-$HPLAT"
  out="$("$HW" update --wikis-only 2>&1)"
  case "$out" in *"== Helper"*"- helper $HSRC installed for $HPLAT"*) ok "wiki update fetches the helper for its version" ;; *) bad "wiki update fetches the helper for its version" "$out" ;; esac
  expect "and then uses it" "helper: release $HSRC" "$HW" helper
  rm -f "$REL/llm-wiki-$HPLAT" "$HDIR/$HSRC/llm-wiki"
  out="$("$HW" update --wikis-only 2>&1)"
  case "$out" in *"== Helper"*"couldn't be downloaded"*"Nothing is lost"*) ok "an update that can't fetch says so and carries on" ;; *) bad "an update that can't fetch says so and carries on" "$out" ;; esac
  # Session start fetches a missing helper by itself, in the background.
  hwait() { local i=0; while [ "$i" -lt 100 ]; do [ -x "$HDIR/$HSRC/llm-wiki" ] && return 0; sleep 0.1; i=$((i + 1)); done; return 1; }
  hgone() { rm -f "$HDIR/$HSRC/llm-wiki"; [ -z "${1:-}" ] || rm -f "$HDIR/$HSRC/.tried"; }
  hhook() { printf '%s' '{"source":"startup"}' | CLAUDE_PLUGIN_ROOT="$HR" CLAUDE_PLUGIN_DATA="$T/hdata" CLAUDE_PROJECT_DIR="$T/projects/web" bash "$HR/hooks/session-start.sh"; }
  cp "$T/release-good" "$REL/llm-wiki-$HPLAT"
  hgone again
  expect "fetching at session start is on unless turned off" "Fetched automatically at session start: on" "$HW" helper
  "$HW" __helper-auto
  check "session start fetches a missing helper in the background" hwait
  expect "and wiki.sh then uses it" "helper: release $HSRC" "$HW" helper
  hgone
  "$HW" __helper-auto
  sleep 1
  check "it tries once in six hours, not at every session" test ! -e "$HDIR/$HSRC/llm-wiki"
  touch -t 202001010000 "$HDIR/$HSRC/.tried"
  "$HW" __helper-auto
  check "and tries again after that" hwait
  hgone again
  hhook >/dev/null
  check "the session hook starts the fetch" hwait
  hgone again
  LLM_WIKI_BACKGROUND=1 hhook >/dev/null
  sleep 1
  check "a background compile's own session fetches nothing" test ! -e "$HDIR/$HSRC/llm-wiki"
  "$HW" start web >/dev/null 2>&1
  check "wiki start fetches too, for agents with no hook" hwait
  hgone again
  expect "helper auto off turns it off" "helper auto: off" "$HW" helper auto off
  "$HW" __helper-auto
  sleep 1
  check "off, session start fetches nothing" test ! -e "$HDIR/$HSRC/llm-wiki"
  expect "and wiki helper fetch still works" "helper $HSRC installed" "$HW" helper fetch
  expect "helper auto on turns it back on" "helper auto: on" "$HW" helper auto on
  refuse "helper auto needs on or off" "$HW" helper auto maybe
  expect "setup --list marks the question as new" "fetched at session start: on  <- new" "$HW" setup --list
  out="$(printf 'n\n' | in_tty "$HW" setup helper 2>&1)"
  case "$out" in *"Fetch it automatically at session start?"*"helper auto: off"*) ok "setup helper asks, and a no turns it off" ;; *) bad "setup helper asks, and a no turns it off" "$out" ;; esac
  lacks "and the question isn't new any more" "<- new" bash -c "'$HW' setup --list | grep '^helper'"
  "$HW" helper auto on >/dev/null
  # A file that isn't the release's bytes is a broken download.
  hwhole() { local i=0; while [ "$i" -lt 100 ]; do [ "$(sha "$HDIR/$HSRC/llm-wiki" 2>/dev/null)" = "$(sha "$T/release-good")" ] && return 0; sleep 0.1; i=$((i + 1)); done; return 1; }
  hgone again
  printf '#!/bin/sh\nexit 1\n' > "$HDIR/$HSRC/llm-wiki"
  chmod +x "$HDIR/$HSRC/llm-wiki"
  "$HW" __helper-auto
  check "session start replaces a helper that is there but broken" hwhole
  rm -f "$HDIR/$HSRC/.tried"
  "$HW" __helper-auto
  check "and leaves a whole one alone" test ! -e "$HDIR/$HSRC/.tried"
else
  skipped "fetching and verifying a release (go isn't installed)"
fi
fi

section_time "${section_name:-}"
printf '\n%d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ]
