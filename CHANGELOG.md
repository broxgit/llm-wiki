# Changelog

What changed in each handbook version, written for the person upgrading. `./wiki.sh upgrade` prints the entries newer than the version it upgraded from.

Format: one `## vN (date)` section per version. Lines starting `- ` say what changed. Lines starting `- Do:` say what to do about it. Newest first. Bumping the handbook version means adding a section here.

## v19 (2026-10-28)

Knowledge that holds beyond one project now reaches every project. Audits of two collections found general lessons stuck in project wikis, sessions that rarely opened the shared wiki, and corrections saved to the agent's own memory, where no other repository could see them.

- Every session reads the shared wiki's index, and the `For agents` section of its conventions page, at session start, not only when its own wiki can't answer.
- Before each capture, the agent asks whether another repository needs it. If so, it goes in the shared wiki or the owning wiki. The handbook now lists what belongs in the shared wiki: how you want agents to work, how shared libraries, internal tools and vendors behave, pipelines and environments, team practice, and guild decisions.
- Knowledge goes in the wiki, not in the agent's own memory, which only reaches sessions in one folder. The plugin's session hook repeats this every session.
- The shared wiki gets `wiki/conventions.md`, with `For agents` (working agreements) and `For code` sections. Setup and upgrade create it. Repeated corrections about how agents work land there.
- Compile looks for a topic in other wikis before starting a page. Lint reports duplicated facts, stale copies after a rename, broken cross-wiki citations, project pages whose lesson holds elsewhere, and shared pages that lean on one project.
- A session that finds its wiki some other way than by name runs `wiki cover`, so the next one finds it by name.
- The weekly report counts recorded corrections, and flags a busy week with none.
- Do: nothing. Sessions upgrade the wikis, and the upgrade creates the conventions page. Then fill in its `For agents` section with your working agreements, or ask a session to.

## v18 (2026-10-28)

- Bulk compile. Five or more waiting notes, as after `wiki seed`, are compiled as one batch: read together, planned by topic, and each page written once, instead of rewriting the same page once per note.
- `wiki pending <wiki> --show` prints a wiki's waiting notes in one go, so an agent reads twenty documents in one step. `wiki pending` lists what waits in every wiki.
- With more than ten notes waiting, a session does what you asked first and compiles at the next pause, instead of making you wait.
- Do: nothing. Sessions upgrade the wikis on their own.

## v17 (2026-10-28)

- Team skills. When a repeated procedure becomes a skill, it now lives in the wiki that owns it, as `skills/<name>/SKILL.md`, instead of in one person's `~/.claude/skills`. Everyone who syncs the collection gets it, and a fix reaches everyone.
- `wiki skills` lists them. `wiki skills link` links them into `~/.claude/skills` for Claude Code. The plugin links new ones at every session start, and `upgrade` and `setup` link them too. A skill of yours with the same name is left alone.
- Skills keep the steps and cite wiki pages for facts, so a corrected page corrects the skill. Each wiki's index lists its skills, so other agents can follow them as how-tos.
- `wiki seed` also takes a repository's agent instructions (`CLAUDE.md`, `AGENTS.md`, Cursor and Copilot rules) and its `.claude/skills/`.
- Do: nothing. Sessions upgrade the wikis on their own. To share a skill you already have, move its folder into `~/wikis/global/skills/` or a project wiki's `skills/`, then run `wiki skills link`.

## v16 (2026-10-28)

- Hit-rate stats. Agents log one line per question they check a wiki for, `hit` or `miss`, to `stats.csv` in the collection. It stays on each machine. `wiki stats` shows each wiki's hit rate, so you can tell which wikis earn their keep.
- `wiki seed [<repo>]` starts a wiki from a repository's own docs: its README, top-level guides, `docs/`, and decision records. It copies them into `raw/`, with a note saying where they came from, and the next session compiles them. With the plugin, a session in a repository with no wiki offers to do this.
- With the plugin, a session that was just compacted is asked to capture what the summary holds that the wiki doesn't.
- `wiki standup` lists at most 15 commits per repository, newest first, and says how many it left out. The `max_commits` journal setting, or `--max`, changes it. Detailed reports list them all.
- Do: run `wiki upgrade --all`. It also adds `stats.csv` to the collection's `.gitignore`.
- Do: run `wiki setup --new` to see the new `max_commits` setting.
- Do: in a repository whose wiki is empty or missing, try `wiki seed`.

## v15 (2026-10-28)

- Secret scan. A pre-commit hook runs `gitleaks` over every commit to the collection, or to a wiki that is its own repo, and refuses one that holds a key, token or password. `init --git`, `new --git`, `upgrade` and `setup git` install it. A wiki inside a project's repo never gets it.
- When a commit is refused, agents replace the secret with `[REDACTED]`, even in `raw/`, commit again and tell you. A false positive needs your OK: add its fingerprint to `.gitleaksignore` at the top of the repo.
- An existing pre-commit hook, or a `core.hooksPath` setting, is left alone. Upgrade says how to call the scan from yours.
- Without `gitleaks` the hook lets commits through with a warning. `./wiki.sh status` says when commits aren't scanned.
- Do: install gitleaks (`brew install gitleaks`), then run `./wiki.sh upgrade --all`.

## v14 (2026-10-28)

For collections shared by a team, or by one person on several machines.

- Two people compiling the same wiki no longer stop on a git conflict in `index.md` or `log.md`. Each wiki's new `.gitattributes` tells git to keep both sides' lines. Lint now reports an index line left twice by such a merge.
- `delegation.md` is git-ignored, like its log. It holds one person's preferences, and in a shared collection coworkers were overwriting each other's mode.
- `./wiki.sh status` flags a wiki whose handbook is newer than your template, as happens when a coworker upgrades a shared wiki first. `upgrade` leaves such a wiki alone and tells you to pull the template.
- Do: run `./wiki.sh upgrade --all`. It adds `.gitattributes` to every wiki and `delegation.md` to the collection's `.gitignore`.
- Do: if upgrade says the delegation files are tracked from before, run the `git rm --cached` command it prints, then commit. Each machine keeps its own copy.

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
