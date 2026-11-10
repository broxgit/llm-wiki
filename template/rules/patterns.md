# Patterns

Read this when the user corrects your work, when you catch a mistake of your own, when review comments land on code an agent helped write, when you finish an operational job likely to come up again, or when compile finds `Feedback:` lines.

The goal: the user never gives the same correction twice. When feedback repeats, turn it into something that prevents it next time.

## Evidence: Feedback lines

Add a `Feedback:` line to your next capture when:

- **review**: a reviewer flags something in code an agent helped write. The user pastes the comments, or you read the merge request.
- **correction**: the user corrects your work or your approach.
- **lesson**: you catch a mistake of your own, with no one correcting you, that a rule would have prevented. It is counted and proposed at the same thresholds as a correction.
- **ask**: the user asks for something the wiki shows they have asked for before.
- **procedure**: an operational job that needs judgment on each run, or one the user tells you that you keep doing. Its fix is a skill.
- **toil**: the same commands, edits, or lookups, step for step, every time. No judgment needed, so its fix is a script. When a procedure is mostly toil, use `procedure`: the skill can call a script for the mechanical part.

Record `procedure` and `toil` from the first run. When you finish an operational job, such as a release, a deploy, setting up an environment, a data pull, or regenerating files, and its steps would be the same next time, add the line even if you have never done it before: a later session can't count a run nobody wrote down. Writing or changing code is not such a job. Start the rule with the job's name, a verb and what it acts on, such as `Release llm-relay:`. Use `here` for a job tied to one repository, and `everywhere` only for the same job done across repositories. When sightings disagree on the kind, keep `procedure`. Where the plugin's hooks run, a reminder says this when a command looks like a release or a deploy. Record the job without it too: it knows only a few commands.

A single command the user asks for, like running the tests again, is not a repeat. A multi-step job is, whoever starts it, and each separate request is a sighting, even in one session. Repeats within one request, like four screens built from one pattern, count as one.

One line per item:

```
Feedback: <kind> | <scope> | <the general rule, in one line>
```

`scope` says who owns the rule:

- `here`: this project's code or work.
- a wiki name: a library, service, or tool that wiki owns. Use it when the rule is about how to use that thing.
- `everywhere`: it holds across projects.

Write the rule, not the incident. Examples:

```
Feedback: review | here | Wrap returned errors with %w and context. No bare `return err`.
Feedback: lesson | here | Run the migration check before pushing a schema change.
Feedback: correction | go-common | Services using go-common's HTTP middleware get request metrics from it. Don't add metrics for those.
Feedback: procedure | everywhere | Bump a shared proto across the repos that consume it.
Feedback: toil | here | Release llm-relay: tag main, hash the tarball, update the tap formula, check it with brew.
```

Capture the note in the wiki that owns the scope: this wiki for `here`, the named wiki for a library, the shared wiki for `everywhere`. Feedback with two owners makes two notes, one in each wiki. A note can carry several lines. Before choosing the wording, run `wiki.sh patterns`, which lists each wiki's entries and the `Feedback:` lines in notes not compiled yet, or read the owning wiki's `patterns.md`. If an entry or a waiting line already covers it, use its rule text. Leave out who said it unless it matters to the rule. "Off the record" applies.

## The ledger

Each wiki keeps `patterns.md` at its root. Updating it is compile work, done under the lock. For each `Feedback:` line you ingest:

1. Look for an entry with the same rule, worded any way. If there is one, add a `seen:` line.
2. If there isn't, add an entry with `status: watching`.
3. If the sighting is a review comment, set the entry's kind to `review`, whatever it was. Review comments are the costliest kind.

A feedback-only note needs no topic page. The ledger is its record. The note still gets its `log.md` entry, which marks it compiled.

```
## Wrap errors with context
- kind: review
- rule: Wrap returned errors with %w and context. No bare `return err`.
- status: watching
- seen: 2026-10-27 billing-api raw/2026-10-27-141502-mr-412-review.md
- seen: 2026-10-29 orders-api raw/2026-10-29-090210-mr-87-review.md
```

