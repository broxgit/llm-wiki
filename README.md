# llm-wiki

Your coding agent forgets everything between sessions. llm-wiki gives it a memory you can read: a small markdown wiki for each project, kept by the agent itself.

- **It answers from what you've already worked out.** Before answering, the agent checks the wiki for the project you're in, and for any other project the work touches.
- **It saves what matters, on its own.** Decisions and why, corrections, root causes, research findings. Not a log of everything, and nothing you mark off the record.
- **It stays plain files.** One folder per project in `~/wikis`, in git, readable in any editor. No database, no service.


## What it does

### Remembers, so you stop re-explaining

- **Checks the wiki before answering.** The agent reads the index of the wiki for the repo you're in, and opens the pages that fit. *You stop re-explaining the same architecture, quirks and decisions to every new session.*
- **Saves what matters, without being asked.** Decisions and the reasons behind them, your corrections, root causes, research findings, at natural stopping points. *Knowledge that would vanish with the session survives it, and you don't have to remember to write it down.*
- **Turns notes into small linked pages.** Notes are compiled into one page per topic, listed in an index. A backlog, such as a newly seeded wiki, is compiled in one batch. *Answers come from a few short pages instead of rereading code, docs and old chats.*
- **Keeps itself honest.** Pages record when they were last checked, and against which commit. Before acting on a page, the agent checks it against the code. Contradictions are flagged for you rather than overwritten, and a regular health check catches broken links and stale pages. *A confident wrong answer is worse than none.*

### Useful from day one

- **`wiki seed`** starts a repo's wiki from what it already has: its README, `CLAUDE.md` and `AGENTS.md`, Cursor and Copilot rules, Claude skills, `docs/`, and decision records. *The first question you ask in a new repo can already be answered from the wiki.*

### Shares knowledge across projects and people

- **One wiki per project, found by name.** A session in repo A that needs to know about repo B's client reads B's wiki. A product spread over several repos gets one wiki. *What any session learned about a service is there for every session that touches it.*
- **A shared wiki for what holds everywhere:** shared libraries, tools, team conventions. Projects cite it instead of copying it. *A lesson that holds beyond one project is written down once, where every project can find it, and corrected in one place.*
- **One collection for the whole team.** It's a git repo: agents pull, commit and push, the two files every compile touches merge on their own, and a secret scan blocks any commit containing a key or token. *Your teammates' agents learn from yours, safely.*

### Stops the same mistake happening twice

- **Repeated corrections become rules.** When you correct the agent, or reviewers flag the same thing again, it keeps count. After a few times, it proposes a fix, with the evidence: a line in the conventions, a note on how to use a shared library, a team skill, or a small script. Code is checked against the conventions before it's called done. *Review comments stop coming back.*
- **Team skills.** Procedures that keep coming up live in the wikis as Claude skills, shared with everyone who syncs the collection, and linked into Claude Code automatically. *One person works out the steps, and the whole team's agents follow them.*

### Reports on your work

- **Standups, written for you.** "Give me my standup" assembles yesterday, today and blockers from your commits across repos, journal entries, and what the wikis learned. Past days can be filled in from Claude Code's session history. *No more reconstructing yesterday at 9:58.*
- **A weekly report.** Tokens per project, what each wiki gained, how often the wikis answered, and a "needs you" list: open contradictions, unanswered proposals, stale pages. *You can see whether it earns its keep, and what's waiting on you.*

### Watches the token bill

- **Reads little.** An index first, then a handful of short pages. Wiki reads came to about 1% of new input tokens in real use.
- **Hit-rate stats** show which wikis actually answer questions.
- **Hands busywork to cheaper models:** test runs, file sweeps, boilerplate. Design, debugging and review stay on your best model. *Your expensive model's tokens go on the hard parts.*

### Looks after itself

- **Three-step install** as a Claude Code plugin. It runs in the terminal, the desktop app's Code tab and IDEs.
- **Updates on its own.** New versions arrive in the background. When the rules change, your next session upgrades your wikis, commits the upgrade and tells you what changed.
- **Points every session at the right wiki** at startup. Right after a long session is compacted, it asks the agent to save what the summary still holds.
- **Suggests features you haven't tried,** at most one per session, only when your own wikis show a reason. You can mute any of them.
- **A `wiki` command with tab completion** for status, standups, reports, seeding and setup.

### Works with any agent

Everything is plain markdown, in git, readable in any editor. The rules are a handbook any agent can follow, so Codex, Cursor and Copilot work too. The Claude Code plugin adds the automatic parts.

## Start here

| You use | Guide | Time |
|---|---|---|
| Claude Code: in a terminal, the Claude desktop app's **Code** tab, or an IDE | [Set up with Claude Code](docs/claude-code.md), as a plugin | 5 minutes |
| Anything else: Codex, Cursor, Copilot, the desktop app's **Chat** tab, claude.ai | [Set up with another agent](docs/other-agents.md) | 10 minutes |

Joining a team that already shares a collection? Read [Teams](docs/teams.md#join-a-shared-collection) first.

## Then

- [Using it](docs/using.md): what the agent does on its own, what to say, and every feature above in detail.
- [Teams](docs/teams.md): one shared collection for everyone.
- [Troubleshooting](docs/troubleshooting.md)
- [Maintaining the template](docs/maintaining.md): changing the rules, releasing.

## How it works

Each project has a wiki in `~/wikis`, named after its repository. When the session produces something worth keeping, the agent writes a short dated note into that wiki's `raw/` folder. Later, at a pause, it compiles waiting notes into small linked pages and lists them in `index.md`. Every session starts by reading that index, so answers come from compiled pages instead of rereading everything.

The rules the agent follows are a handbook, `AGENTS.md`, copied into each wiki from this repo's `template/`. Any agent and any model can follow it. Nothing depends on one vendor.

This repo is the template, the setup script `wiki.sh`, and a Claude Code plugin. It is not a wiki itself.
