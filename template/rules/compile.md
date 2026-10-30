# Compile

Read this before any change to `wiki/`, `index.md`, or `log.md`. Ingest, lint, and restructure are all compile work.

## The lock

One session compiles at a time. The lock is the file `.compile-lock` in the wiki root. Git ignores it.

Check for pending files first. Take the lock only when there is something to compile.

1. Read `.compile-lock`. The lock is free if the file is missing, says `free`, or carries a time more than 30 minutes old.
2. If it is free, write one line: `held <token> <UTC time>`. Make up a 6-character token. Write the time as `YYYY-MM-DDTHH:MM:SSZ`.
3. Read the file back. If the token is yours, you hold the lock. If not, another session got there first. Don't compile.
4. When the compile work ends, write `free`. Do this even if the work failed.

`wiki.sh lock <wiki>` does steps 1 to 3, and exits with an error if another session holds the lock. `wiki.sh lock <wiki> --release` does step 4, and `--renew` rewrites the time. Use them when you have the script.

If you can't get the current time, treat any `held` line as held. If compile work runs past 20 minutes, rewrite the line with a fresh time.

Once you hold the lock, read the last 10 entries of `log.md`.

`index.md` and `log.md` are shared by every compile. Re-read each one right before editing it. Change only the lines you need. Never rewrite either from an earlier read.

## Ingest

Trigger: session start, a pause, five notes waiting, or the user says "ingest" or "compile".

With a named source, ingest that source. With none, ingest every pending file in `raw/` in filename order. That is oldest first. A raw file is pending until it is compiled: until an ingest entry in `log.md` names it in a `- source:` line, a page lists it in `sources:`, or, in a wiki from before handbook v24, `wiki/sources/` has a page of the same name, extension aside. Check with `wiki.sh pending <wiki>`. Don't open files to check. Ignore dotfiles.

