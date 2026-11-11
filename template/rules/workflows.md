# Workflows: where a session is

Read this when session start says the session's folder matched no pattern, or when the user says a pattern is wrong.

Not everyone works in one repository at a time. Some people start a session in a folder for a ticket, which holds clones of the repositories the ticket touches. Never guess silently about that. Session start says which wikis it used and why, and what the user tells you about how they work is kept, so they are asked once.

None of this applies inside a git repository: its wiki is the session's.

## What session start says

For a folder that is not in a git repository, it says one of three things. Pass it on in one line of your first reply.

- **The folder matched a pattern.** Say which pattern you recognised and what it gave, and that the user can say so if it is wrong. Ask nothing.
- **No pattern, and the folder holds clones that have wikis.** Those wikis are in use. Say so, and ask once whether folders like this one always work this way.
- **No pattern, and nothing to go on.** The shared wiki is in use. Say so, and ask whether they want llm-wiki used for this work at all.

Ask in that first reply, in a sentence or two, and carry on with what the user asked for. Their request doesn't wait for the answer.

## Asking, and keeping the answer

**When the guess was good.** Ask whether folders like this one always work this way. On a yes, show the pattern session start offered, and record it once they agree:

```
wiki.sh workflows add '~/repos/*-[0-9]*' inside
```

If only this one folder works that way, record its own path. If the guess was wrong, ask which wiki the work belongs to and record that.

**When there was nothing to go on.** Ask whether they want llm-wiki used here. On a yes, ask how the folder is laid out: which wiki or wikis this kind of work belongs to, and whether other folders are like it. Then ask whether to remember it, and record what they said. On a no, offer to remember that, so the question isn't asked again:

```
wiki.sh workflows add '~/scratch/*' none
```

What a pattern can say:

| Last word | A session in a matching folder uses |
|---|---|
| `inside` | the wikis of the repositories cloned directly inside it |
| a wiki's name | that wiki |
| `none` | no wiki. llm-wiki stays out of the session |

**The pattern.** It is a full path starting with `~/` or `/`, and may hold `*`, `?` and `[...]`. A `*` stops at a slash, so `~/repos/*` covers the folders directly inside `~/repos` and nothing deeper. Propose the narrowest pattern that fits what the user described, show it, and record it only when they agree. The first line that fits a folder wins, and a path with no wildcard is put ahead of the patterns.

**If they would rather not have it remembered,** record nothing and don't ask again in this session.

After recording, sync the shared wiki, so their other machines know. The line is the record. Capture a note as well only when the user said why they work that way.

## When a pattern is wrong

The user says so, at any point. Run `wiki.sh workflows` to see the lines. Adding a pattern that is already there changes it. `wiki.sh workflows remove '<pattern>'` takes one out. `wiki.sh workflows check <folder>` says what a session in a folder would be told. Then use the wikis they named for the rest of the session.

## Where patterns live

In `workflows.md` at the root of the shared wiki, one line each:

```
- in `~/repos/*-[0-9]*`: the wikis of the repositories inside.
- in `~/notes`: `global`.
- in `~/scratch/*`: no wiki.
```

They describe one person's habits. Session start reads the lines that start with `- in`. Use the command, so the shape stays one a script can read. Edit the file by hand only to reorder lines.
