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
- `wiki.sh capture` warns about a `Waiting:` or `Due:` line not in this form. Fix the note before it is compiled.

For example, `Done: Confirm the Gemini reminder hook` closes the entry shown below.

Work the user puts off goes in the owning repository's `ROADMAP.md`, or its equivalent, when it has one. Use these lines when there is none.

## Ticket lines

`wiki.sh capture` ends a note with `Ticket: <KEY>` when the session's folder, or its branch, is named for a ticket. Leave the line there. It ties the note's `Waiting:` and `Due:` lines to that ticket. Where the Jira extension is set to close items, an entry whose heading names the ticket closes when the ticket is done. One tied only by this line stays open, and an entry that begins `Jira:` asks whether it is finished too. Ask the user. On a yes, close the entry with a `Done:` line. On a no, close only the question.

- An item that isn't about that ticket goes in a note of its own that ends with `Ticket: none`. Capture adds nothing to a note that has a `Ticket:` line, so the entry closes only with a `Done:`, and nothing asks about it.
- A note about another ticket ends with that ticket's line, such as `Ticket: PROJ-123`.

Compile does nothing with the line: it stays in the note, and the entry's `from:` line is what leads to it.

## The ledger

Each wiki keeps `open.md` at its root. Updating it is compile work, done under the lock. For each line you ingest:

1. `Waiting:` or `Due:`: look for an open entry with the same what, worded any way. If there is one, add a `from:` line to it. If there isn't, add an entry.
2. `Done:`: find the open entry whose heading contains the text, ignoring case. Of several, take the one whose heading is the text, if one is; if that one is already done, leave the others alone. Set its status to `done <the note's date>` and add a `from:` line for the closing note. If it matches no entry, or more than one, say so in your compile report and leave the ledger alone.

With the script, use its commands for both steps, and don't edit the file by hand. Each writes the entry as shown below and refuses text that would break it.

- `wiki.sh open add <wiki> "<what>" --who <who> --from raw/<note>` for a `Waiting:` line, or `--due <YYYY-MM-DD>` in place of `--who` for a `Due:` line. When an open entry has the same what worded another way, use its heading: the command adds the `from:` line to it, and says when the entry keeps a who or a date other than yours.
- `wiki.sh open done <wiki> "<text>" --from raw/<note>` for a `Done:` line. It refuses, and changes nothing, when the text matches no open entry or more than one. Put what it says in your compile report.

Both date the entry by the note unless you give `--date`.

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
