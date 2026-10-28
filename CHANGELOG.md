# Changelog

What changed in each handbook version, written for the person upgrading. `./wiki.sh upgrade` prints the entries newer than the version it upgraded from.

Format: one `## vN (date)` section per version. Lines starting `- ` say what changed. Lines starting `- Do:` say what to do about it. Newest first. Bumping the handbook version means adding a section here.

## v13 (2026-10-28)

- Fix: a wiki an agent creates by hand for another repository now gets `patterns.md`, as `wiki.sh new` already did. `rules/peers.md` was missing that step.
- `wiki.sh new` refuses names with spaces or characters a repository name can't have, and resolves `..` in paths. `wiki.sh find` no longer matches index headings.
- Do: run `./wiki.sh upgrade --all`. It also adds `patterns.md` to any wiki that lacks one.

## v12 (2026-10-27)

- Delegation. Sessions hand large, self-contained work whose results can be checked, like test runs, file sweeps and boilerplate, to sub-agents on cheaper models. Design, debugging and review stay in the session.
- `~/wikis/delegation.md` holds your preferences: a mode (`off`, `ask`, `auto`), a table of which kind of work goes to which model and effort, and an Auto list of kinds approved without asking. The default is `ask`.
- After you approve the same kind of handoff three times, the session offers to add it to the Auto list. Each handoff is logged, and `./wiki.sh delegation` shows how often each kind needed fixing or redoing.
- The session line in `~/.claude/CLAUDE.md` now points every session at `delegation.md`.
- Do: run `./wiki.sh setup --new` to pick a mode and refresh the session line. Edit the table in `~/wikis/delegation.md` to match the models you use.

## v11 (2026-10-27)

- Repeat feedback becomes a fix. When you correct an agent, paste review comments on code it wrote, or it repeats a procedure or mechanical work, the agent records a `Feedback:` line. Compile tallies them in each wiki's `patterns.md`.
- When a pattern repeats (3 times, or twice in review comments or across repositories), the agent proposes a fix once, with the evidence: a convention, a note in a shared library's wiki, a skill, or a small script.
- Agents check code against the conventions pages that apply before calling it done: the project's, the shared wiki's, and those of the internal libraries it calls.
- `./wiki.sh patterns` shows every wiki's patterns and which are ready. `./wiki.sh status` flags `pattern(s) ready`.
- Do: paste merge request review comments into the session that wrote the code. That is the evidence that stops the same comment coming back.

## v10 (2026-10-22)

- Journal backfill. `./wiki.sh journal backfill --since 14d` digests your past Claude Code sessions into `journal/backfill.md`. Ask an agent to "backfill my journal" and it writes entries for those days, then deletes the digest.
- `./wiki.sh journal note` takes `--day` and `--at`, so entries can go on past days.
- Do: to fill in the last two weeks, run `./wiki.sh journal backfill`, then ask an agent to backfill your journal.

## v9 (2026-10-22)

- Work journal. Agents add one line per stopping point for work that leaves no commit: an investigation, a review, a dead end.
- `./wiki.sh standup` gathers your commits, journal lines, wiki notes, work in progress, and open checks. Ask an agent "what did I do yesterday" and it writes the standup.
- The journal is on by default and stays on this machine. It is never committed unless you set `commit=yes`.
- Do: pick the journal settings with `./wiki.sh setup journal`, or turn it off with `./wiki.sh journal off`.

## v8 (2026-10-07)

- Compile now runs at session start and whenever five notes are waiting, not only at a pause. Backlogs clear on their own.
- Agents capture less: decisions, direction, and what the code doesn't show. Finished work is no longer a capture.
- Lint runs on its own after 10 ingests.
- Timestamps come from the clock, never estimated. Wiki changes are committed once per compile, with messages starting `<wiki>:`.
- `./wiki.sh status` flags `compile due` and `lint due`.

## v7 (2026-10-01)

- A wiki covers a project, not a repository. A project with several repositories lists them in `repos.md`.
- `./wiki.sh cover <wiki> <repo>...` records that, and `./wiki.sh which <repo>` finds the wiki for a repository.
- Do: run `./wiki.sh claude` again. The session line changed so sessions look wikis up with `which`.
- Do: for a project split across several wikis, pick one, `cover` the other repositories, and ask an agent to move the pages.

## v6 (2026-09-30)

- The handbook split into a short core that loads every session and `rules/` files read on demand. Each session loads about a third less.
- Pages carry `verified` and `commit` stamps. Agents check a claim against the code before acting on it and file a correction when it no longer holds.
- `./wiki.sh stale` lists pages not verified in a while.
