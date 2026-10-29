# Peers

Read this before you look something up in a peer wiki, write to another wiki, create one, or move knowledge between wikis.

## Other wikis

This wiki is rarely alone. Two kinds of other wiki matter. Each has its own `AGENTS.md` and `rules/`, which apply when you write there. If its version line matches this handbook's, yours will do. Reading from another wiki needs no check.

**Peers.** Every wiki in this wiki's parent folder is a peer. Each covers one project. Most projects are a single code repository, and the wiki is named after it: the last part of the repository's remote URL, or its folder name when it has no remote. A project that spans several repositories has one wiki, named after the project, and its `repos.md` lists every repository it covers. To find the wiki for a repository, look for the peer with that name. If there is none, search the peers' `repos.md` files for it.

**Shared.** `links.md` lists wikis for knowledge that holds everywhere, one per line:

```
- global: ~/wikis/global | knowledge that holds across projects: tooling, conventions, glossary
```

Each line is a name, a path, and a purpose. Skip a line whose path doesn't exist on this machine, or that points at this wiki.

Rules for both kinds:

- **Ownership.** Knowledge lives in the wiki of whatever owns the thing. What you learn about another project's code, client, or API goes in that project's wiki, even though this session is working elsewhere. Knowledge that holds beyond one project goes in the shared wiki whose purpose fits. For example:
  - how the user wants agents to work (commits, branches, writing style, when to ask), in `wiki/conventions.md` under `## For agents`;
  - how a shared library, internal tool, or vendor behaves;
  - delivery pipelines, environments, and deploys;
  - team practice for observability, tickets, and reviews;
  - decisions by a guild or any group that sets practice across repositories.

  Write the general lesson there once. Here, keep only what is specific to this project, with a citation to the shared page. Knowledge about this project stays here, once, however many of its repositories it touches. When unsure whether something holds beyond this project, ask yourself whether another repository's session would act differently for knowing it.
- **Lookup by name.** When the work touches a repository outside this project that the user's team owns, find its wiki and read that `index.md` before answering from its source code or from general knowledge. Also list its `raw/` for pending files whose names bear on the question, and read those.
- **Search.** When you don't know which wiki owns a topic, search the peers' `index.md` files by keyword and open only the ones that match. Then try the shared wikis in listed order. Never read every index.
- **Found another way.** If you reached this repository's wiki some way other than its name or `repos.md`, such as a pointer in a file, run `wiki.sh cover <wiki> <repository>` so the next session finds it by name.
- **Missing wiki.** If you have something to file and no wiki is named after the owning repository or lists it, create one. `rules/peers.md` says how. Don't create a wiki just to look something up.
- **Cite, don't copy.** Never restate what another wiki says. Refer to its pages as `name:path`, such as `billing-service:wiki/entities/client.md`. Don't use relative file paths across wikis.


## Create a missing wiki

Do this when you have something to file and no wiki is named after the owning repository or lists it in `repos.md`. Check both first. No need to ask.

1. Name it after the repository: the last part of its remote URL, or its folder name when it has no remote. Put it beside this wiki.
2. Copy this wiki's `AGENTS.md`, `CLAUDE.md`, `links.md`, `.gitignore`, `.gitattributes`, and `rules/` folder into it.
3. Add `raw/`, `wiki/`, and `data/` folders.
4. Create `index.md` containing `# Index`, `log.md` containing `# Log`, `repos.md` containing `# Repositories`, and `patterns.md` containing `# Patterns`. Don't copy this wiki's `repos.md` or `patterns.md`.

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
