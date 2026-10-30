# Roadmap

Potential improvements to the wiki template, in rough order of payoff. Work from the top of Next. When an item is finished, move it to Done with the date and what changed.

Each item says why it matters, a sketch of how, and what is still undecided.

## Next

### Terse page style

- **Why:** agents read pages far more often than people do. Measured on one sample page, terse notes in plain words used 56% of the tokens of default prose. The body alone used 45%.
- **Sketch:** a style rule in `rules/compile.md`. One fact per line. Fragments over sentences. No narrative, no restating. Plain words, identifiers verbatim. Then trim frontmatter, which is nearly half of a terse page: cite sources by timestamp prefix, and drop fields that repeat each other.
- **Not this:** invented abbreviations or JSON. In the same test, shorthand saved 2 points over terse plain words and JSON saved none. Abbreviations cost more tokens per word ("tmo" is 2 tokens, "timeout" is 1) and are harder for a model to read back.
- **Open:** whether terse pages hurt answer quality. Test by asking the same questions against both versions of a page. Whether teammates still need to read pages comfortably.

### Know whether sessions capture and compile

- **Why:** `wiki stats` measures lookups only. Saving and compiling are the parts that failed in the first week (50 of 109 notes never compiled), and nothing measures them now.
- **Sketch:** `wiki status` flags a wiki whose repository has commits in the last two weeks but no new notes in that time.
- **Open:** wait for two weeks of `wiki stats` first. It may not be needed.

## Later

- **Merge requests in standups.** Reviews and MRs opened live in GitHub or GitLab, not in git history. Pulling them in would need an API token and a host per remote.
- **Backfill from more places.** The desktop app's Chat tab and claude.ai aren't on disk, so they're out of reach without an agent that has chat search. (The desktop Code tab is in `~/.claude/projects`, and Gemini's Antigravity conversations are read since 2026-10-29.)
- **Team digest.** A weekly roll-up across several people's journals, for a lead. Needs a shared, opt-in journal location.
- **Reach sessions with no file access.** A chat session that can't read files can't use a wiki. A small MCP server over the collection would fix that.
- **Review flow for teams.** Agents push straight to the collection. A team may want a weekly digest of changes, or pull requests.
- **Obsidian.** Add `.obsidian/` to the template's `.gitignore` if anyone opens wikis as vaults.

## Untested

Things that have never been run for real. Treat them as unproven until crossed off.

- `wiki.sh unlock` and `claude` on macOS. `setup` and `journal backfill` have since run on Macs in real use (2026-10-28 and 2026-10-29); every other command ran cleanly on macOS (bash 3.2, BSD `date`) on 2026-10-28.
- `wiki.sh journal backfill` on transcripts from Claude Code versions other than the one it was written against. It needs `python3`.
- Git sync between two people or two machines. Pull, commit, and push from one machine worked in real use on 2026-10-01.
- Two sessions taking the compile lock in the same second.
- A wiki with two shared wikis listed in `links.md`.
- Real scale: hundreds of wikis, hundreds of pages. Real use so far is 10 wikis and 53 pages.
- The version 8 triggers in real use. They passed a dry run only.
- Agents other than Claude pulling at session start, and syncing. Gemini in Antigravity and Codex pull through their plugins' hooks; Codex's and Cursor's sandboxes block writes to `~/wikis/.git`, so `wiki sync` there, and Cursor's `wiki start`, run outside the sandbox. Copilot is still untried.
- Delegation in real use: whether sessions suggest handoffs at the right size, and whether the log shows real savings. The log records outcomes, not tokens. Token counts per handoff would need the tool's usage data.
- Stats in real use: whether sessions log every lookup, and what hit rate means a wiki should go.
- Seed in real use: how long compiling 20 seeded documents takes, and whether the pages are worth it.
- `scripts/migrate-to-plugin.sh` and the interactive parts of `wiki setup` in CI. Both ran by hand in fake homes on 2026-10-28; CI only shellchecks the script. Testing them needs a pseudo-terminal that works on Linux and macOS runners.
- The plugin's data folder name. Docs hard-code `~/.claude/plugins/data/llm-wiki-llm-wiki`, seen on three machines. A fork under another marketplace name gets a different folder.
- Sessions upgrading wikis on their own (plugin, 2026-10-28): whether they pull before upgrading, and two machines upgrading one shared collection at once.
- Tips in real use: whether people act on them or mute them all. Look at the mutes after a few weeks and drop the tips everyone mutes. Usage before 2026-10-28 wasn't recorded, so early standup and find tips may point at features already used.
- Bulk compile in real use: how long twenty seeded documents take, and whether planning by topic gives better pages than one at a time. No agent has run it yet.
- The weekly report in real use: whether people ask for it, and whether the token estimate for wiki reads is close enough to be useful.
- Shared knowledge in real use: whether sessions now file general lessons in the shared wiki, and whether they stop saving to their own memory. The weekly report's correction count is the first signal. Whether harvested notes get filed in the right wiki at compile.
- Capture after compaction in real use: whether sessions capture before answering when the user's message arrives with the hook's message. On 2026-10-28 one session answered first and captured a turn late, which led to the "before you answer anything" wording. Watch for raw notes timed just after a compaction.
- Cursor's own sessionStart hook (`wiki setup cursor`) in a live session without the Claude Code plugin: whether Cursor runs it outside its sandbox, so the pull works.
- Codex's PostCompact hook in a live session. The smoke tests cover its reply; no Codex session has compacted with it yet.
- Patterns in real use: whether agents write `Feedback:` lines unprompted, and whether the thresholds are right.

