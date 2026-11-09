# Open items

Read this when you add a `Waiting:` or `Due:` line to a capture, close one with `Done:`, or compile a note that has one.

Some things can't be finished in a session. They wait for someone, or for a date. A conversation forgets them, so they go in a capture, and compile tallies them into a ledger, as it does `Feedback:` lines.

## Evidence: Waiting, Due and Done lines

```
Waiting: <who> | <what>
Due: <YYYY-MM-DD> | <what>
Done: <what>
```

- `Waiting:` is for something that can't move until someone acts. `who` is `user`, a name, or a team. A claim nobody has tested yet is a `Waiting:` on whoever can test it.
- `Due:` is for something to look at on or after a date.
- `Done:` closes one. Use the entry's heading, or enough of it to pick one open entry.
- Write the what so it stands alone in a list. Someone who sees only that line should know what to do.

For example, `Done: Confirm the Gemini reminder hook` closes the entry shown below.

Work the user puts off goes in the owning repository's `ROADMAP.md`, or its equivalent, when it has one. Use these lines when there is none.

## The ledger

Each wiki keeps `open.md` at its root. Updating it is compile work, done under the lock. For each line you ingest:

1. `Waiting:` or `Due:`: look for an open entry with the same what, worded any way. If there is one, add a `from:` line to it. If there isn't, add an entry.
2. `Done:`: find the open entry whose heading contains the text, ignoring case. Set its status to `done <the note's date>` and add a `from:` line for the closing note. If it matches no entry, or more than one, say so in your compile report and leave the ledger alone.

A note with only these lines needs no topic page. The ledger is its record. The note still gets its `log.md` entry, which marks it compiled.

```
## Confirm the Gemini reminder hook fires in Antigravity
- kind: waiting
- who: user
- status: open
- from: 2026-11-09 raw/2026-11-09-164228-gemini-reminders-check.md
```

A due entry has `- due:` where a waiting one has `- who:`. A `from:` line is the UTC date and the note. Status is `open` or `done YYYY-MM-DD`. A done entry stays, as a record.

## Using it

`wiki.sh open` lists the open entries in every wiki, those past their date first. `wiki.sh status` counts them, and `wiki.sh lint` reports an entry it can't read. When a session ends with entries waiting on the user, say what they are in your last reply.
