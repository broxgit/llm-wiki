# What uses what

Read this when you learn that one repository uses another, and before you change something other repositories use: a library's public functions, a service's API, a message's shape, a shared table.

Wikis hold what each project knows about itself. This is what joins them: which repository imports, calls or reads from which. It is built up one link at a time, by the sessions that see the links.

## Record a link when you see one

When your work shows that one repository uses another, add a `Uses:` line to your next capture:

```
Uses: <the repository that uses> -> <the repository used> | <how>
```

```
Uses: checkout-handler -> auth-service | calls POST /v1/tokens over HTTP, in internal/auth/client.go
Uses: checkout-handler -> go-common | imports pkg/retry
Uses: billing-worker -> orders-service | reads the orders.created queue
```

- One line for each link. Name both repositories as their wikis are named.
- Say how in a few words: the package, the endpoint, the queue, the table. Add the file when you have it.
- Only what you saw: in code, in configuration, in a log. Never a guess, and never what a name suggests.
- A link you already find on the page needs no new line, unless how it is used has changed.
- When you see that a link is gone, say so the same way: `Unused: <user> -> <used> | <what was removed>`.

The note goes to the wiki of the repository that does the using. If this session is in neither repository, it still goes there.

## At ingest

For each `Uses:` line, keep one page in each of the two wikis, `wiki/dependencies.md`, with two sections:

```markdown
## Uses

- auth-service: calls POST /v1/tokens over HTTP, in internal/auth/client.go (seen 2026-01-15)
- go-common: imports pkg/retry (seen 2026-01-15)

## Used by

- billing-worker: reads the orders.created queue (seen 2026-01-15)
```

1. In this wiki, add or replace the line under `## Uses`. One line for each repository and each way it is used. The date is the note's `Captured:` date.
2. In the wiki of the repository that is used, add or replace the matching line under `## Used by`. That is a write to another wiki, so `rules/peers.md` applies. Cite the note as `<this wiki>:raw/<file>`. If no wiki covers that repository, keep only the `Uses` side.
3. For an `Unused:` line, remove the line from both pages.
4. Keep each section sorted by name. The page's summary says how many of each it holds.

A note with only such lines needs no other page, and still gets its `log.md` entry.

## Packages are mapped for you

`wiki.sh deps` reads `go.mod`, `package.json` and `pyproject.toml` in the repositories the wikis cover, and prints which repository owns each package and which repositories import it. `wiki.sh deps --write` saves that as `data/dependencies.csv` in the shared wiki.

So don't write a `Uses:` line just to say that a package is imported: the command already knows. Write one for what a module file can't show: a service called over the network, a queue, a shared database, a configuration that names another system. And write one when how a package is used is worth knowing, such as the one function everything depends on.

## Before you change something others use

1. Read `wiki/dependencies.md` in that repository's wiki, under `## Used by`.
2. For a package, run `wiki.sh deps` and look for it.
3. Search for its name: `wiki.sh find <name>`.

Tell the user who is affected before you make the change, and name where each answer came from. Say too that the list holds only what sessions have seen and what module files show, so a repository missing from it may still use the thing.
