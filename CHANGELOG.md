# Changelog

What changed in each handbook version, written for the person upgrading. `./wiki.sh upgrade` prints the entries newer than the version it upgraded from.

Format: one `## vN (date)` section per version. Lines starting `- ` say what changed. Lines starting `- Do:` say what to do about it. Newest first. Bumping the handbook version means adding a section here.

## v27 (2026-10-30)

Agents can tell you, and llm-wiki's maintainer, what got in their way. It's off until you turn it on.

- `wiki setup feedback` picks one of three: `off`, `notes` (agents keep notes on this machine for you to read) or `share` (the same, and you can file one as an issue on llm-wiki's GitHub after reading it). The notes stay outside the collection, so they never sync to teammates.
- With it on, `wiki start` prints a `Feedback on llm-wiki` section, and the handbook's new `rules/feedback.md` says what's worth a note (a bug, friction, a docs conflict, an idea, each with evidence), at most one per session and never mid-task. Agents save it with `wiki feedback add`.
- `wiki feedback` lists the notes, `show` prints the issue it would file, `send` files it only after you read it and say yes (with `gh`, or a filled-in form in the browser), and `dismiss` drops one. Drafts have paths, emails, git remotes, and the names of your projects and wikis replaced, and `gitleaks` checks them when it's installed. `wiki status` lists notes waiting under To do.
- Do: run `wiki setup feedback` and choose. `share` helps the most; you still read every note before it goes anywhere.

## v26 (2026-10-30)

Each project's own definition of done, and the tools its work needs. Gemini resuming work in a project skipped checks Claude makes, such as CI after a push, because they came from Claude's app, not from the wiki.

- A project wiki's `wiki/conventions.md` takes `## For agents` (the project's procedures) and `## Tools` (one line per tool: `- gh (cli): what it's for`, `- supabase (mcp): ...`). `wiki start` prints both after the shared wikis' sections, and marks each `cli` tool installed or not. Nothing in the page is run.
- The handbook says to follow the project's `For agents` like the shared one, to tell the user when the work needs a listed tool the agent doesn't have instead of skipping the step, and to capture procedures and tools as they're learned. `rules/compile.md` says where they go.
- `wiki setup tools` offers, one tool at a time, to let Claude Code and Antigravity run the command-line tools your wikis list without asking.
- Do: nothing needed. To start, tell a session in a project "record this project's procedures and tools", or add them to its `wiki/conventions.md` yourself, then run `wiki setup tools`.

## v25 (2026-10-29)

A shorter core. Every session reads `AGENTS.md`, so what only some sessions need moved into `rules/`: about 3,000 words became about 2,300.

- "Other wikis" keeps the two rules every session needs, Ownership and Cite, don't copy. Finding peers, shared wikis, lookup by name, search, and missing wikis moved to `rules/peers.md`.
- "Sync" is one paragraph: run `wiki.sh sync` after each compile, never rebase, stash or `--no-verify`. Committing by hand, merge conflicts and refused commits moved to a new `rules/sync.md`.
- "Capture" leads with `wiki.sh capture` (and `--file`), with the by-hand naming rules after it.
- Do: nothing. Sessions upgrade the wikis on their own.

## v24 (2026-10-29)

No more summary page per source. Each raw note used to get a page in `wiki/sources/` that only pointed at the pages it fed: one more file written per note at every compile. The collection had 59.

- A compile records each note in its `log.md` entry instead: `wiki log <wiki> ingest "<title>" --source raw/<file> ...` writes a `- source:` line. A note counts as compiled when a log entry names it, a page lists it in `sources:`, or its old summary page exists. Existing summary pages stay, and nothing needs migrating.
- `rules/compile.md` drops the summary-page step. `wiki pending`, `status`, `lint`, the weekly report and the Claude Code hook all decide "compiled" the same way.
- Do: if you share a collection, update everyone's plugin (or pull everyone's clone) before the next compile. Someone still on v23 decides "compiled" by summary pages, so they would see notes compiled under v24 as waiting and compile them again.

## v23 (2026-10-29)

Session start in one call, and staleness that counts commits. Both from the test with Gemini, which skipped the session-start pull in every run.

