# Roadmap

Potential improvements to the wiki template, in rough order of payoff. Work from the top of Next. When an item is finished, move it to Done with the date and what changed.

Each item says why it matters, a sketch of how, and what is still undecided.

## Next

### Terse page style

- **Why:** agents read pages far more often than people do. Measured on one sample page, terse notes in plain words used 56% of the tokens of default prose. The body alone used 45%.
- **Sketch:** a style rule in `rules/compile.md`. One fact per line. Fragments over sentences. No narrative, no restating. Plain words, identifiers verbatim. Then trim frontmatter, which is nearly half of a terse page: cite sources by timestamp prefix, and drop fields that repeat each other.
- **Not this:** invented abbreviations or JSON. In the same test, shorthand saved 2 points over terse plain words and JSON saved none. Abbreviations cost more tokens per word ("tmo" is 2 tokens, "timeout" is 1) and are harder for a model to read back.
- **Open:** whether terse pages hurt answer quality. Test by asking the same questions against both versions of a page. Whether teammates still need to read pages comfortably.

### Seed a wiki from its repository

- **Why:** a new wiki is empty. Each repository already holds a README, docs, decision records, and merged PR descriptions. Ingesting those makes a wiki useful on day one.
- **Sketch:** `./wiki.sh seed <name> <path to repo>` copies the chosen documents into `raw/`. The next session compiles them. Stamp pages with the repository's HEAD.
- **Open:** which files to take by default. How to cap the size for a large repo. Whether PR descriptions are worth the API calls.

### Hooks for the two moments that matter

- **Why:** instructions are suggestions. A hook runs every time.
- **Sketch:** Claude Code only. A `SessionStart` hook injects the wiki's index. A `PreCompact` hook holds compaction until the session has captured what it knows.
- **Open:** how to find the right wiki from inside a hook. Whether blocking compaction is too heavy-handed. The handbook must stay usable without hooks.

### Scan for secrets before pushing

- **Why:** agents commit and push on their own. "Never store secrets" is a rule, not a check.
- **Sketch:** a pre-commit hook in the collection repo that runs a secret scanner over staged files. `./wiki.sh init --git` installs it.
- **Open:** which scanner. What the agent should do when a commit is refused.

### Measure whether it pays

- **Why:** nobody knows yet if the wikis save tokens or just move them.
- **Sketch:** the agent appends one line per lookup to a local, git-ignored file: date, wiki, hit or miss. `./wiki.sh stats` shows hit rate per wiki.
- **Open:** whether agents will log reliably. What hit rate means a wiki should be dropped.

## Later

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

- `wiki.sh` on macOS, beyond `new` and `status`. Those two ran cleanly in real use on 2026-10-01. The other commands have only run on Linux.
- Git sync between two people or two machines. Pull, commit, and push from one machine worked in real use on 2026-10-01.
- Two sessions taking the compile lock in the same second.
- A wiki with two shared wikis listed in `links.md`.
- Real scale: hundreds of wikis, hundreds of pages. Real use so far is 10 wikis and 53 pages.
- The version 8 triggers in real use. They passed a dry run only.
- A model other than Claude following the handbook.

## Decided against

- **Embeddings or a vector database.** Lookup by repository name plus keyword search covers the need. Embeddings also tie the data to one embedding model.
- **A custom UI.** Obsidian and GitHub already render markdown.
- **More scaffolding automation.** Setup is one command and one line.

## Done

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
