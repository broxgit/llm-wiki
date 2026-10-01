# Roadmap

Potential improvements to the wiki template, in rough order of payoff. Work from the top of Next. When an item is finished, move it to Done with the date and what changed.

Each item says why it matters, a sketch of how, and what is still undecided.

## Next

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

- **Trim the core further.** `template/AGENTS.md` is about 2,500 tokens. "Other wikis" and "Sync" are the biggest sections left.
- **Batch small compiles.** A one-line fact costs a lock, a source page, a topic page, an index edit, and a log entry. Let a few notes collect before compiling.
- **Search page text, not just indexes.** `./wiki.sh find` reads `index.md` only. Past a few hundred pages per wiki it should search page bodies too.
- **Reach sessions with no file access.** A chat session that can't read files can't use a wiki. A small MCP server over the collection would fix that.
- **Review flow for teams.** Agents push straight to the collection. A team may want a weekly digest of changes, or pull requests.
- **Obsidian.** Add `.obsidian/` to the template's `.gitignore` if anyone opens wikis as vaults.
- **Dependency map.** A table of which repository owns which client or package, built from module files, kept in the shared wiki's `data/`.

## Untested

Things that have never been run for real. Treat them as unproven until crossed off.

- `wiki.sh` on macOS. It was written for bash 3.2 and BSD tools but only run on Linux.
- Git sync. Every dry run used wikis with no git.
- Two sessions taking the compile lock in the same second.
- A wiki with two shared wikis listed in `links.md`.
- Real scale: hundreds of wikis, hundreds of pages.
- A model other than Claude following the handbook.

## Decided against

- **Embeddings or a vector database.** Lookup by repository name plus keyword search covers the need. Embeddings also tie the data to one embedding model.
- **A custom UI.** Obsidian and GitHub already render markdown.
- **More scaffolding automation.** Setup is one command and one line.

## Done

### Core handbook plus on-demand rules (2026-09-30, handbook version 6)

- **Why:** the handbook loaded in full in every session, about 3,800 tokens, and a third of it went unused.
- **What changed:** `template/AGENTS.md` now holds only what every session needs, about 2,500 tokens. Compile, conflicts, lint, and peer-wiki rules moved to `template/rules/` and are read on demand. The skill no longer embeds a copy of the handbook, which cut it from about 5,300 tokens to about 1,500 and removed a second copy to keep in step.

### Stale-knowledge guard (2026-09-30, handbook version 6)

- **Why:** code changes and pages don't. A stale page that answers confidently is worse than no page.
- **What changed:** pages carry `verified` and `commit` stamps. Before acting on a claim about code, the agent checks it against the code when the code is at hand, and files a correction if it no longer holds. Answers from pages verified more than 90 days ago say so. Lint flags pages past 180 days. `./wiki.sh stale` lists them.