- `wiki start` finds the wiki for the folder you're in, pulls the collection, and prints what session start reads: this wiki's index, each shared wiki's index and `For agents` section, and what waits. A failed pull is a warning, not an error. The handbook's session start runs it, and keeps the steps by hand for agents without the script.
- The session line for other agents (`wiki claude --print`) runs `wiki start` instead of `wiki which`.
- `wiki stale` and `wiki lint` also report a page whose `commit` is 50 or more commits behind its repository, a commit the repository doesn't have, and a bare hash in a wiki that covers several repositories. They find repositories under the journal's `code_dirs`. Without a clone, days still apply.
- With Antigravity installed, `wiki setup` offers an llm-wiki plugin for it: a rule naming the wikis, a SessionStart hook that runs `wiki start` and gives the conversation its output, and the llm-wiki skill. `wiki capture --file` reads a note from a file, so agents can capture without a pipe or heredoc. `delegation.md` names Gemini's tiers next to Claude's.
- Do: run `wiki setup --new`. It updates the session line in `~/.claude/CLAUDE.md`, and with Antigravity installed it offers the plugin; quit and reopen Antigravity once after adding it. If you put the session line in another agent's file, such as `~/.codex/AGENTS.md`, replace it with the new output of `wiki claude --print`.

## v22 (2026-10-29)

From the first test with an agent other than Claude (Gemini in Antigravity) and its review of this repo.

- `rules/compile.md` names `wiki index`, which writes index lines from each page's summary, and `rules/lint.md` says to run `wiki lint` first for the mechanical checks.
- `wiki lint` also reports `sources:` entries whose file in `raw/` doesn't exist.
- `wiki find` also searches page text, so an identifier or error string that no summary mentions still finds its page. The handbook's query steps use it before searching `raw/`.
- An accepted pattern seen again after its accepted date is marked `AGAIN` in `wiki patterns`, counted in `wiki status`, and listed in the weekly report: the fix isn't working.
- `wiki status` and `wiki pending` say when they can't read a wiki's `raw/`, as inside an agent's sandbox, instead of reporting nothing waiting.
- Do: nothing. Sessions upgrade the wikis on their own. If you run an agent in a sandbox, allow `~/wikis` there.

## v21 (2026-10-28)

Fitting in with real setups, from a review of two weeks of use.

- Status pages, such as work in progress or open questions, carry an `as_of` date and are rewritten when the state changes, not appended to.
- A newer version of a captured document supersedes the older one at compile, instead of both being merged.
- About people, wikis keep only role, ownership, and how to work with them.
- Reports and standups follow the user's own reply style where it differs from the default shapes.
- The session hook gives sessions the plugin's stable `wiki` command, not a path that changes with every update. `wiki which` suggests close matches and the `wiki cover` fix. `/llm-wiki:save` also writes the session's journal lines.
- `wiki setup` tries your normal SSH before asking for a key, and explains a failed push test: an https remote, a key that wasn't accepted, a blocked port, or a missing repository.
- Do: nothing. Sessions upgrade the wikis on their own.

## v20 (2026-10-28)

Commands for the mechanical parts of capturing and compiling. A review of two weeks of real use found agents rounding capture times, skipping the `Captured:` line, and spending dozens of shell calls on locks, log entries and pulls, which also failed on a dirty collection.

- `wiki capture <wiki> <slug>` saves a note piped on stdin, named from the clock and never overwriting, with the `Captured:` line added. `--copy FILE` stores a document unchanged.
- `wiki lock <wiki>`, `--release` and `--renew` run the compile lock.
- `wiki log <wiki> <type> [title]` appends a well-formed `log.md` entry and prints its counts.
- `wiki sync <wiki>` commits only that wiki's folder, pulls with a merge, and pushes. A rebase-pull failed whenever another wiki had uncommitted notes, so the handbook now says to pull with a merge, never a rebase or a stash.
- `wiki delegation log` records a handoff, and `wiki journal backfill --done` removes the digest, which an agent's own delete could be refused.
- The handbook names each command, and keeps the steps by hand for agents without the script.
- Do: nothing. Sessions upgrade the wikis on their own.

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