A `seen:` line is the UTC date, the repository where it happened (`-` if unknown), and the note. When the user or a reviewer says it happened before, add `xN` at the end with the count they give: `x3` for "the last three times", `x2` for "again" or "every time". If it is also happening now, add one: `x4`. One `seen:` line then counts as N sightings. Status is one of `watching`, `proposed YYYY-MM-DD`, `accepted YYYY-MM-DD: <what was done, where>`, or `declined YYYY-MM-DD`.

## When to propose

An entry is ready when it is `watching` and one of these holds:

- 3 sightings
- 2 sightings, and they are review comments. A review round costs the whole team.
- 2 sightings in different repositories

`wiki.sh patterns` lists ready entries across every wiki.

Propose in your reply at the stopping point where the entry became ready, never in the middle of work. Set the entry to `proposed` in the same compile that made it ready, then send the proposal in that reply. A compile with no user to answer, such as one running in the background, leaves the entry `watching`: the next session that sees it ready in `wiki.sh patterns` sets it and asks. One short question per pattern, with the evidence and the fix you suggest:

> Reviewers flagged bare `return err` in 3 merge requests since Oct 9: billing-api !412, orders-api !87, billing-api !431. Add it to billing-api's conventions, so I check for it before calling code done?

When the user answers, set it to `accepted` or `declined`, and on `accepted` make the fix now. Only an answer to a proposal is a decline. "That's fine, just noting it" before a proposal is not one. A user pointing out a repeat wants it fixed, so propose. If the user moves on without answering, ask once more at a later stopping point, best at the end of the session or the start of the next. After that, leave it `proposed`. Lint lists it. Never ask about a declined pattern again unless three new sightings follow the decline. Then ask once more and mention the earlier answer. If an accepted pattern gets sightings after its accepted date, the fix isn't working. Say so. `wiki.sh patterns` marks it `AGAIN`, and `wiki.sh status` counts it.

## The fixes

Pick the smallest fix that would have prevented every sighting.

- **A convention.** For review, correction, lesson, and ask patterns. Add one line to `wiki/conventions.md` in the wiki that owns the scope. Create the page if it's missing, with normal frontmatter, and list it in the index. A correction about how agents should work with the user, such as when to commit or how to write, goes in the shared wiki's page under `## For agents`, so every session in every repository follows it.
- **A note for code that uses a library.** For a rule about using something another wiki owns. Add it to that wiki's `wiki/conventions.md`, under `## For code that uses this`. Every repository that calls the library then gets the rule from one place.
- **A skill.** For a procedure. Propose one skill, with the steps taken from the evidence. Once accepted, write it as `skills/<name>/SKILL.md` in the wiki that owns the scope: the shared wiki for `everywhere`. Give it frontmatter with `name`, and a `description` that says when to use it. Keep the steps in the skill. For facts the steps rely on, such as hosts, flags, or who owns what, cite wiki pages as `name:path` instead of copying them, so a correction reaches the skill too. List it under `## Skills` in that wiki's `index.md`, so agents without skills find it and follow it as a how-to. Then run `wiki.sh skills link`, which links it into `~/.claude/skills` for Claude Code. Everyone who syncs the collection gets it. Never write a team skill into `~/.claude/skills` directly: there, only you would have it.
- **A tool.** For toil. Say what the script would do, about how long it is, and what it saves per run, in steps or tokens. Ask where it should live: the repository's own scripts folder, or a tools repository the user keeps. After it exists, add a how-to page with its path and usage, and use it from then on instead of doing the steps by hand.

## Conventions pages

`wiki/conventions.md` holds rules for code, one line each. Each line names its ledger entry in brackets so the reason can be found.

```markdown
## For this project's code
- Wrap returned errors with %w and context. No bare `return err`. [Wrap errors with context]

## For code that uses this
- Request metrics come from the HTTP middleware. Don't add them in services that use it. [Middleware already records metrics]
```

Before you call code done, read the conventions pages that apply and check your change against every line:

- this wiki's
- the shared wiki's
- those of the wikis that own the internal libraries and services your change calls. Read only the `## For code that uses this` section of those.

Fix what doesn't comply before telling the user the work is done. Keep each page under about 50 lines. When it grows past that, group the lines under subheadings.
