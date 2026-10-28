# Compile

Read this before any change to `wiki/`, `index.md`, or `log.md`. Ingest, lint, and restructure are all compile work.

## The lock

One session compiles at a time. The lock is the file `.compile-lock` in the wiki root. Git ignores it.

Check for pending files first. Take the lock only when there is something to compile.

1. Read `.compile-lock`. The lock is free if the file is missing, says `free`, or carries a time more than 30 minutes old.
2. If it is free, write one line: `held <token> <UTC time>`. Make up a 6-character token. Write the time as `YYYY-MM-DDTHH:MM:SSZ`.
3. Read the file back. If the token is yours, you hold the lock. If not, another session got there first. Don't compile.
4. When the compile work ends, write `free`. Do this even if the work failed.

If you can't get the current time, treat any `held` line as held. If compile work runs past 20 minutes, rewrite the line with a fresh time.

Once you hold the lock, read the last 10 entries of `log.md`.

`index.md` and `log.md` are shared by every compile. Re-read each one right before editing it. Change only the lines you need. Never rewrite either from an earlier read.

## Ingest

Trigger: session start, a pause, five notes waiting, or the user says "ingest" or "compile".

With a named source, ingest that source. With none, ingest every pending file in `raw/` in filename order. That is oldest first. A raw file is pending when `wiki/sources/` has no page with the same name, extension aside. Check by listing the two folders. Don't open files to check. Ignore dotfiles. A missing `wiki/sources/` folder means nothing has been ingested yet.

With fewer than five pending files, compile them one at a time, as in the steps below. With five or more, as after `wiki seed`, compile them as one batch: see [Many files at once](#many-files-at-once).

For each source:

1. If it is not in `raw/` yet, capture it first.
2. Read it once, fully. Skip the read if this session wrote it.
3. Write a summary page in `wiki/sources/` with the raw file's name, minus its extension, plus `.md`. Keep it short: what the source is, and links to the pages that carry its claims. Don't restate a short note.
4. Update every other wiki page the source affects. Create a new page only if the topic will be referenced again. Before creating one, look for the topic in the other wikis with `wiki.sh find <word>`. If another wiki has it, add to that page or cite it, instead of starting a second copy. If the lesson holds beyond this project, as `AGENTS.md` describes under Ownership, write it in the shared wiki and cite it from here. When a page gains a claim that matters, revise its summary so the index shows it.
5. Where the source disagrees with an existing page, or you doubt a claim, read `rules/conflicts.md` and follow it. Never overwrite silently.
6. If it has `Feedback:` lines, add each to `patterns.md` as `rules/patterns.md` says.

After the last source, update `index.md` once and append one entry per source to `log.md`. Also stamp any page you confirmed against code this session (see Stale knowledge in `AGENTS.md`). Then report in one line: pages created, pages updated, corrections, conflicts.

### Many files at once

One file at a time means rewriting the same topic page once per file, and a session that spends its start compiling instead of helping. With five or more pending files:

1. Read them together. `wiki.sh pending <wiki> --show` prints them in one go, oldest first, up to about 150KB. If it says more wait, finish this batch, then run it again for the next.
2. Before writing, plan: group the claims across all the files by topic, and match each topic to an existing page or a new one. A topic only one file touches can stay on that file's own page.
3. Write each topic page once, with every file's claims for it, each cited to its file.
4. Write each file's summary page in `wiki/sources/`: one line on what it is, and links to the pages it fed.
5. Steps 5 and 6 above still apply to every file: conflicts, and `Feedback:` lines.
6. Finish as below: `index.md` once, and one `log.md` entry per file.

Files named `*-seed-*` came from `wiki seed`: a repository's own docs, as its authors wrote them. Read the `seed-00-manifest` note first. It says which repository and commit they came from. Their claims about code are unchecked, so don't stamp `commit` from them, and where two of them disagree, the code decides once you check it.

Last, before you release the lock, count the `ingest` entries in `log.md` that come after the most recent `lint` entry. At 10 or more, read `rules/lint.md` and lint now.

## Pages

Suggested subfolders under `wiki/`: `sources/` (one summary per raw source), `concepts/`, `entities/`, `howto/`, `decisions/`. Add others when a category has three or more pages.

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
- One topic per page.
- Keep pages under roughly 1,500 words. Split larger ones and link the parts.
- Lead with the conclusion. Detail follows.
- Link with relative markdown links: `[Title](../concepts/page.md)`. They work in every tool.
- Every claim traces to a file in `raw/`. Mark anything else `(unsourced)`.
- Filenames are `lowercase-kebab-case.md`. Avoid renames. If one is needed, fix every inbound link and the index in the same change.

## index.md

Grouped by category. One line per page, except pages under `wiki/sources/`. Those are bookkeeping and stay out of the index. Skills get a `## Skills` section, one line per `skills/<name>/SKILL.md`, with its description.

```markdown
## Concepts
- [Page title](wiki/concepts/page-title.md): the summary line from its frontmatter
```

Keep it under 300 lines. Past that, split into one index file per category and make `index.md` a short list of those.

## log.md

Newest entry at the bottom. Append only.

```markdown
## 2026-01-15 ingest: Source title
- created: wiki/sources/2026-01-15-093000-source-title.md
- updated: wiki/concepts/page-title.md
- conflicts: 1
```

One entry per source, dated the day of the work and titled with the summary page's title. List wiki pages only. `conflicts` counts contradictions flagged. Write it even at zero. Add a `corrections:` line when a source corrected earlier claims, and a `patterns:` line with the number of `Feedback:` lines tallied when there were any. Entry types: `ingest`, `lint`, `restructure`, `resolve`. Captures are not logged. The file in `raw/` is the record. Stamping `verified` and `commit` is not logged either.

## Structured data

Rows do not belong in wiki pages. Records, listings, and metrics go in `data/` as CSV or SQLite. Query them with a tool and return only the rows needed. A wiki page documents each dataset: what it is, its columns, where it came from.
