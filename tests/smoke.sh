#!/usr/bin/env bash
# Smoke tests for wiki.sh, the plugin's session hook, and the secret scan.
# Everything runs in a temp folder with its own HOME, so real wikis and settings are
# never touched. Works with the bash that ships on macOS (3.2) and on Linux.
#
#   tests/smoke.sh
#
# The secret-scan tests run only when gitleaks is installed. CI installs it.
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
W="$REPO/wiki.sh"
T="$(mktemp -d)"
T="$(cd "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT

export HOME="$T/home"
export WIKIS_DIR="$T/wikis"
mkdir -p "$HOME" "$T/bin"
git config --global user.email smoke@example.com
git config --global user.name "Smoke Test"
git config --global init.defaultBranch main

TV="$(sed -n 's/^Handbook version \([0-9][0-9]*\).*/\1/p' "$REPO/template/AGENTS.md" | head -n 1)"
pass=0
fail=0
skip=0

ok() { pass=$((pass + 1)); printf 'ok    %s\n' "$1"; }
bad() {
  fail=$((fail + 1))
  printf 'FAIL  %s\n' "$1"
  [ -z "${2:-}" ] || printf '%s\n' "$2" | head -n 15 | sed 's/^/        /'
}
skipped() { skip=$((skip + 1)); printf 'skip  %s\n' "$1"; }
section() { printf '\n# %s\n' "$1"; }

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

section "Collection"
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

section "What a new wiki gets"
for f in .gitattributes .gitignore patterns.md links.md repos.md rules/peers.md rules/compile.md; do
  check "demo has $f" test -f "$WIKIS_DIR/demo/$f"
done
expect "index.md merges by union" "merge: union" git -C "$WIKIS_DIR" check-attr merge -- demo/index.md
expect "log.md merges by union" "merge: union" git -C "$WIKIS_DIR" check-attr merge -- demo/log.md
check "delegation.md is git-ignored" git -C "$WIKIS_DIR" check-ignore -q delegation.md
check "the secret-scan hook is installed" grep -q "llm-wiki secret scan" "$WIKIS_DIR/.git/hooks/pre-commit"

section "Upgrade"
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

section "Two clones merge index.md and log.md"
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

section "Secret scan"
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

section "Session hook"
mkdir -p "$T/projects/web" && git -C "$T/projects/web" init -q
# hook <project dir> [stdin json]
hook() { printf '%s' "${2:-}" | CLAUDE_PLUGIN_ROOT="$REPO" CLAUDE_PLUGIN_DATA="$T/data" CLAUDE_PROJECT_DIR="$1" bash "$REPO/hooks/session-start.sh"; }
# context <json>: the additionalContext from hook output, or a parse error.
context() {
  python3 -c 'import json, sys
d = json.load(sys.stdin)["hookSpecificOutput"]
assert d["hookEventName"] == "SessionStart"
print(d["additionalContext"])'
}
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

section "Links and plugin mode"
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

section "Seed"
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

section "Pending and bulk compile"
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

section "Team skills"
SK="$HOME/.claude/skills"
mkdir -p "$SK/go-expert" && printf -- '---\nname: go-expert\ndescription: mine\n---\n' > "$SK/go-expert/SKILL.md"
mkskill() { mkdir -p "$1" && printf -- '---\nname: %s\ndescription: %s\n---\n\nSteps.\n' "${1##*/}" "$2" > "$1/SKILL.md"; }
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

section "Tips"
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

section "Tab completion"
expect "the first word completes to commands" "standup" "$W" __complete 1 st
expect "journal set completes setting names" "max_commits" "$W" __complete 3 journal set ""
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

