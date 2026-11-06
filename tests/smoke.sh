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
2 | What moved to llm-relay |
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
# build_helper: the compiled helper, in $T/bin/llm-wiki, and two stand-ins for a helper
# gone wrong: one built for another protocol, and one that fails.
build_helper() {
  (cd "$REPO" && go build -o "$T/bin/llm-wiki" ./cmd/llm-wiki) || return 1
  printf '#!/bin/sh\n[ "$1" = protocol ] && { echo 0; exit 0; }\necho "STALE TABLE"\n' > "$T/bin/stale-helper"
  printf '#!/bin/sh\n[ "$1" = protocol ] && { sed -n "s/^GO_PROTOCOL=//p" "%s"; exit 0; }\nexit 1\n' "$W" > "$T/bin/broken-helper"
  chmod +x "$T/bin/stale-helper" "$T/bin/broken-helper"
}

if section "Collection"; then
expect "init --git makes the first commit" "first commit made" "$W" init --git
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
for f in .gitattributes .gitignore patterns.md links.md repos.md rules/peers.md rules/compile.md; do
  check "demo has $f" test -f "$WIKIS_DIR/demo/$f"
done
expect "index.md merges by union" "merge: union" git -C "$WIKIS_DIR" check-attr merge -- demo/index.md
expect "log.md merges by union" "merge: union" git -C "$WIKIS_DIR" check-attr merge -- demo/log.md
check "delegation.md is git-ignored" git -C "$WIKIS_DIR" check-ignore -q delegation.md
check "the secret-scan hook is installed" grep -q "llm-wiki secret scan" "$WIKIS_DIR/.git/hooks/pre-commit"
fi

if section "Upgrade"; then
set_version "$WIKIS_DIR/demo/AGENTS.md" 12
rm -f "$WIKIS_DIR/demo/patterns.md" "$WIKIS_DIR/demo/.gitattributes"
out="$("$W" upgrade demo 2>&1)"
case "$out" in *"handbook: v12 -> v$TV"*) ok "upgrade moves the handbook to v$TV" ;; *) bad "upgrade moves the handbook to v$TV" "$out" ;; esac
case "$out" in *"What's new since v12"*) ok "upgrade prints the changelog" ;; *) bad "upgrade prints the changelog" "$out" ;; esac
check "upgrade restores patterns.md" test -f "$WIKIS_DIR/demo/patterns.md"
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
case "$out" in *"Wiki reads are about 5"[0-9].[0-9]"% of new input"*) ok "tokens: wiki reads are estimated against new input" ;; *) bad "tokens: wiki reads are estimated against new input" "$out" ;; esac
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
case "$out" in *"## Tokens (Gemini in Antigravity)"*"| demo | 1 | 2k | 20k | 400 |"*"don't add to Claude's"*) ok "report adds a separate Gemini token table, by project" ;; *) bad "report adds a separate Gemini token table, by project" "$out" ;; esac
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
[ -z "\${FAKE_FAIL:-}" ] || exit 3
for f in \$("$W" pending "\$LLM_WIKI_COMPILE_WIKI" | sed -n 's/^\(raw\/[^ ]*\).*/\1/p'); do
  "$W" log "\$LLM_WIKI_COMPILE_WIKI" ingest "Fake" --source "\$f" >/dev/null
done
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
expect "and the lock is freed all the same" "free" cat "$BG/.compile-lock"
out="$(FAKE_SLEEP=30 LLM_WIKI_COMPILE_TIMEOUT=1 "$W" compile bg 2>&1)" && bad "a run past its time limit is stopped" "$out" || case "$out" in *", timeout."*) ok "a run past its time limit is stopped" ;; *) bad "a run past its time limit is stopped" "$out" ;; esac
expect "and the lock is freed then too" "free" cat "$BG/.compile-lock"
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
check "five are read: one shared, four of its own" test "$(printf '%s\n' "$out" | grep -c .)" = 5
case "$out" in *"not a reminder"* | *"inside a fence"*) bad "a line that isn't a reminder, or sits in a code fence, is left out" "$out" ;; *) ok "a line that isn't a reminder, or sits in a code fence, is left out" ;; esac
out="$("$W" lint rem 2>&1)"
case "$out" in *"reminder line not understood: 1"*"sometimes bash"*) ok "lint names the line it couldn't read" ;; *) bad "lint names the line it couldn't read" "$out" ;; esac
lacks "and not the one in the fence" "inside a fence" "$W" lint rem

