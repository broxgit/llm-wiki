# Lint

Run when the user asks, or on your own when the log shows 10 or more ingests since the last lint. Lint is compile work. Read `rules/compile.md` and take the lock first.

Check for:

- Broken links
- Pages missing from the index, and index lines with no page
- Orphans (no inbound links). Source summaries are exempt from both checks
- Missing or incomplete frontmatter
- Pages over the size limit
- Unresolved `Conflict` lines and open `Check` lines
- Claims superseded by a newer source
- Duplicate or near-duplicate pages
- Pending files in `raw/`
- Stale pages: no `verified` date, or one more than 180 days old. If the owning repository is at hand, also pages whose `commit` is far behind its HEAD

Report findings first. Fix mechanical problems (links, index lines, frontmatter) without asking. Re-verify stale pages against the code when you can, and stamp the ones that still hold. Ask before merging pages, deleting pages, or resolving conflicts.

Outside a lint run, fix a broken link or a stale claim when you trip over one while you hold the lock.

Log the run with an entry of type `lint`.
