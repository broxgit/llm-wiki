# AGENTS.md

This repo is a template. It holds the rules and the scaffold for LLM-maintained wikis. It is not a wiki. Never store knowledge here.

## If the user pointed you here to start using a wiki

1. Get the wiki root. It is a separate folder, one per code repository, never one per session. If the user didn't name one, use `~/wikis/<repository-name>`, named after the repository this session is working in. Create it without asking when `~/wikis` already exists. Otherwise confirm first.
2. If the wiki root has no `AGENTS.md`, scaffold it. With a shell, run `./wiki.sh new <wiki root>` from this repo. It does all of this step. Without one, do it by hand: create the folder, copy everything inside `template/` into it with hidden files included and nothing overwritten, then create `index.md` containing `# Index` and `log.md` containing `# Log` in the wiki root. Copy without reading. You read the handbook once, in step 4.
3. Check the new wiki's `links.md`. It ships pointing at a shared wiki at `~/wikis/global`. If that wiki doesn't exist, offer once to scaffold it the same way. If the user keeps a shared wiki somewhere else, edit the line.
4. Read `AGENTS.md` in the wiki root and follow it from then on. That copy is the authority for that wiki.
5. If the wiki sits inside a project folder, or this session is working in one, check that project for its own agent instruction file (`AGENTS.md`, `CLAUDE.md`, or similar). If it has one that doesn't mention the wiki, offer once to add the line below. It is what lets future sessions find the wiki with no prompting.
6. Write nothing in this repo.

```
This project's knowledge wiki is at <wiki root>. Read its AGENTS.md at session start and follow it.
```

From then on, use the wiki without being told to. The handbook says when to query, capture, and compile on your own. Several sessions can share one wiki. A lock keeps compile work to one session at a time.

Wikis in the same folder are peers, each named after a repository. What you learn about another repository goes in that repository's wiki, so any later session can find it there.

## If a wiki's handbook is out of date

`template/AGENTS.md` carries a version number. The files in `template/rules/` share it. If a wiki's copy has a lower one, tell the user. Upgrade it with `./wiki.sh upgrade <name>` only when they say so.

## Working on this repo itself

Edit the handbook, the skill, or the README only when the user asks. The handbook is `template/AGENTS.md` plus `template/rules/`. When any of it changes, bump the version in `template/AGENTS.md`. Keep `template/AGENTS.md` short: it loads in every session, so anything a session needs only sometimes belongs in `rules/`.

`ROADMAP.md` lists planned improvements and what is still untested. When you finish an item, move it to Done and say what changed.