# tool_call <json>: what the tool-call hook replies.
tool_call() { printf '%s' "$1" | CLAUDE_PLUGIN_ROOT="$REPO" sh "$REPO/hooks/pre-tool-use.sh"; }
check "the plugin registers the tool-call hook" grep -q '"PreToolUse"' "$REPO/hooks/hooks.json"
check "its Python parses" python3 -c "import ast, sys; ast.parse(open(sys.argv[1]).read())" "$REPO/hooks/reminders.py"
out="$(tool_call '{"session_id":"s-1","tool_name":"Bash","tool_input":{"command":"git push"}}')"
[ -z "$out" ] && ok "with no session started, a tool call gets nothing" || bad "with no session started, a tool call gets nothing" "$out"
hook "$T/projects/rem" '{"session_id":"s-1","source":"startup"}' >/dev/null
check "session start writes the session's reminders" test "$(grep -c . "$RD/s-1.tsv")" = 5
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
out="$(tool_call 'not json'; echo "rc=$?")"
[ "$out" = "rc=0" ] && ok "input it can't read is ignored, and the hook still exits 0" || bad "input it can't read is ignored, and the hook still exits 0" "$out"
out="$(tool_call '{"session_id":"../s-1","tool_name":"Bash","tool_input":{"command":"git push"}}')"
[ -z "$out" ] && ok "a session id that isn't a plain name is ignored" || bad "a session id that isn't a plain name is ignored" "$out"
hook "$T/projects/rem" '{"session_id":"s-1","source":"compact"}' >/dev/null
expect "after a compaction the reminders are given again" "make sure the hooks ran" tool_call "$push"
hook "$T/projects/rem" '{"session_id":"s-1","source":"resume"}' >/dev/null
out="$(printf '%s' "$push" | LLM_WIKI_BACKGROUND=1 CLAUDE_PLUGIN_ROOT="$REPO" sh "$REPO/hooks/pre-tool-use.sh")"
[ -z "$out" ] && ok "a background compile's session gets no reminders" || bad "a background compile's session gets no reminders" "$out"
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
rm "$L/wiki/concepts/cited.md"
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
expect "stats says most sessions don't log" "Most sessions don't log" "$W" stats
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
"$W" deps --all --write >/dev/null 2>&1
check "deps --write saves the shared wiki's data/dependencies.csv" grep -q '^uses,app,go,example.com/me/lib/sub,lib,' "$WIKIS_DIR/global/data/dependencies.csv"
rm -rf "$D" "$WIKIS_DIR/global/data/dependencies.csv"
fi

if section "Sync takes turns"; then
# Another session's sync holds the collection's lock: this one waits, then runs.
L="$(git -C "$WIKIS_DIR" rev-parse --absolute-git-dir)/llm-wiki-sync.lock"
mkdir "$L"; ( sleep 2; rmdir "$L" ) &
out="$("$W" sync demo -m "demo: wait test" 2>&1)"
case "$out" in *"waiting for another session's sync"*"synced:"*) ok "sync waits for another session's sync, then runs" ;; *) bad "sync waits for another session's sync, then runs" "$out" ;; esac
check "and leaves no lock behind" test ! -d "$L"
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
printf -- '---\ntitle: Conventions\nsummary: x\nupdated: 2026-10-30\nverified: 2026-10-30\n---\n\n## For agents\n\n- After a push, check CI with gh pr checks.\n\n## Tools\n\n- ls (cli): listing\n- nosuchtool123 (cli): never installed\n- jira (mcp): tickets\n- $(touch %s/pwned) (cli): never run\n' "$T" > "$WIKIS_DIR/demo/wiki/conventions.md"
out="$("$W" start web 2>&1)"
case "$out" in *"For agents, from"*"demo/wiki/conventions.md"*"check CI with gh pr checks"*) ok "start prints the project's own For agents section" ;; *) bad "start prints the project's own For agents section" "$out" ;; esac
case "$out" in *"- ls (cli): listing  [installed]"*) ok "start marks a listed tool that's installed" ;; *) bad "start marks a listed tool that's installed" "$out" ;; esac
case "$out" in *"nosuchtool123 (cli): never installed  [NOT INSTALLED"*) ok "and one that isn't" ;; *) bad "and one that isn't" "$out" ;; esac
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
lacks "without Antigravity, setup --list says nothing about it" "antigravity" "$W" setup --list
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
check "the handbook rule ships in the template" grep -q 'wiki.sh feedback add' "$REPO/template/rules/feedback.md"
check "and AGENTS.md points to it" grep -q 'rules/feedback.md' "$REPO/template/AGENTS.md"
rm -rf "$FB" "$HOME/.config/llm-wiki/feedback" "$T/bin/gh" "$T/gh.log" "$T/gh.body" "$T/fb.md"
fi

