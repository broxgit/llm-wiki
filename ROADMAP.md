# Roadmap

Potential improvements to the wiki template, in rough order of payoff. Work from the top of Next. When an item is finished, move it to Done with the date and what changed.

Each item says why it matters, a sketch of how, and what is still undecided.

## Next

### Terse page style

- **Why:** agents read pages far more often than people do. Measured on one sample page, terse notes in plain words used 56% of the tokens of default prose. The body alone used 45%.
- **Sketch:** a style rule in `rules/compile.md`. One fact per line. Fragments over sentences. No narrative, no restating. Plain words, identifiers verbatim. Then trim frontmatter, which is nearly half of a terse page: cite sources by timestamp prefix, and drop fields that repeat each other.
- **Not this:** invented abbreviations or JSON. In the same test, shorthand saved 2 points over terse plain words and JSON saved none. Abbreviations cost more tokens per word ("tmo" is 2 tokens, "timeout" is 1) and are harder for a model to read back.
- **Open:** whether terse pages hurt answer quality. Test by asking the same questions against both versions of a page. Whether teammates still need to read pages comfortably.

## Later

- **Merge requests in standups.** Reviews and MRs opened live in GitHub or GitLab, not in git history. Pulling them in would need an API token and a host per remote.
- **Backfill from more places.** Sessions in the Claude desktop app and claude.ai chats aren't in `~/.claude/projects`. An agent with chat search could add them.
- **Team digest.** A weekly roll-up across several people's journals, for a lead. Needs a shared, opt-in journal location.
- **Trim the core further.** `template/AGENTS.md` is about 2,900 tokens, up from 2,600 after version 8. "Other wikis" and "Sync" are the biggest sections left.
- **Drop per-source summary pages.** Each raw note gets a summary page that only says where its claims live. The live collection has 59 of them. A single ledger file per wiki could track what has been ingested.
- **Split work and personal collections.** One collection on a personal remote now holds work, client, and personal wikis. `WIKIS_DIR` already supports a second collection. The routing line would need to know about both.
- **Compile a backlog in bulk.** A wiki with dozens of waiting notes compiles one source at a time. A bulk mode could read them all, then write pages once.
- **Search page text, not just indexes.** `./wiki.sh find` reads `index.md` only. Past a few hundred pages per wiki it should search page bodies too.
- **Reach sessions with no file access.** A chat session that can't read files can't use a wiki. A small MCP server over the collection would fix that.
- **Review flow for teams.** Agents push straight to the collection. A team may want a weekly digest of changes, or pull requests.
- **Obsidian.** Add `.obsidian/` to the template's `.gitignore` if anyone opens wikis as vaults.
- **Dependency map.** A table of which repository owns which client or package, built from module files, kept in the shared wiki's `data/`.

## Untested

Things that have never been run for real. Treat them as unproven until crossed off.

- `wiki.sh` on macOS: `setup`, `journal backfill`, `unlock` and `claude`. Every other command ran cleanly on macOS (bash 3.2, BSD `date`) on 2026-10-28.
- `wiki.sh setup` on macOS. It ran only in a Linux pseudo-terminal. The SSH key test push never ran against a real SSH host.
- `wiki.sh journal backfill` on macOS, and on transcripts from Claude Code versions other than the one it was written against. It needs `python3`.
- Git sync between two people or two machines. Pull, commit, and push from one machine worked in real use on 2026-10-01.
- Two sessions taking the compile lock in the same second.
- A wiki with two shared wikis listed in `links.md`.
- Real scale: hundreds of wikis, hundreds of pages. Real use so far is 10 wikis and 53 pages.
- The version 8 triggers in real use. They passed a dry run only.
- A model other than Claude following the handbook.
- Delegation in real use: whether sessions suggest handoffs at the right size, and whether the log shows real savings. The log records outcomes, not tokens. Token counts per handoff would need the tool's usage data.
- Stats in real use: whether sessions log every lookup, and what hit rate means a wiki should go.
- Seed in real use: how long compiling 20 seeded documents takes, and whether the pages are worth it.
- Patterns in real use: whether agents write `Feedback:` lines unprompted, and whether the thresholds are right.

## Decided against

- **Embeddings or a vector database.** Lookup by repository name plus keyword search covers the need. Embeddings also tie the data to one embedding model.
- **A custom UI.** Obsidian and GitHub already render markdown.
- **More scaffolding automation.** Setup is one command.

## Done

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
