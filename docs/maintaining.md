# Maintaining the template

For whoever changes the rules, the script or the plugin. Work in a clone.

## What's here

```
README.md          The landing page.
LICENSE            MIT.
docs/              Setup guides, using it, teams, troubleshooting, this page.
AGENTS.md          Tells an agent this is the template and how to start a wiki from it.
CLAUDE.md          Imports AGENTS.md for Claude Code.
ROADMAP.md         Planned improvements, untested areas, and what was decided against.
CHANGELOG.md       What each handbook version changed. upgrade prints the parts you missed.
wiki.sh            Setup and upkeep. Run it with no arguments for the commands.
template/          The scaffold, copied whole to start a wiki.
  AGENTS.md        The core handbook. Loaded in every session.
  rules/           The rest of the handbook. Read on demand.
  CLAUDE.md        Imports the handbook for Claude Code.
  .gitattributes   Lets git merge index.md and log.md from two people without a conflict.
  links.md         Shared wikis this one can fall back to.
  patterns.md      Recurring feedback, tallied toward a fix.
  repos.md         Repositories this wiki covers, when more than one.
  raw/ wiki/ data/ Sources, compiled pages, structured data.
skills/llm-wiki/   The Claude skill that finds, runs, and scaffolds wikis.
.claude-plugin/    The plugin manifest, and the marketplace that lists it.
commands/          The plugin's slash commands. wiki.sh also makes skills from them for Antigravity, Codex and Cursor.
tests/smoke.sh     Smoke tests for wiki.sh, the hook and the secret scan. CI runs them.
.github/workflows/ CI: shellcheck, plugin validation, and the smoke tests on Linux and macOS.
scripts/
  migrate-to-plugin.sh  Moves a machine from the clone-and-line setup to the plugin.
hooks/
  hooks.json       The plugin's session hook, which runs session-start.sh.
  session-start.sh Finds the session's wiki, points the session at it, and keeps the wiki command current.
  pre-commit       The secret scan that wiki.sh installs in wiki repos.
```

## Change the rules

The handbook is `template/AGENTS.md` plus `template/rules/`. `AGENTS.md` loads in every session, so it holds only what every session needs. The rules files are read on demand: compile, conflicts, lint, peers, journal, patterns, delegation.

1. Edit them.
2. Bump the version at the top of `template/AGENTS.md`.
3. Add a section for that version to `CHANGELOG.md`, written for the person upgrading: what changed, and `- Do:` lines for anything they need to do. `wiki upgrade` prints it.
4. Run `wiki upgrade --all` to roll it out to your own wikis.

Batch handbook changes: at most one version a day. Each version makes every machine's next session upgrade and commit. Seven versions in one day left people seeing "behind template" over and over.

## Add a setting

A journal setting is one line in `JOURNAL_SETTINGS` in `wiki.sh`: key, type, basic or advanced, default, description. That line writes the config entry, validates `journal set`, and makes `wiki setup --new` ask about it on every machine. Anything else a person configures needs its own step in `cmd_setup`, recorded with `setup_mark`.

## Release

Merging to `main` is the release. The plugin has no version number, so every commit on `main` reaches plugin users with auto-update on, and a broken one breaks everyone's sessions at once. So:

1. Work on a branch.
2. Run the smoke tests: `tests/smoke.sh`. They take a few seconds, run in a temp folder with their own `HOME`, and never touch your wikis. Install gitleaks first, or the secret-scan tests are skipped.
3. Push the branch and open a pull request. CI runs shellcheck, `claude plugin validate`, and the smoke tests on Linux and on macOS with Apple's bash 3.2.
4. Merge when CI is green. GitHub enforces this: `main` is protected, so it takes a pull request with all three CI checks passing, for admins too. In an emergency, untick "Do not allow bypassing the above settings" in the repository's Settings → Branches, and tick it again afterwards.

Add a smoke test when you fix a bug or add a command. Each one is a line or two: see the helpers at the top of `tests/smoke.sh`.

A change people will notice belongs in the setup guides or [Using it](using.md), not only in the CHANGELOG. The one `claude plugin validate` warning, no `version`, is on purpose.

To try a change before pushing it, install the plugin from your clone: `claude plugin marketplace add <path to clone>`, then `claude plugin install llm-wiki@llm-wiki`. A marketplace added from a local path runs straight from your working tree, so a new session picks up your edits. Switch back with `claude plugin marketplace remove llm-wiki` and the install steps in [Set up with Claude Code](claude-code.md).

Every call to action that `wiki status` or `wiki report` prints ends with its fix: `Run:` a terminal command, `Ask an agent:` the exact request, or `Do:` a manual step. Add new flags to status's To do list with `todo_add`. A smoke test fails any item without a fix.

Keep the session hook's output short. Claude Code shows the model only a short preview of a long hook output and saves the rest to a file, which the model may never read. The hook points at the handbook rather than embedding it for this reason.

`ROADMAP.md` lists what's planned and what's still untested. When you finish an item, move it to Done and say what changed.
