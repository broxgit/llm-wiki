# AGENTS.md

This repo is a template. It holds the rules and the scaffold for LLM-maintained wikis. It is not a wiki. Never store knowledge here.

## If the user pointed you here to start using a wiki

1. Get the wiki root. It is a separate folder, one per project, never one per session. If the user didn't name one, run `./wiki.sh which <repository-name>` for the repository this session is working in. It prints the wiki that covers it. If none does, use `~/wikis/<repository-name>`, and create it without asking when `~/wikis` already exists. Otherwise confirm first.
2. If the wiki root has no `AGENTS.md`, scaffold it. With a shell, run `./wiki.sh new <wiki root>` from this repo. It does all of this step. Without one, do it by hand: create the folder, copy everything inside `template/` into it with hidden files included and nothing overwritten, then create `index.md` containing `# Index` and `log.md` containing `# Log` in the wiki root. Copy without reading. You read the handbook once, in step 4.
3. Check the new wiki's `links.md`. It ships pointing at a shared wiki at `~/wikis/global`. If that wiki doesn't exist, offer once to scaffold it the same way. If the user keeps a shared wiki somewhere else, edit the line.
4. Read `AGENTS.md` in the wiki root and follow it from then on. That copy is the authority for that wiki.
5. If the wiki sits inside a project folder, or this session is working in one, check that project for its own agent instruction file (`AGENTS.md`, `CLAUDE.md`, or similar). If it has one that doesn't mention the wiki, offer once to add the line below. It is what lets future sessions find the wiki with no prompting.
6. Write nothing in this repo.

```
This project's knowledge wiki is at <wiki root>. Read its AGENTS.md at session start and follow it.
```

From then on, use the wiki without being told to. The handbook says when to query, capture, and compile on your own. Several sessions can share one wiki. A lock keeps compile work to one session at a time.

Wikis in the same folder are peers. Most cover one repository and are named after it. A project that spans several repositories has one wiki that lists them in `repos.md`. What you learn about another project goes in that project's wiki, so any later session can find it there.

## Setup and settings

The collection's `journal/` folder holds the user's work journal. It is personal, not a wiki.

`./wiki.sh setup` is an interactive walkthrough for a person at a terminal. Don't run it for the user. To see the current settings, run `./wiki.sh setup --list`. To change one journal setting the user asked for, run `./wiki.sh journal set <key> <value>`. If `./wiki.sh status` says there are new settings, tell the user to run `./wiki.sh setup --new`.

## If a wiki's handbook is out of date

`template/AGENTS.md` carries a version number. The files in `template/rules/` share it. If a wiki's copy has a lower one, tell the user. Upgrade it with `./wiki.sh upgrade <name>` only when they say so.

## Working on this repo itself

Edit the handbook, the skill, the README, or `docs/` only when the user asks. `docs/maintaining.md` is the maintainer's guide. The handbook is `template/AGENTS.md` plus `template/rules/`. When any of it changes, bump the version in `template/AGENTS.md` and add a section for that version to `CHANGELOG.md`, written for the person upgrading: what changed, and `- Do:` lines for anything they need to do. `./wiki.sh upgrade` prints it. Keep `template/AGENTS.md` short: it loads in every session, so anything a session needs only sometimes belongs in `rules/`.

A new journal setting is one line in `JOURNAL_SETTINGS` in `wiki.sh`. It reaches the config file, validation, and `setup --new` from there. Anything else the user configures gets a step in `cmd_setup`, recorded with `setup_mark`, so `setup --new` asks about it once on each machine.

The repo is also a Claude Code plugin: `.claude-plugin/` holds the manifest and the marketplace, `commands/` the slash commands, and `hooks/hooks.json` the session hook. Check changes to them with `claude plugin validate .`.

`ROADMAP.md` lists planned improvements and what is still untested. When you finish an item, move it to Done and say what changed.