## Decided against

- **Embeddings or a vector database.** Lookup by repository name plus keyword search covers the need. Embeddings also tie the data to one embedding model.
- **A custom UI.** Obsidian and GitHub already render markdown.
- **More scaffolding automation.** Setup is one command.

## Done

### Cursor (2026-10-30)

- **Why:** Cursor runs the Claude Code plugin from Claude Code's own installed copy, which on a directory marketplace can sit days behind. Cursor users without Claude Code got only a pasted user rule: no pull outside the sandbox, no wiki loaded at start.
- **What changed:** `wiki status` says when an installed llm-wiki plugin copy is behind its marketplace, which both Claude Code and Cursor run. `wiki setup cursor` adds a sessionStart hook to `~/.cursor/hooks.json` that runs `wiki start` and replies with `additional_context`, prints the user-rules line, and links the skills into `~/.cursor/skills`. With the Claude Code plugin installed, the hook replies with nothing, so the brief never arrives twice. No compaction hook: Cursor has none after compaction, and its preCompact reply reaches only the person.

### Collections whose branch doesn't track the remote (2026-10-30)

- **Why:** `wiki setup git` adds `origin` but never set the branch's upstream. On a teammate's machine `wiki update` failed with "There is no tracking information for the current branch", and `wiki start` and `wiki sync` pulls fail the same way.
- **What changed:** `start`, `sync` and `update` now set the upstream to origin's branch of the same name when it's missing. When origin has no such branch yet, `start` says the next sync pushes to it, and `sync` and `update` make that first push with `-u`.

### Codex plugin (2026-10-30)

- **Why:** Codex has a plugin system and hooks in Claude Code's shape, but used only a pasted session line: no pull outside its sandbox, no wiki loaded at start, nothing after compaction.
- **What changed:** `wiki setup codex` writes a local marketplace with an llm-wiki plugin to `~/.codex/llm-wiki` and installs it. Its SessionStart hook runs `wiki start` and hands the output to the session; its PostCompact hook says to capture before answering. The hooks call the stable `wiki` command, so they don't change with updates and Codex asks to trust them only once. The rule goes in `~/.codex/AGENTS.md`, replacing the session line, and the skills are linked into `~/.codex/skills`. `setup --list` and `setup --new` know about it. Tested live on 2026-10-30: once trusted, a Codex session got the brief, the pull ran outside the sandbox, and Codex answered from the brief without running `start` again.

### Fixes from the Codex and Cursor tests (2026-10-30)

- **Why:** `docs/agent-test.md`, run by Codex and Cursor, found bugs the Gemini test hadn't.
- **What changed:** a read-only command no longer fails when it can't record its own use. Messages name the path `wiki.sh` was run by, not `./wiki.sh`, so agents copy commands that work. `wiki sync` takes a lock for the whole collection, so two sessions' syncs take turns. When a pull would overwrite uncommitted local copies of incoming files, sync sets aside the identical ones and pulls again, and stops on the rest, never resetting. `wiki start` and `sync` say when a sandbox is the likely cause of a failed pull. `wiki update` on a clone also refreshes an installed plugin's cached copy, whose hook other agents may load. `docs/agent-test.md` is the protocol; `docs/other-agents.md` covers Codex and Cursor.

### `wiki update` (2026-10-30)

- **Why:** an update took a plugin command, a pull, an upgrade per collection, a push and `setup --new`, by hand on each machine; a script for it broke on `wiki collections`' hint line.
- **What changed:** `wiki update` updates the plugin, or pulls the clone, then `exec`s the new version for the rest, so the old script never reads a file that changed under it. The new version pulls, upgrades and pushes each collection, runs `setup --new` at a terminal, and ends with what's left: restarting the Claude app and Antigravity, and the line to paste into open sessions. `upgrade` prints that line too. `wiki collections` writes its hint to stderr.

