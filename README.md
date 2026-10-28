# llm-wiki

Your coding agent forgets everything between sessions. llm-wiki gives it a memory you can read: a small markdown wiki for each project, kept by the agent itself.

- **It answers from what you've already worked out.** Before answering, the agent checks the wiki for the project you're in, and for any other project the work touches.
- **It saves what matters, on its own.** Decisions and why, corrections, root causes, research findings. Not a log of everything, and nothing you mark off the record.
- **It stays plain files.** One folder per project in `~/wikis`, in git, readable in any editor. No database, no service.

It also writes your standup, tallies repeated corrections until they become a rule, and can hand busywork to cheaper models.

## Start here

| You use | Guide | Time |
|---|---|---|
| Claude Code: in a terminal, the Claude desktop app's **Code** tab, or an IDE | [Set up with Claude Code](docs/claude-code.md), as a plugin | 5 minutes |
| Anything else: Codex, Cursor, Copilot, the desktop app's **Chat** tab, claude.ai | [Set up with another agent](docs/other-agents.md) | 10 minutes |

Joining a team that already shares a collection? Read [Teams](docs/teams.md#join-a-shared-collection) first.

## Then

- [Using it](docs/using.md): what the agent does on its own, what to say, standups, many repositories.
- [Teams](docs/teams.md): one shared collection for everyone.
- [Troubleshooting](docs/troubleshooting.md)
- [Maintaining the template](docs/maintaining.md): changing the rules, releasing.

## How it works

Each project has a wiki in `~/wikis`, named after its repository. When the session produces something worth keeping, the agent writes a short dated note into that wiki's `raw/` folder. Later, at a pause, it compiles waiting notes into small linked pages and lists them in `index.md`. Every session starts by reading that index, so answers come from compiled pages instead of rereading everything.

The rules the agent follows are a handbook, `AGENTS.md`, copied into each wiki from this repo's `template/`. Any agent and any model can follow it. Nothing depends on one vendor.

This repo is the template, the setup script `wiki.sh`, and a Claude Code plugin. It is not a wiki itself.