section "Weekly report"
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
rm -rf "$HOME/.gemini"
for i in 01 02 03 04 05 06 07 08 09 10; do printf 'Captured: %s\n\nA note.\n' "$(date -u +%Y-%m-%d)" > "$WIKIS_DIR/global/raw/$(date -u +%Y-%m-%d)-1200$i-busy-$i.md"; done
expect "a busy week with no corrections becomes a Needs you item" "may have gone to its own memory" "$W" report
printf 'Captured: %s\n\nFeedback: correction | everywhere | Ask before pushing.\n' "$(date -u +%Y-%m-%d)" > "$WIKIS_DIR/global/raw/$(date -u +%Y-%m-%d)-120099-feedback.md"
lacks "and goes away once one is recorded" "may have gone to its own memory" "$W" report
rm -f "$WIKIS_DIR"/global/raw/*-busy-*.md "$WIKIS_DIR"/global/raw/*-120099-feedback.md
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

section "Bookkeeping commands"
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

section "Index and lint"
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

section "Setup fit"
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

section "Harvest Claude Code memory"
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

section "Setup fixes"
check "setup --new would ask about tab completion" bash -c "SHELL=/bin/zsh '$W' setup --list | grep -q '^completion  *off  <- new'"
printf '.DS_Store\n.compile-lock\njournal/\ndelegation.md\ndelegation-log.csv\nstats.csv\n' > "$WIKIS_DIR/.gitignore"
git -C "$WIKIS_DIR" add .gitignore >/dev/null 2>&1 && git -C "$WIKIS_DIR" commit -qm "old ignores" -- .gitignore >/dev/null 2>&1
expect "with no wiki behind, upgrade still commits collection changes" 'Committed the upgrade as "wikis: update collection files"' "$W" upgrade --all
check "and the ignore rules are anchored" grep -qx '/delegation.md' "$WIKIS_DIR/.gitignore"

section "Stats"
expect "stats with no log says so" "No lookups logged yet" "$W" stats
check "stats.csv is git-ignored" git -C "$WIKIS_DIR" check-ignore -q stats.csv
today="$(date -u +%Y-%m-%d)"
printf 'date,wiki,result\n%s,demo,hit\n%s,demo,miss\n%s,global,hit\n2000-01-01,demo,miss\n' "$today" "$today" "$today" > "$WIKIS_DIR/stats.csv"
expect "stats computes a wiki's hit rate" "50%" "$W" stats
expect "stats totals every wiki" "67%" "$W" stats
lacks "stats leaves out lookups before the range" "25%" "$W" stats

section "Plugin updates reach the wiki command"
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

section "Journal and standup"
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

section "Commit distance"
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

section "Dependency map"
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
"$W" deps --all --write >/dev/null 2>&1
check "deps --write saves the shared wiki's data/dependencies.csv" grep -q '^uses,app,go,example.com/me/lib/sub,lib,' "$WIKIS_DIR/global/data/dependencies.csv"
rm -rf "$D" "$WIKIS_DIR/global/data/dependencies.csv"

section "Sync takes turns"
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

section "Session start in one call"
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

section "A remote the branch doesn't track"
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

section "Antigravity plugin"
lacks "without Antigravity, setup --list says nothing about it" "antigravity" "$W" setup --list
mkdir -p "$HOME/.gemini"
expect "with Antigravity, setup --list shows the plugin missing" "plugin missing" "$W" setup --list
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

section "Codex plugin"
lacks "without Codex, setup --list says nothing about it" "codex" "$W" setup --list
mkdir -p "$HOME/.codex"
expect "with Codex, setup --list shows the plugin missing" "codex               plugin missing" "$W" setup --list
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
# setup wants a terminal for its questions. The tests answer through a pipe.
in_tty() { LLM_WIKI_TEST_TTY=1 "$@"; }
out="$(printf 'y\n' | PATH="$T/bin:$PATH" in_tty "$W" setup codex 2>&1)"
case "$out" in *"replaces the wiki line"*"/hooks and trust both"*) ok "setup codex installs it and says to trust its hooks" ;; *) bad "setup codex installs it and says to trust its hooks" "$out" ;; esac
check "it adds the marketplace and the plugin with the codex command" grep -qx "plugin add llm-wiki@llm-wiki" "$T/codex.log"
check "its marketplace lists the plugin" python3 -c "import json,sys; p=json.load(open(sys.argv[1]))['plugins'][0]; assert p['name']=='llm-wiki' and p['source']=={'source':'local','path':'./plugins/llm-wiki'}" "$HOME/.codex/llm-wiki/.agents/plugins/marketplace.json"
check "its hooks run __codex-start at SessionStart and PostCompact" python3 -c "import json,sys; h=json.load(open(sys.argv[1]))['hooks']['hooks']; assert all(h[e][0]['hooks'][0]['command'].endswith(' __codex-start') for e in ('SessionStart','PostCompact'))" "$HOME/.codex/llm-wiki/plugins/llm-wiki/.codex-plugin/plugin.json"
check "the old line is replaced in place, and the rest of AGENTS.md stays" python3 -c "import sys; t=open(sys.argv[1]).read(); assert t.startswith('# Mine\n\nKeep this.\n\nMy knowledge wikis live in') and 'plugin' in t.split('\n')[4] and t.endswith('\n\nAnd this.\n') and 'old line' not in t" "$HOME/.codex/AGENTS.md"
check "it links the llm-wiki skill" test -f "$HOME/.codex/skills/llm-wiki/SKILL.md"
check "and the slash commands as skills" test -f "$HOME/.codex/skills/wiki-compile/SKILL.md"
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

section "Cursor"
lacks "without Cursor, setup --list says nothing about it" "cursor" "$W" setup --list
mkdir -p "$HOME/.cursor"
expect "with Cursor and no Claude Code plugin, setup --list shows the hook missing" "cursor              hook missing" "$W" setup --list
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

section "Compiled without summary pages (v24)"
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
section "Claude Code permissions"
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

section "Collections"
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
rm -f "$HOME/.config/llm-wiki/collections"

section "Update"
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

printf '\n%d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ]
