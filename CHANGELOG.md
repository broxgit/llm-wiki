# Changelog

What changed in each handbook version, written for the person upgrading. `./wiki.sh upgrade` prints the entries newer than the version it upgraded from.

Format: one `## vN (date)` section per version. Lines starting `- ` say what changed. Lines starting `- Do:` say what to do about it. Newest first. Bumping the handbook version means adding a section here.

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
