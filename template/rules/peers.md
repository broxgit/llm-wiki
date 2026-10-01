# Peers

Read this before creating a wiki for another repository or moving knowledge between wikis.

## Create a missing wiki

Do this when you have something to file and no wiki is named after the owning repository or lists it in `repos.md`. Check both first. No need to ask.

1. Name it after the repository: the last part of its remote URL, or its folder name when it has no remote. Put it beside this wiki.
2. Copy this wiki's `AGENTS.md`, `CLAUDE.md`, `links.md`, `.gitignore`, and `rules/` folder into it.
3. Add `raw/`, `wiki/`, and `data/` folders.
4. Create `index.md` containing `# Index`, `log.md` containing `# Log`, and `repos.md` containing `# Repositories`. Don't copy this wiki's `repos.md`.

## One wiki for several repositories

Repositories belong in one wiki when a single piece of work routinely touches several of them, or when the same facts matter to all of them. Don't decide that on your own. If you see knowledge about one subject being split across wikis, tell the user and suggest a shared project wiki.

When the user sets one up, add a line per repository to its `repos.md`:

```
- repository-name
```

Inside such a wiki, file shared knowledge once, by topic. Give a repository its own page only for what is specific to it, such as its build steps.

Don't create wikis for third-party libraries. Their knowledge goes in a shared wiki. Don't create an empty wiki just to look something up.

## Compile other wikis

At a pause, after this wiki, compile any shared wiki with pending files and any peer this session captured into. Use each wiki's own lock. Leave the other peers alone, with one exception: if a peer has pending files that bear on a question you are answering, compile them first.

## Move knowledge

If a page here turns out to belong in another wiki, tell the user. Moving it is restructuring, so ask first. Once they agree, capture the content into the owning wiki as a note, compile it there, and replace this page's body with a citation to the new page.