With fewer than five pending files, compile them one at a time, as in the steps below. With five or more, as after `wiki seed`, compile them as one batch: see [Many files at once](#many-files-at-once).

When a pending file is a newer version of an earlier one, the same document often named `-v2` or `-v3`, the newer one supersedes it. Compile the newer version. In the older one's source page, add a line naming the file that replaced it. Don't merge claims from both versions.

For each source:

1. If it is not in `raw/` yet, capture it first.
2. Read it once, fully. Skip the read if this session wrote it.
3. Update every other wiki page the source affects. Create a new page only if the topic will be referenced again. Before creating one, look for the topic in the other wikis with `wiki.sh find <word>`. If another wiki has it, add to that page or cite it, instead of starting a second copy. If the lesson holds beyond this project, as `AGENTS.md` describes under Ownership, write it in the shared wiki and cite it from here. When a page gains a claim that matters, revise its summary so the index shows it.
4. Where the source disagrees with an existing page, or you doubt a claim, read `rules/conflicts.md` and follow it. Never overwrite silently.
5. If it has `Feedback:` lines, add each to `patterns.md` as `rules/patterns.md` says.

After the last source, update `index.md` once (`wiki.sh index <wiki>`) and append one entry per source to `log.md`, naming the source in it. That entry is what marks the source compiled. Also stamp any page you confirmed against code this session (see Stale knowledge in `AGENTS.md`). Then report in one line: pages created, pages updated, corrections, conflicts.

### Many files at once

One file at a time means rewriting the same topic page once per file, and a session that spends its start compiling instead of helping. With five or more pending files:

1. Read them together. `wiki.sh pending <wiki> --show` prints them in one go, oldest first, up to about 150KB. If it says more wait, finish this batch, then run it again for the next.
2. Before writing, plan: group the claims across all the files by topic, and match each topic to an existing page or a new one. A topic only one file touches still goes on a topic page.
3. Write each topic page once, with every file's claims for it, each cited to its file.
4. Steps 4 and 5 above still apply to every file: conflicts, and `Feedback:` lines.
5. Finish as below: `index.md` once, and one `log.md` entry per file.

Files named `*-seed-*` came from `wiki seed`: a repository's own docs, as its authors wrote them. Read the `seed-00-manifest` note first. It says which repository and commit they came from. Their claims about code are unchecked, so don't stamp `commit` from them, and where two of them disagree, the code decides once you check it.

Last, before you release the lock, count the `ingest` entries in `log.md` that come after the most recent `lint` entry. At 10 or more, read `rules/lint.md` and lint now.

## Pages

Suggested subfolders under `wiki/`: `concepts/`, `entities/`, `howto/`, `decisions/`. Add others when a category has three or more pages.

Every page starts with frontmatter:

```yaml
---
title: Short title
summary: One line, under 120 characters. This is what the index shows.
tags: [tag-one, tag-two]
sources: [raw/2026-01-15-093000-example.pdf]
updated: 2026-01-15
verified: 2026-01-15
commit: 3f2a9c1
---
```

- `updated` is the day the page's text last changed.
- `verified` is the day its claims were last confirmed. Set it at ingest. Move it forward when you confirm the page against code. If you confirmed only some of its claims, still move it forward, and mark each claim you could not check with `(not re-checked)`.
- `commit` is the short hash of the owning repository's HEAD on the `verified` day. Include it only when you checked the claim against that repository's code. Leave it out otherwise. Never stamp a commit on a claim nobody checked. In a wiki that covers several repositories, write it as `repository-name@hash`.
- A fact taken from outside, such as a vote, a quote, or a figure, names its source where the claim is stated: a link, or the document and date.
- Dates and times are UTC everywhere: filenames, frontmatter, and the log.
- Quote frontmatter values that contain a colon.
- A project's procedures and tools go in its `wiki/conventions.md`, under `## For agents` and `## Tools`, one line each, each citing its source. Create the page when the first one comes up. A `Tools` line reads `- <name> (<cli|mcp|other>): what it's for`; `wiki.sh start` checks that each `cli` tool is installed. Ones that hold in every project go in the shared wiki's conventions instead.
- One topic per page.
- A page about current state, such as work in progress or open questions, carries `as_of: YYYY-MM-DD` in its frontmatter and the date in its summary. When the state changes, rewrite it to the new state. Don't append: the log and the sources keep the history.
- Keep pages under roughly 1,500 words. Split larger ones and link the parts.
- Lead with the conclusion. Detail follows.
- Link with relative markdown links: `[Title](../concepts/page.md)`. They work in every tool.
- Every claim traces to a file in `raw/`. Mark anything else `(unsourced)`.
- Filenames are `lowercase-kebab-case.md`. Avoid renames. If one is needed, fix every inbound link and the index in the same change.

## index.md

Grouped by category. One line per page, except the source summaries under `wiki/sources/` that wikis from before v24 have. Those are bookkeeping and stay out of the index; leave them as they are. Skills get a `## Skills` section, one line per `skills/<name>/SKILL.md`, with its description.

```markdown
## Concepts
- [Page title](wiki/concepts/page-title.md): the summary line from its frontmatter
```

After changing pages, run `wiki.sh index <wiki>`. It adds, updates and removes lines from each page's frontmatter, keeps your order and headings, and lists every line it changed. To change an index line, change the page's `summary` and run it again. Never edit a page's line by hand only.

Keep it under 300 lines. Past that, split into one index file per category and make `index.md` a short list of those.

## log.md

Newest entry at the bottom. Append only. `wiki.sh log <wiki> ingest "<title>" --source raw/<file> --created <page> --updated <page> --conflicts <n>` appends a well-formed entry and prints the counts for your one-line report. It also takes `lint` with `--fixed` and `--reported`, and `--corrections` and `--patterns`.

```markdown
## 2026-01-15 ingest: Source title
- source: raw/2026-01-15-093000-source-title.md
- updated: wiki/concepts/page-title.md
- conflicts: 1
```

One entry per source, dated the day of the work and titled with the source's title. The `- source:` line names its file in `raw/`, and marks it compiled. The other lines list wiki pages. `conflicts` counts contradictions flagged. Write it even at zero. Add a `corrections:` line when a source corrected earlier claims, and a `patterns:` line with the number of `Feedback:` lines tallied when there were any. Entry types: `ingest`, `lint`, `restructure`, `resolve`. Captures are not logged. The file in `raw/` is the record. Stamping `verified` and `commit` is not logged either.

## Structured data

Rows do not belong in wiki pages. Records, listings, and metrics go in `data/` as CSV or SQLite. Query them with a tool and return only the rows needed. A wiki page documents each dataset: what it is, its columns, where it came from.