### Handbook version 26: each project's procedures and tools (2026-10-30)

- **Why:** an agent resuming another agent's work skipped checks, such as CI after a push, that came from the other agent's app rather than from the wiki. And nothing said which tools or MCP servers a project's work needs.
- **What changed:** a project wiki's `wiki/conventions.md` takes `## For agents` and `## Tools` (`- <name> (<cli|mcp|other>): what it's for`). `wiki start` prints both after the shared wikis' and marks each `cli` tool installed or not; nothing in the page is run. The handbook says to follow the project's procedures like the shared ones, to tell the user when a listed tool is missing instead of skipping the step, and to capture procedures and tools as they're learned. `wiki setup tools` offers allow rules for the listed command-line tools in Claude Code and Antigravity, one at a time.

### Gemini's tokens in the weekly report (2026-10-29)

- **Why:** the report counted Claude Code's tokens only, so a week's work in Antigravity was invisible in it.
- **What changed:** with Antigravity installed, `wiki report` adds a "Tokens (Gemini in Antigravity)" table from each transcript step's `input_tokens`, `cache_read_tokens` and `output_tokens`, with an estimate of wiki reads. A conversation counts toward the project its file paths and `git -C` folders point at most. It's a separate table, since the models count tokens differently and are priced differently.

### Work and personal collections (2026-10-29)

- **Why:** one collection on a personal remote held work, client and personal wikis together.
- **What changed:** `~/.config/llm-wiki/collections` lists collections besides `~/wikis`: a name, a folder, and rules that match a repository's folder or remote URL. Every command, `wiki start`, the Claude Code hook and the Antigravity plugin use the collection for the repository at hand; `--collection NAME` picks one by name; `wiki collections` lists them; `status` mentions notes waiting in the others; `WIKIS_DIR` still overrides. `wiki setup collections` adds one and creates it with its shared wiki. Moving existing wikis stays a person's step.
- **Open:** the session line for other agents and the Antigravity plugin's rule name the collection they were written from; each session's `wiki start` output names the right one.

### Handbook version 25: a shorter core (2026-10-29)

- **Why:** every session reads `AGENTS.md`, about 3,000 words, though finding peers and committing by hand matter only some of the time.
- **What changed:** about 2,300 words now. "Other wikis" keeps Ownership and Cite, don't copy; the rest moved to `rules/peers.md`. "Sync" is one paragraph around `wiki.sh sync`; the by-hand steps, conflicts and refused commits moved to a new `rules/sync.md`. "Capture" leads with `wiki.sh capture`. Terse page style, still in Next, would cut further once tested.

### Dependency map (2026-10-29)

- **Why:** an agent changing a shared package couldn't tell which of your repositories use it, or which repository owns a package it saw imported.
- **What changed:** `wiki deps` reads `go.mod`, `package.json` and `pyproject.toml` (three folders deep, skipping nested repositories, `node_modules` and `vendor`) in the repositories under `code_dirs`. It lists which repository owns each package, and which of your repositories use another's. A Go import counts toward the module that contains it. By default it covers only repositories a wiki in the collection covers, so another context's repositories don't leak in; `--all` takes them all, and `exclude` still applies. `--write` saves `data/dependencies.csv` in the shared wiki, with the columns kind, repo, ecosystem, package, owner and file.

### Backfill reads Gemini's Antigravity conversations (2026-10-29)

- **Why:** work done in Antigravity never reached the journal, so standups missed it.
- **What changed:** `wiki journal backfill` also digests `~/.gemini/antigravity/brain/*/…/transcript_full.jsonl`. A conversation doesn't record its workspace, so it goes under the project its file paths and `git -C` folders point at most. The digest marks how many sessions were Gemini's, with the user's prompts, files written or edited, a commit or `wiki.sh sync`, and the last reply. On 2026-10-29 it filed 8 conversations under workout-app, llm-wiki and global correctly.

### Antigravity grants for llm-wiki (2026-10-29)

- **Why:** Gemini asked before every wiki file it read and every `wiki.sh` command it ran, because Antigravity grants one path or command at a time unless told otherwise.
- **What changed:** `wiki setup antigravity` offers grants in `userSettings.globalPermissionGrants.allow` (`~/.gemini/config/config.json`, where "Always allow" writes): read and write `~/wikis`, read the template, and `command(wiki.sh)` in both spellings. Folder grants cover everything under them. Setup checks the list is where expected before writing, keeps a backup, and adds nothing beyond llm-wiki's own needs. `wiki permissions` prints them; `setup --list` and `--new` report missing ones.

### Allow rules for the wiki commands (2026-10-29)

- **Why:** the handbook has agents commit and push the wikis with `wiki sync`, but Claude Code's auto mode stops a push and asks, and a session can't grant itself the permission. A v24 compile in one wiki ended with its changes uncommitted.
- **What changed:** `wiki setup` (or `setup permissions`) offers allow rules in `~/.claude/settings.json` for `start`, `capture`, `lock`, `log`, `index` and `sync`, in each spelling sessions use: the plugin's stable command or the clone's script, with `~` and in full, and plain `wiki`. It merges with what's there and keeps a backup. `wiki permissions` prints them for pasting. Adding them stays a person's step at a terminal on purpose: there is no non-interactive way for a session to add them.

### Handbook version 24: no summary page per source (2026-10-29)

- **Why:** each raw note got a page in `wiki/sources/` that only pointed at the pages it fed, 59 in the collection, one more write per note at every compile. Gemini's review proposed dropping them.
- **What changed:** `wiki log --source raw/<file>` records the note in its ingest entry. One check decides "compiled" everywhere (`pending`, `status`, `lint`, the report, the Claude Code hook): a log entry names it, a page lists it in `sources:`, or its old summary page exists, so existing wikis need no migration. `compile.md` drops the summary step. Risk noted in the CHANGELOG: a teammate still on v23 would compile v24 notes again.

### Handbook version 23: `wiki start`, and staleness in commits (2026-10-29)

- **Why:** Gemini skipped the session-start pull in every run, and session start took five or six calls without the plugin's hook. `lint.md` asked for pages far behind their repository's HEAD, which no command checked.
- **What changed:** `wiki start` finds the wiki, pulls with a timeout and the collection's own SSH command, and prints the indexes, `For agents` and what waits. A failed pull is a warning. The handbook's session start and the session line for other agents run it. With Antigravity installed, `wiki setup` adds an llm-wiki plugin whose SessionStart hook runs `wiki start` and hands its output to the conversation, as Gemini proposed after checking Antigravity's own docs. `capture --file` lets agents capture without a pipe or heredoc. `stale` and `lint` count commits behind for pages with a `commit` stamp, report commits a repository doesn't have, and bare hashes in wikis over several repositories, using clones under `code_dirs`.

### Handbook version 22: mechanical checks named, and Gemini's review (2026-10-29)

- **Why:** the handbook didn't name `wiki index` or `wiki lint` yet, and Gemini's review of the repo found checks the handbook asked for that no command did.
- **What changed:** `compile.md` and `lint.md` name `wiki index` and `wiki lint`. `lint` checks `sources:` files. `find` searches page text after index lines. `patterns`, `status` and the report flag an accepted pattern seen again (`AGAIN`). `status` and `pending` with no wiki say when a sandbox hides `raw/`.

### A model other than Claude: Gemini in Antigravity (2026-10-29)

- **Why:** the handbook says it needs no vendor features, and this had never been checked.
- **What changed:** Gemini 3.8 Flash in Antigravity ran a scripted test in a real repository: lookups, checking a page against code, captures, a correction, off the record, compile, sync, and recall in a fresh conversation. It followed the handbook apart from the session-start pull, and found three bugs: the session line didn't say where `wiki.sh` is (PR 19), `capture` reported success on a failed write (PR 20), and `pending` reported nothing waiting when it couldn't list `raw/` (PR 21). `docs/other-agents.md` now covers `~/.gemini/GEMINI.md`, sandboxes, and grading a run from its transcripts.

### `wiki index` and `wiki lint` (2026-10-28)

- **Why:** real use showed 45 shell edits to `index.md` and a throwaway lint script in two weeks.
- **What changed:** `wiki index` updates `index.md` in place from the pages' frontmatter: it refreshes lines, adds missing pages under their category, and drops lines for missing pages and duplicates, keeping the index's own order and headings. It lists every line it changes, so a better index line isn't silently replaced by a stale page summary. `--check` exits 1 when out of step. `wiki lint` reports the mechanical checks across one wiki or all of them, in under half a second for 13 wikis, and changes nothing. The handbook doesn't name them yet: see Next handbook release.

### Fitting real setups (2026-10-28, handbook version 21)

- **Why:** the same review of real use, plus a coworker's failed push test.
- **What changed:** the session hook gives sessions the stable `wiki` command; `which` suggests close matches and the `cover` fix; setup tries normal SSH before asking for a key, and explains push-test failures (https remote, refused key, blocked port, missing repository); reports and standups follow the user's reply style; `/llm-wiki:save` writes journal lines. Handbook v21: status pages carry `as_of` and are rewritten, newer versions of a document supersede older ones, and wikis keep only role and ownership about people. Docs: living with lint hooks, commit rules and commit-message skills; troubleshooting for a failed pull, a failed push test, a refused delete, and a repo under another name; one handbook version a day at most.

### Bookkeeping commands (2026-10-28, handbook version 20)

- **Why:** a review of two weeks of real use found the handbook's by-hand bookkeeping going wrong. In one collection: 61 `date -u` calls to name captures, 13 names rounded to `:00` and 9 with no time, 26 of 73 notes without `Captured:`, 58 shell calls on locks, and a rebase-pull that refused to run while another wiki had uncommitted notes. A digest delete was also refused by a safety check.
- **What changed:** `wiki capture`, `wiki lock`, `wiki log`, `wiki sync`, `wiki delegation log` and `wiki journal backfill --done`. The handbook names each one and keeps the steps by hand. Pulls are merges, never rebases or stashes.

### Harvest Claude Code memory, and two setup fixes (2026-10-28)

- **Why:** the work machine's audit found corrections and working rules saved to Claude Code's per-folder memory, 31 notes in 9 folders, where no other repository or teammate sees them. This machine had 60 in 6.
- **What changed:** `wiki harvest` copies memory notes into the wikis' `raw/`. `user` and `feedback` notes go to the shared wiki, project and reference notes to the wiki of the folder they were saved in (found from that folder's transcripts), and the rest to the shared wiki. A manifest per wiki says where each came from. Identical notes are skipped on rerun, and the memory itself is never touched. A tip points at it when memory has notes newer than the last harvest. Fixed: `wiki setup --new` never asked about tab completion, and `wiki upgrade` didn't commit collection changes such as the anchored ignore rules when no wiki was behind. Also found while testing: bash 3.2 treats an empty array as unbound under `set -u`.

### Shared knowledge reaches every project (2026-10-28, handbook version 19)

- **Why:** audits of two collections found general lessons stuck in project wikis (12 on one machine), sessions that opened the shared wiki only to write to it, no conventions pages anywhere, and zero `Feedback:` lines. The work machine's transcripts showed 11 corrections, 9 of them global, saved to Claude Code's own per-folder memory, which no other repository loads.
- **What changed:** sessions read the shared index and its conventions page's `For agents` section at start. Every capture asks whether another repository needs the item. The Ownership rule lists what belongs in the shared wiki, and "when unsure, keep it here" became a question about whether another repository's session would act differently. Knowledge goes in the wiki, not the agent's memory, and the hook repeats it. Setup and upgrade create the shared conventions page. Compile searches other wikis before starting a page. Lint reports duplicates, stale copies, broken cross-wiki citations, and lessons stuck in a project. Sessions that find a wiki indirectly run `wiki cover`. The weekly report counts corrections and flags a busy week with none.

### Tab completion (2026-10-28)

- **What changed:** `wiki completion zsh|bash` prints a small script that asks `wiki __complete` for candidates on every Tab: commands, wiki names, journal settings and their values, tip names, ranges, and folders for `seed`. `wiki setup` writes it to `~/.config/llm-wiki/` and adds one line to the shell profile, after asking. The candidates live in `wiki.sh`, so updates can't leave completion stale. Found while testing: bash 3.2 joins `"${COMP_WORDS[@]:1}"` into one word when `IFS` is a newline, so the script sets `IFS` only afterwards.

### Weekly report, and two fixes it found (2026-10-28)

- **Why:** to show whether the wikis earn their keep, and to gather what waits on a person into one weekly list instead of more nudges.
- **What changed:** `wiki report` builds the material from data already on disk: tokens per project from Claude Code's transcripts (each reply counted once, though a multi-part reply is recorded several times; scratch folders count toward their project), the estimated share spent reading wikis, what each wiki captured and compiled, hit rates, and a Needs you list. The session hook offers it once a week, and skips that week's tip. On this machine's real week: 33 sessions, 102.7M new input tokens, 5.4B cache reads, and wiki reads about 1.4% of new input.
- **Found while building it:** a session had upgraded every wiki to v18 but never committed, so 39 files sat uncommitted. `wiki upgrade` now commits its own changes, only the files the handbook owns, and leaves a wiki's other uncommitted work alone. And since v14 the collection's `.gitignore` said `delegation.md` unanchored, which also hid every wiki's `rules/delegation.md` in collections made after v14. The patterns are now anchored with `/`, and upgrades rewrite old ones.

### Bulk compile (2026-10-28, handbook version 18)

- **Why:** `wiki seed` can leave 20 documents waiting, and a session compiled them one at a time, rewriting the same topic page once per document, before it got to what the person asked.
- **What changed:** with five or more waiting, `rules/compile.md` has the session read them together, plan pages by topic, write each page once, then write the per-file summary pages. `wiki pending <wiki> --show` prints the waiting files in one call, up to about 150KB, and says when more wait. Seeded files get their own note: read the manifest first, and treat their code claims as unchecked. With more than ten waiting, a session does the person's request first and compiles at the next pause; the hook says so.

### Tips: features your wikis suggest (2026-10-28)

- **Why:** most features, like seed, standup, stats, team skills and backfill, are invisible unless someone reads the docs, so they risked going unused.
- **What changed:** `wiki tips` checks the person's own records for a reason to use each of eight features: a repository with docs but no wiki, skills only on this machine, journal entries but no standup, a young journal with older transcripts, two weeks of lookups, pages unchecked for 90 days, several wikis but no `find`, and delegation never used. The plugin's session hook passes on at most one per session, to mention at a stopping point, never right after compaction or during an upgrade. A shown tip rests 14 days, a muted one for good, and a used feature's tip stops. `wiki status` counts them. State is per machine in `~/.config/llm-wiki/tips`. It ran in 0.13 seconds on a 13-wiki collection.

### Team skills, and seed takes agent instructions (2026-10-28, handbook version 17)

- **Why:** a skill that came out of a repeated procedure landed in one person's `~/.claude/skills`, so the rest of the team never got it, and nothing kept it current. And `wiki seed` skipped `CLAUDE.md`, `AGENTS.md` and a repository's skills, often its best-kept guidance.
- **What changed:** skills live in the owning wiki as `skills/<name>/SKILL.md`, listed in its index. They keep the steps and cite wiki pages for facts. `wiki skills` lists them, and `wiki skills link` links them into `~/.claude/skills`, prefixing a wiki's name when two share a skill name, never touching a skill from elsewhere, and removing links to deleted skills. The plugin's hook links new ones every session, as do `upgrade` and `setup`. Checked: Claude Code loads a symlinked skill folder, even mid-session. `wiki seed` now also takes `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, Cursor, Windsurf and Copilot rules, and `.claude/skills/`.

### Sessions upgrade wikis on their own (2026-10-28)

- **Why:** plugin updates arrived on their own, but the wikis stayed on the old handbook until someone ran `wiki upgrade --all` and committed, on every machine, after every handbook change.
- **What changed:** when the session's wiki is behind the plugin's handbook, the session hook tells the session to pull, run `wiki upgrade --all`, commit and push one `wikis: handbook vN` commit, and say what changed, before reading the new handbook. The hook doesn't upgrade files itself: upgrading before the pull would leave local changes, and the pull would fail if a teammate had pushed the same upgrade. `upgrade` never moves a wiki backwards.

### Install in three steps (2026-10-28)

- **Why:** a dry run as a new coworker, on a fake machine with a stock macOS `PATH`, hit two snags in the seven-step guide: auto-update needed a hand edit to `~/.claude/settings.json`, and the `wiki` command was linked into `~/.local/bin`, which a stock Mac's shell never looks in.
- **What changed:** from the plugin, `wiki setup` now links `wiki` into a writable folder already on the `PATH` (or `~/.local/bin`, adding it to the shell profile after asking), turns on auto-update, offers to install gitleaks with Homebrew, and removes the old `CLAUDE.md` line. `wiki link` does the first part alone, and the session hook points Claude at it. The guide went from seven steps to three: install, start a session, run setup. `wiki status` warns when auto-update is off. The rerun found and fixed a setup crash where an empty `grep` stopped the script.

### Day-one value, stats, and capture after compaction (2026-10-28, handbook version 16)

- **Seed:** `wiki seed` copies a repository's tracked README, top-level guides, `docs/` and decision records into its wiki's `raw/`, most useful first, capped at 20 documents and 100KB each, with a manifest note saying where they came from and that their code claims are unchecked. Reruns copy only what's new. The plugin's hook offers it in a repository with no wiki. PR descriptions were left out: they need an API token.
- **Capture after compaction:** a `PreCompact` hook can block compaction, but its output doesn't reach the model, so blocking would stall the session without prompting a capture. Instead the `SessionStart` hook, which runs again with `"source": "compact"`, asks the session to capture what the summary holds.
- **Stats:** handbook step 6 under Query logs one line per question to `stats.csv`: hit or miss. `wiki stats` shows hit rates. Git ignores the file.
- **Standup:** at most 15 commits per repository, newest first, via the `max_commits` setting or `--max`. Fixed on the way: "through now" cut off at the current minute, dropping the last few seconds of commits, and commits in the same minute were ordered by hash.

### CI and smoke tests (2026-10-28)

- **Why:** every commit on `main` reaches plugin users with auto-update on, and nothing checked a commit before it went out.
- **What changed:** `tests/smoke.sh` holds 54 checks built from the session's manual tests: collection and wiki commands, the files a new wiki gets, upgrade and the ahead-of-template guard, a two-clone union merge, the secret scan with a fake token, the session hook's output and its 2,000-character budget, the `wiki` command, symlinks, plugin mode, journal and standup. It runs in a temp `HOME` in about four seconds. GitHub Actions runs it on Linux and on macOS with Apple's bash 3.2, plus shellcheck and `claude plugin validate`. Sabotaging a copy of the repo (no `.gitattributes`, an oversized hook, a disabled scan) made the matching tests fail.

### Claude Code plugin (2026-10-28)

- **Why:** a line in `CLAUDE.md` relies on the agent choosing to act on it, the skill had to be zipped and uploaded by hand, and coworkers needed several setup steps.
- **What changed:** the repo is a plugin and its own marketplace. A `SessionStart` hook finds the session's wiki the way `wiki.sh which` does and tells the session to read its handbook first, with the waiting-note count and a note when the handbook is behind. It first embedded the handbook and index, about 15KB; in the desktop app's Code tab only a 2KB preview reached the model, so it now points instead, in about 600 characters. Tested in a desktop Code-tab session on 2026-10-28: hook, `/llm-wiki:status`, and the `wiki` command all worked. It runs again after `/clear` and compaction. Commands: `status`, `save`, `compile`, `standup`. The plugin carries `wiki.sh` and the template, and `wiki.sh` skips the `CLAUDE.md` line when run from the plugin, since a line naming the plugin's versioned folder would break on update. The manifest has no `version`, so each pushed commit is an update. The plugin's folder changes with each update, so the hook keeps a `wiki` command in the plugin's data folder, which survives updates, pointed at the current version. Claude offers once to link it onto the `PATH`. The command reads Claude Code's `installed_plugins.json` on every run, so `claude plugin update` takes effect at once, without waiting for a session to repoint it. `wiki.sh` messages name whichever command was typed.

### Scan for secrets before pushing (2026-10-28, handbook version 15)

- **Why:** agents commit and push on their own. "Never store secrets" was a rule, not a check, and a team collection spreads a leak to everyone.
- **What changed:** `hooks/pre-commit` runs gitleaks over staged files. `init --git`, `new --git`, `upgrade` and `setup git` install it in the collection or a wiki's own repo, never a project's repo, and leave an existing hook or `core.hooksPath` alone. A refused commit tells the agent to redact, even in `raw/`, and never to use `--no-verify`. Without gitleaks the hook warns and lets the commit through, and `status` says so.

### Team-sharing fixes (2026-10-28, handbook version 14)

- **Why:** the collection was built for one person. Shared with coworkers, three things broke: two people compiling one wiki conflicted in git, coworkers overwrote each other's delegation mode, and a stale template clone gave no sign.
- **What changed:** each wiki's `.gitattributes` merges `index.md` and `log.md` with git's union driver, and lint reports a page indexed twice. `delegation.md` is git-ignored like its log. `status` flags a wiki ahead of the local template, and `upgrade` leaves it alone.

### Delegation to cheaper models (2026-10-27, handbook version 12)

- **Why:** expensive models spent tokens on volume work, such as test runs, sweeps and boilerplate, that a cheaper model does as well.
- **What changed:** `rules/delegation.md` says when to hand off (self-contained, big, checkable), how to brief, to check before relying on the result, and to log each handoff. `~/wikis/delegation.md` holds the mode, a who-does-what table and an Auto list. Setup asks for the mode, the session line points every session at the file, and `./wiki.sh delegation` sums the log.

### Repeat feedback becomes a fix (2026-10-27, handbook version 11)

- **Why:** the same review comments came back on agent-written code, and the same corrections had to be repeated, such as a shared Go library's metrics being added again in every service that imports it. Repeated procedures and mechanical work cost tokens every time.
- **What changed:** agents add `Feedback:` lines to their notes, filed in the wiki that owns the rule. Compile tallies them in each wiki's `patterns.md`. A ready pattern gets one proposal with evidence, and the fix depends on its kind: a conventions line, a note for code that uses a library, a skill, or a script. Agents check conventions before calling code done. `./wiki.sh patterns` gives the cross-wiki view, and lint reports patterns nobody has proposed.

### Journal backfill (2026-10-22, handbook version 10)

- **Why:** the journal starts empty on the day it's turned on. Past sessions held the work that left no commit.
- **What changed:** `./wiki.sh journal backfill` digests Claude Code transcripts into `journal/backfill.md`, one block per project per day: prompts, files changed, whether it committed, the last reply. Agents turn the digest into entries per the new Backfill section of `rules/journal.md`. `journal note` takes `--day` and `--at`. First real run: 42 project-days over two weeks became 17 entries. It led to two digest fixes: drop prompts written by tools (task notifications, side-session events), and file sessions from scratch folders under the project they ran in.

### Step-by-step setup (2026-10-22)

- **Why:** setup was five commands plus hand edits, and nothing told an existing machine when a template update added a setting.
- **What changed:** `./wiki.sh setup` walks through the collection, git (repo, remote, commit email, a per-repo SSH key, a test push), the Claude Code session line, handbook upgrades, and every journal setting, with validation and re-asking on bad input. It records answered questions per machine in `~/.config/llm-wiki/setup`, so `setup --new` asks only about what's new. `setup --list` shows every value and marks defaults. `setup journal.format` (or `setup format`) edits one setting. `upgrade` ends with a summary: which wikis moved from which version, the `CHANGELOG.md` entries since then, and next steps (commit command, stale session line, new settings, restart running sessions). `status` and `upgrade --all` say when there is something. Journal settings now come from one registry in `wiki.sh`, so a new setting is one line. Handbook unchanged, still version 9.

### Work journal and standups (2026-10-22, handbook version 9)

- **Why:** engineers need a daily summary for standup. Version 8 stopped capturing finished work, so the wikis alone can't supply one.
- **What changed:** `./wiki.sh standup` gathers the user's commits across repositories, journal entries, wiki notes and changes, work in progress, and open checks. The agent writes it up as a standup, a summary, or a detailed report, per `rules/journal.md`. Agents add one journal line per stopping point for work that leaves no commit. On by default, not committed by default. Thirteen settings in `~/wikis/journal/config`.

### Fixes from the first week of real use (2026-10-07, handbook version 8)

- **Why:** a review of the live collection after six days. Ten wikis, 109 captured notes, 53 pages. Four things had gone wrong.
- **Compile wasn't firing.** 50 of 109 notes were never compiled, and five wikis had an empty index. Long working sessions never reach a "pause". Compile now also runs at session start and whenever five notes are waiting.
- **Capture was too eager.** One build session wrote 27 notes in a day, each its own commit. "Finished work" is no longer a trigger. Notes cover decisions, direction, and what the code doesn't show, at stopping points. Captures are committed with the next compile.
- **Lint never ran.** 58 ingests, no lint. Agents don't count log entries unprompted. Every compile now ends by counting, and `./wiki.sh status` flags `lint due` and `compile due`.
- **Timestamps were invented.** Several notes carried round times. The capture step now says to read the clock and never estimate.

### Wikis that cover several repositories (2026-10-01, handbook version 7)

- **Why:** the first real use was a product spread over several repositories. One wiki per repository sent sessions to the wrong wiki and split the same fact across two.
- **What changed:** a wiki covers a project. That is one repository by default, or several listed in its `repos.md`. Sessions resolve a repository to its wiki by name, then by listing. `./wiki.sh cover` and `./wiki.sh which` manage and query the mapping. The staleness rule now covers facts checked against a cited source, not only against code. `./wiki.sh claude` replaces its own older line.

### Core handbook plus on-demand rules (2026-09-30, handbook version 6)

- **Why:** the handbook loaded in full in every session, about 3,800 tokens, and a third of it went unused.
- **What changed:** `template/AGENTS.md` now holds only what every session needs, about 2,500 tokens. Compile, conflicts, lint, and peer-wiki rules moved to `template/rules/` and are read on demand. The skill no longer embeds a copy of the handbook, which cut it from about 5,300 tokens to about 1,500 and removed a second copy to keep in step.

### Stale-knowledge guard (2026-09-30, handbook version 6)

- **Why:** code changes and pages don't. A stale page that answers confidently is worse than no page.
- **What changed:** pages carry `verified` and `commit` stamps. Before acting on a claim about code, the agent checks it against the code when the code is at hand, and files a correction if it no longer holds. Answers from pages verified more than 90 days ago say so. Lint flags pages past 180 days. `./wiki.sh stale` lists them.