if section "MCP server"; then
# mcp_call <tool> <json arguments>: the tool's text, with ERROR: in front if it failed.
mcp_call() {
  local a="${2:-}"
  [ -n "$a" ] || a='{}'
  printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"%s","arguments":%s}}\n' "$1" "$a" | "$W" mcp \
    | python3 -c 'import json,sys; r=json.loads(sys.stdin.readline())["result"]; print(("ERROR: " if r.get("isError") else "")+r["content"][0]["text"])'
}
out="$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}' '{"jsonrpc":"2.0","method":"notifications/initialized"}' 'not json' '{"jsonrpc":"2.0","id":2,"method":"ping"}' '{"jsonrpc":"2.0","id":3,"method":"nope"}' '{"jsonrpc":"2.0","id":4,"method":"tools/list"}' | "$W" mcp)"
check "initialize answers in the client's protocol version, with instructions" python3 -c "import json,sys; r=json.loads(sys.argv[1].splitlines()[0])['result']; assert r['protocolVersion']=='2025-03-26' and 'wiki_start' in r['instructions'] and 'tools' in r['capabilities']" "$out"
check "a notification gets no reply, bad JSON a parse error, and the server carries on" python3 -c "import json,sys; l=[json.loads(x) for x in sys.argv[1].splitlines()]; assert len(l)==5 and l[1]['error']['code']==-32700 and l[2]['id']==2 and l[3]['error']['code']==-32601" "$out"
check "it lists its tools, each with a schema" python3 -c "import json,sys; t=json.loads(sys.argv[1].splitlines()[4])['result']['tools']; assert [x['name'] for x in t]==['wiki_list','wiki_start','wiki_search','wiki_read','wiki_status','wiki_capture','wiki_feedback'] and all(x['inputSchema']['type']=='object' for x in t)" "$out"
check "it tells chat agents the wikis come before memory and past chats" python3 -c "import json,sys; l=sys.argv[1].splitlines(); r=json.loads(l[0])['result']['instructions']; t={x['name']:x['description'] for x in json.loads(l[4])['result']['tools']}; assert 'before memory' in r and 'before memory' in t['wiki_start'] and 'before memory' in t['wiki_search']" "$out"
expect "wiki_list lists the wikis and what they cover" "covers: api web" mcp_call wiki_list
expect "wiki_start finds the project's wiki" "/demo, for the repository web" mcp_call wiki_start '{"repository":"web"}'
expect "with no project, the shared wiki" "Not in a repository" mcp_call wiki_start
expect "wiki_search searches" "Deploy flow" mcp_call wiki_search '{"word":"canary"}'
expect "wiki_read defaults to the index" "# Index" mcp_call wiki_read '{"wiki":"demo"}'
expect "and reads a page" "blue-green" mcp_call wiki_read '{"wiki":"demo","path":"index.md"}'
expect "wiki_status shows what's due" "HANDBOOK" mcp_call wiki_status
expect "a path out of the wiki is refused" "ERROR: that path is outside the wiki" mcp_call wiki_read '{"wiki":"demo","path":"../global/index.md"}'
expect "so is an absolute one" "ERROR: give a path inside the wiki" mcp_call wiki_read "{\"wiki\":\"demo\",\"path\":\"$HOME/.gitconfig\"}"
ln -s "$T/secret.md" "$WIKIS_DIR/demo/wiki/link.md"; echo "very secret" > "$T/secret.md"
expect "and a link that leads out" "ERROR: that path is outside the wiki" mcp_call wiki_read '{"wiki":"demo","path":"wiki/link.md"}'
rm -f "$WIKIS_DIR/demo/wiki/link.md" "$T/secret.md"
expect "hidden folders aren't readable" "ERROR: that path is outside the wiki" mcp_call wiki_read '{"wiki":"demo","path":".compile-lock.md"}'
expect "only text files are" "ERROR: only .md, .csv and .txt" mcp_call wiki_read '{"wiki":"demo","path":"data/x.sqlite"}'
expect "a wiki name can't be a path" "ERROR: that isn't a wiki name" mcp_call wiki_read '{"wiki":"../demo"}'
expect "wiki_capture refuses a bad slug" "ERROR: the slug" mcp_call wiki_capture '{"wiki":"demo","slug":"../x","note":"n"}'
expect "and an empty note" "ERROR: the note is empty" mcp_call wiki_capture '{"wiki":"demo","slug":"x","note":" "}'
expect "wiki_capture saves and pushes" "Pushed." mcp_call wiki_capture '{"wiki":"demo","slug":"from-chat","note":"We chose Postgres, in a chat."}'
# Chat can't append to stats.csv, so the server logs its lookups.
printf 'one\n' > "$WIKIS_DIR/demo/wiki/mcp-one.md"; printf 'two\n' > "$WIKIS_DIR/demo/wiki/mcp-two.md"
SC="$WIKIS_DIR/stats.csv"; cp "$SC" "$T/stats.bak" 2>/dev/null || true; rm -f "$SC"
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"wiki_read","arguments":{"wiki":"demo"}}}' | "$W" mcp >/dev/null
check "reading the index isn't a lookup that answered anything" test ! -e "$SC"
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"wiki_read","arguments":{"wiki":"demo","path":"wiki/mcp-one.md"}}}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"wiki_read","arguments":{"wiki":"demo","path":"wiki/mcp-two.md"}}}' | "$W" mcp >/dev/null
check "reading pages logs one hit, however many pages" bash -c "[ \"\$(grep -c ',demo,hit$' '$SC')\" = 1 ] && head -n 1 '$SC' | grep -qx 'date,wiki,result'"
expect "a search that finds nothing is logged" ",global,search-none,zzzabsent" bash -c "printf '%s\n' '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"wiki_search\",\"arguments\":{\"word\":\"zzzabsent\"}}}' | '$W' mcp >/dev/null; tail -n 1 '$SC'"
rm -f "$SC" "$WIKIS_DIR/demo/wiki/mcp-one.md" "$WIKIS_DIR/demo/wiki/mcp-two.md"; [ ! -f "$T/stats.bak" ] || mv "$T/stats.bak" "$SC"
check "the note is a normal capture" bash -c "grep -q '^Captured: ' '$WIKIS_DIR'/demo/raw/*-from-chat.md && grep -q 'We chose Postgres' '$WIKIS_DIR'/demo/raw/*-from-chat.md"
check "and it reached the remote" bash -c "git --git-dir='$T/remote.git' log -1 --format=%s | grep -q 'capture from-chat'"
expect "wiki_feedback follows the setting" "feedback is off" mcp_call wiki_feedback '{"kind":"idea","summary":"s","details":"d"}'
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
lacks "and every flag's arm in wiki.sh is guarded" "shift" bash -c "grep -E '^ +-[^ )]*\) .*\\\$\{2:-\}.*shift' '$REPO/wiki.sh' | grep -v 'need_value\|die \|needs a name'"
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
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
class H(BaseHTTPRequestHandler):
    def log_message(self, *_): pass
    def do_POST(self):
        body = {"client_id": "Iv1.fakeid", "client_secret": "real-secret-4242", "slug": "fake-slug", "pem": "pem-4242", "webhook_secret": "hook-4242"}
        status = 201 if self.path == "/app-manifests/goodcode/conversions" else 404
        data = json.dumps(body if status == 201 else {}).encode()
        self.send_response(status); self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)
s = HTTPServer(("127.0.0.1", 0), H)
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
check "news without a NEWS.md stays quiet" env XDG_STATE_HOME="$N/none" LLM_WIKI_NEWS_FILE="$N/none.md" "$W" status
check "NEWS.md entries are dated, with different titles" python3 -c "
import re,sys
h=[l for l in open(sys.argv[1]) if l.startswith('## ')]
assert h and all(re.match(r'## \d{4}-\d\d-\d\d: \S', l) for l in h) and len(set(h))==len(h)
d=[l[3:13] for l in h]
assert d==sorted(d,reverse=True)" "$REPO/NEWS.md"
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
