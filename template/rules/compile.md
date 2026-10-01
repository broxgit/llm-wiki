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

Trigger: your own judgment at a pause, or the user says "ingest" or "compile".

With a named source, ingest that source. With none, ingest every pending file in `raw/` in filename order. That is oldest first. A raw file is pending when `wiki/sources/` has no page with the same name, extension aside. Check by listing the two folders. Don't open files to check. Ignore dotfiles. A missing `wiki/sources/` folder means nothing has been ingested yet.

For each source:

1. If it is not in `raw/` yet, capture it first.
2. Read it once, fully. Skip the read if this session wrote it.
3. Write a summary page in `wiki/sources/` with the raw file's name, minus its extension, plus `.md`. Keep it short: what the source is, and links to the pages that carry its claims. Don't restate a short note.
4. Update every other wiki page the source affects. Create a new page only if the topic will be referenced again. When a page gains a claim that matters, revise its summary so the index shows it.
5. Where the source disagrees with an existing page, or you doubt a claim, read `rules/conflicts.md` and follow it. Never overwrite silently.

After the last source, update `index.md` once and append one entry per source to `log.md`. Also stamp any page you confirmed against code this session (see Stale knowledge in `AGENTS.md`). Then report in one line: pages created, pages updated, corrections, conflicts.

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
- `commit` is the short hash of the owning repository's HEAD on the `verified` day. Include it for claims about code when that repository is at hand. Leave it out otherwise.
- Dates and times are UTC everywhere: filenames, frontmatter, and the log.
- Quote frontmatter values that contain a colon.
- One topic per page.
- Keep pages under roughly 1,500 words. Split larger ones and link the parts.
- Lead with the conclusion. Detail follows.
- Link with relative markdown links: `[Title](../concepts/page.md)`. They work in every tool.
- Every claim traces to a file in `raw/`. Mark anything else `(unsourced)`.
- Filenames are `lowercase-kebab-case.md`. Avoid renames. If one is needed, fix every inbound link and the index in the same change.

## index.md

Grouped by category. One line per page, except pages under `wiki/sources/`. Those are bookkeeping and stay out of the index.

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

One entry per source, dated the day of the work and titled with the summary page's title. List wiki pages only. `conflicts` counts contradictions flagged. Write it even at zero. Add a `corrections:` line when a source corrected earlier claims. Entry types: `ingest`, `lint`, `restructure`, `resolve`. Captures are not logged. The file in `raw/` is the record. Stamping `verified` and `commit` is not logged either.

## Structured data

Rows do not belong in wiki pages. Records, listings, and metrics go in `data/` as CSV or SQLite. Query them with a tool and return only the rows needed. A wiki page documents each dataset: what it is, its columns, where it came from.
