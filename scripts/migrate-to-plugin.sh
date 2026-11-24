#!/usr/bin/env bash
# Move a machine set up the old way (a clone of this repo plus the ~/.claude/CLAUDE.md
# line) onto the Claude Code plugin, and bring its wikis up to date.
# Safe to rerun: each step checks before it acts. It asks before committing or pushing.
#
#   ./scripts/migrate-to-plugin.sh
#
# Commands that don't need answers get </dev/null, so they can't swallow typed input.
set -euo pipefail
# Each git here acts on the wikis folder, never on a repository the environment names, as a
# dotfiles setup's GIT_DIR and GIT_WORK_TREE do. The same list is in wiki.sh: change them together.
unset GIT_DIR GIT_WORK_TREE GIT_IMPLICIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
  GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_QUARANTINE_PATH GIT_GRAFT_FILE GIT_SHALLOW_FILE GIT_REPLACE_REF_BASE \
  GIT_NAMESPACE GIT_CONFIG GIT_CONFIG_PARAMETERS GIT_PREFIX
# And git takes no folder that holds HEAD, objects/ and refs/ for a repository unless it is
# named: safe.bareRepository=explicit, last, as wiki.sh's own first step adds it.
mig_n="${GIT_CONFIG_COUNT:-0}"
case "$mig_n" in '' | *[!0-9]*) mig_n=0 ;; esac
mig_n=$((10#$mig_n))
mig_k="GIT_CONFIG_KEY_$((mig_n - 1))"; mig_v="GIT_CONFIG_VALUE_$((mig_n - 1))"
if [ "$mig_n" -eq 0 ] || [ "$(printf '%s' "${!mig_k:-}" | LC_ALL=C tr 'A-Z' 'a-z')" != safe.barerepository ] || [ "${!mig_v:-}" != explicit ]; then
  export "GIT_CONFIG_KEY_$mig_n=safe.bareRepository" "GIT_CONFIG_VALUE_$mig_n=explicit" GIT_CONFIG_COUNT=$((mig_n + 1))
fi
unset mig_n mig_k mig_v

WIKIS_DIR="${WIKIS_DIR:-$HOME/wikis}"
SETTINGS="$HOME/.claude/settings.json"
CLAUDE_MD="$HOME/.claude/CLAUDE.md"
STAMP="$(date +%Y%m%d-%H%M%S)"

step() { printf '\n== %s\n' "$1"; }
# wikis_repo: the wikis folder is the top of a git repository of its own, as wiki.sh's
# collection_repo has it. Its .git is looked for first, so a folder with none starts no git:
# a git older than 2.38 doesn't know safe.bareRepository.
wikis_repo() {
  local top here
  [ -e "$WIKIS_DIR/.git" ] || [ -L "$WIKIS_DIR/.git" ] || return 1
  top="$(git -C "$WIKIS_DIR" rev-parse --show-toplevel 2>/dev/null)" || return 1
  here="$(cd "$WIKIS_DIR" 2>/dev/null && pwd -P)" || return 1
  [ -n "$top" ] && [ "$top" = "$here" ]
}
die() { echo "error: $*" >&2; exit 1; }
ask_yn() {
  local r
  printf '%s [y/N] ' "$1"
  IFS= read -r r || return 1
  case "$r" in y | Y | yes) return 0 ;; *) return 1 ;; esac
}

command -v claude >/dev/null 2>&1 || die "Claude Code isn't installed: no claude command."
command -v git >/dev/null 2>&1 || die "git isn't installed."
command -v python3 >/dev/null 2>&1 || die "python3 is needed to edit $SETTINGS."
[ -t 0 ] || die "this script asks questions, so run it in a terminal."

# 1. Pulling a commit that untracked delegation.md deletes this machine's copy,
#    so keep it aside first and put it back after the upgrade.
step "Collection"
deleg_backup=""
if [ -f "$WIKIS_DIR/delegation.md" ]; then
  deleg_backup="$(dirname "$WIKIS_DIR")/.llm-wiki-delegation.md.bak-$STAMP"
  cp "$WIKIS_DIR/delegation.md" "$deleg_backup"
  echo "saved delegation.md to $deleg_backup"
fi
if wikis_repo && [ -n "$(git -C "$WIKIS_DIR" remote 2>/dev/null)" ]; then
  if [ -n "$(git -C "$WIKIS_DIR" status --porcelain)" ]; then
    # Likely an earlier run of this script, stopped before its commit step.
    echo "$WIKIS_DIR has uncommitted changes, so it isn't pulled now. The commit step below offers to commit them."
  else
    git -C "$WIKIS_DIR" pull --no-rebase --no-edit </dev/null
  fi
elif [ -d "$WIKIS_DIR" ]; then
  echo "$WIKIS_DIR isn't a git repository of its own with a remote, nothing to pull."
else
  echo "no collection at $WIKIS_DIR yet. wiki setup creates one at the end."
fi

step "gitleaks"
if command -v gitleaks >/dev/null 2>&1; then
  echo "already installed"
