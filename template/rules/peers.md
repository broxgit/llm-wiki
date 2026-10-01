# Peers

Read this before creating a wiki for another repository or moving knowledge between wikis.

## Create a missing wiki

Do this when you have something to file and the owning repository has no wiki yet. No need to ask.

1. Name it after the repository: the last part of its remote URL, or its folder name when it has no remote. Put it beside this wiki.
2. Copy this wiki's `AGENTS.md`, `CLAUDE.md`, `links.md`, `.gitignore`, and `rules/` folder into it.
3. Add `raw/`, `wiki/`, and `data/` folders.
4. Create `index.md` containing `# Index` and `log.md` containing `# Log`.

Don't create wikis for third-party libraries. Their knowledge goes in a shared wiki. Don't create an empty wiki just to look something up.

## Compile other wikis

At a pause, after this wiki, compile any shared wiki with pending files and any peer this session captured into. Use each wiki's own lock. Leave the other peers alone, with one exception: if a peer has pending files that bear on a question you are answering, compile them first.

## Move knowledge

If a page here turns out to belong in another wiki, tell the user. Moving it is restructuring, so ask first. Once they agree, capture the content into the owning wiki as a note, compile it there, and replace this page's body with a citation to the new page.
