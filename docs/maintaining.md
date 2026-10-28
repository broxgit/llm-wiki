# Maintaining the template

For whoever changes the rules, the script or the plugin. Work in a clone.

## What's here

```
README.md          The landing page.
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
commands/          The plugin's slash commands.
hooks/
  hooks.json       The plugin's session hook, which runs session-start.sh.
  session-start.sh Finds the session's wiki, loads it, and keeps the wiki command current.
  pre-commit       The secret scan that wiki.sh installs in wiki repos.
```

## Change the rules

The handbook is `template/AGENTS.md` plus `template/rules/`. `AGENTS.md` loads in every session, so it holds only what every session needs. The rules files are read on demand: compile, conflicts, lint, peers, journal, patterns, delegation.

1. Edit them.
2. Bump the version at the top of `template/AGENTS.md`.
3. Add a section for that version to `CHANGELOG.md`, written for the person upgrading: what changed, and `- Do:` lines for anything they need to do. `wiki upgrade` prints it.
4. Run `wiki upgrade --all` to roll it out to your own wikis.

## Add a setting

A journal setting is one line in `JOURNAL_SETTINGS` in `wiki.sh`: key, type, basic or advanced, default, description. That line writes the config entry, validates `journal set`, and makes `wiki setup --new` ask about it on every machine. Anything else a person configures needs its own step in `cmd_setup`, recorded with `setup_mark`.

## Release

Pushing to the default branch is the release. The plugin has no version number, so every pushed commit reaches plugin users with auto-update on. Before pushing:

- `shellcheck -S warning wiki.sh hooks/session-start.sh hooks/pre-commit`
- `claude plugin validate .` after any change to `.claude-plugin/`, `commands/` or `hooks/hooks.json`. The one warning, no `version`, is on purpose.
- Docs: a change people will notice belongs in the setup guides or [Using it](using.md), not only in the CHANGELOG.

`ROADMAP.md` lists what's planned and what's still untested. When you finish an item, move it to Done and say what changed.
