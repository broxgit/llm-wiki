# Lint

Run when the user asks, or when a compile finds 10 or more ingests since the last lint. Lint is compile work. Read `rules/compile.md` and take the lock first.

`wiki.sh lint <wiki>` does the mechanical checks: links, citations, index lines, frontmatter, `sources:` files, size, stale dates, open `Check` and `Conflict` lines, and waiting notes. Run it first and fix what it reports, then do the rest of this list yourself.

Check for:

- Broken links
- Pages missing from the index, index lines with no page, and two index lines for one page (a merge keeps both sides when two people edit the same line)
- Orphans (no inbound links). Source summaries are exempt from both checks
- Missing or incomplete frontmatter, and `sources:` entries with no file in `raw/`
- Pages over the size limit
- Unresolved `Conflict` lines and open `Check` lines
- Claims superseded by a newer source
- Duplicate or near-duplicate pages
- Pending files in `raw/`
- Knowledge about one subject split across this wiki and a peer. Report it. Don't move anything
- The same fact on pages in several wikis, especially copies that a later source changed in only one place, such as a rename. Report which copy is current
- Citations to other wikis (`name:path`) whose page doesn't exist
- Pages here whose lesson holds beyond this project, as `AGENTS.md` describes under Ownership. Report each, and offer to move the general part to the shared wiki, leaving a citation. Moving is restructuring, so ask first
- In the shared wiki: pages that depend on a project page, such as an example that only links into one project. The shared page should stand on its own
- Patterns: run `wiki.sh patterns`. Report ready entries nobody has proposed, accepted ones that still get sightings (marked `AGAIN`), and the same rule tallied in two wikis. Ask before moving an entry to the wiki that owns it
- Stale pages: no `verified` date, or one more than 180 days old. If the owning repository is at hand, also pages whose `commit` is far behind its HEAD

Report findings first. Fix mechanical problems (links, index lines, frontmatter) without asking. Re-verify stale pages against the code when you can, and stamp the ones that still hold. Ask before merging pages, deleting pages, or resolving conflicts.

Outside a lint run, fix a broken link or a stale claim when you trip over one while you hold the lock.

Log the run as `## YYYY-MM-DD lint`, with one `- fixed:` line per fix and one `- reported:` line per finding you left for the user. In a lint you started yourself, fix the mechanical problems, then report everything in your next reply.