elif command -v brew >/dev/null 2>&1; then
  brew install gitleaks </dev/null
else
  echo "Homebrew isn't installed. Install gitleaks yourself: https://github.com/gitleaks/gitleaks"
fi

step "Plugin"
if claude plugin marketplace list </dev/null 2>/dev/null | grep -q '❯ llm-wiki$'; then
  echo "marketplace llm-wiki already added"
else
  claude plugin marketplace add broxgit/llm-wiki </dev/null
fi
if claude plugin list --json </dev/null 2>/dev/null | grep -q '"llm-wiki@llm-wiki"'; then
  echo "plugin already installed"
else
  claude plugin install llm-wiki@llm-wiki </dev/null
fi
plugin_root="$(claude plugin list --json </dev/null | python3 -c '
import json, sys
for p in json.load(sys.stdin):
    if p.get("id") == "llm-wiki@llm-wiki":
        print(p.get("installPath", ""))')"
[ -x "$plugin_root/wiki.sh" ] || die "can't find the installed plugin's wiki.sh (got: ${plugin_root:-nothing})."

step "Auto-update"
[ -f "$SETTINGS" ] && cp "$SETTINGS" "$SETTINGS.bak-$STAMP"
python3 - "$SETTINGS" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as f:
    s = json.load(f)
m = s.get("extraKnownMarketplaces", {}).get("llm-wiki")
if m is None:
    print("no llm-wiki marketplace entry in settings.json, skipped. Turn it on with /plugin in a terminal session.")
elif m.get("autoUpdate") is True:
    print("already on")
else:
    m["autoUpdate"] = True
    with open(path, "w") as f:
        json.dump(s, f, indent=2)
        f.write("\n")
    print("turned on")
PY

step "Old session line"
if [ -f "$CLAUDE_MD" ] && grep -q 'knowledge wikis live in' "$CLAUDE_MD"; then
  cp "$CLAUDE_MD" "$CLAUDE_MD.bak-$STAMP"
  grep -v 'knowledge wikis live in' "$CLAUDE_MD.bak-$STAMP" > "$CLAUDE_MD" || true
  echo "removed it from $CLAUDE_MD (backup beside it)"
else
  echo "not there"
fi

# 2. The wiki command. Normally the plugin's session hook writes it at session start;
#    running the hook once here does the same, with the plugin's own code.
step "wiki command"
data_dir="$HOME/.claude/plugins/data/llm-wiki-llm-wiki"
CLAUDE_PLUGIN_ROOT="$plugin_root" CLAUDE_PLUGIN_DATA="$data_dir" CLAUDE_PROJECT_DIR="$HOME" \
  bash "$plugin_root/hooks/session-start.sh" </dev/null >/dev/null
[ -x "$data_dir/bin/wiki" ] || die "the plugin's hook didn't create $data_dir/bin/wiki."
mkdir -p "$HOME/.local/bin"
link="$HOME/.local/bin/wiki"
if [ -e "$link" ] && ! [ "$link" -ef "$data_dir/bin/wiki" ]; then
  mv "$link" "$link.bak-$STAMP"
  echo "moved the old $link aside to $link.bak-$STAMP"
fi
ln -sf "$data_dir/bin/wiki" "$link"
echo "linked $link"
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) echo "note: ~/.local/bin isn't on your PATH. Add this to your shell profile: export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac
WIKI="$link"

if [ ! -d "$WIKIS_DIR" ]; then
  step "Setup"
  "$WIKI" setup
fi

step "Upgrade"
"$WIKI" upgrade --all </dev/null
if [ -n "$deleg_backup" ]; then
  cp "$deleg_backup" "$WIKIS_DIR/delegation.md"
  echo "restored delegation.md"
fi
if wikis_repo && git -C "$WIKIS_DIR" ls-files --error-unmatch delegation.md >/dev/null 2>&1; then
  git -C "$WIKIS_DIR" rm -q --cached delegation.md
  echo "delegation.md is no longer tracked. Each machine keeps its own."
fi

step "Commit"
if wikis_repo && [ -n "$(git -C "$WIKIS_DIR" status --porcelain)" ]; then
  git -C "$WIKIS_DIR" status --short
  if ask_yn "Commit these as \"wikis: handbook upgrade\"?"; then
    git -C "$WIKIS_DIR" add -A
    git -C "$WIKIS_DIR" commit -q -m "wikis: handbook upgrade"
    echo "committed"
    if [ -n "$(git -C "$WIKIS_DIR" remote)" ] && ask_yn "Push?"; then
      git -C "$WIKIS_DIR" push </dev/null
    fi
  else
    echo "left uncommitted"
  fi
else
  echo "nothing to commit"
fi

step "New settings"
"$WIKI" setup --new

step "Status"
"$WIKI" status

cat <<EOF

Done. Last steps:
- Start a new Claude Code session and ask: "What does your llm-wiki session context say?"
- The old clone of this repo is no longer needed to use llm-wiki. Keep it if you edit the template.
- Backups from this run end in .bak-$STAMP, beside each file it changed.
EOF
