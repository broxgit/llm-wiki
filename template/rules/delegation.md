# Delegation

Read this when a large task comes up that a sub-agent could do, when you're about to start one, or when the user asks about handing work to other models.

The goal: spend the expensive model on judgment, and a cheaper one on volume, without losing quality. Handing work off is not free. A sub-agent starts with none of this conversation. You pay to brief it, and you pay again to check what comes back. It wins only on work big enough to beat that cost.

## The preferences file

`delegation.md` in the wiki collection's top folder, the folder above this wiki, holds the user's choices. Read it once per session, the first time a handoff comes up. It belongs to one person on one machine, so git ignores it and its log. Never commit either.

- `mode: off`: never hand off on your own. Do it only when the user asks.
- `mode: ask`: suggest each handoff and wait for a yes. This is also the rule when the file is missing.
- `mode: auto`: hand off on your own, and say so in your reply.
- **Who does what**: a table of kinds of work and the model and effort for each. `stay` means keep it in this session.
- **Auto**: kinds of work the user approved for handoff without asking, even in `ask` mode.

If your tool can't run a sub-agent on a chosen model, skip this file. Do the work yourself.

## When to hand off

All three must hold:

1. **Self-contained.** You can brief it in a short paragraph. It doesn't need this conversation's history to get right.
2. **Big.** Done here, it would take many tool calls or a lot of reading: roughly ten or more files read, or long output to scan.
3. **Checkable.** You can confirm the result cheaply: tests pass, counts match, a spot check of a few items holds up.

Good fits: sweeping many files for something, running tests or builds and summarizing failures, link checks, data extraction, boilerplate that copies an existing pattern, first drafts of docs from code.

Never hand off: design decisions, subtle debugging, code review, security-sensitive changes, or anything where a mistake would be expensive and hard to spot. Never hand off work the table marks `stay`.

When the task mixes volume and judgment, split it. The sub-agent gathers: it runs the tests, makes the inventory, collects the facts. You keep the judgment: why a test fails, what to recommend.

Pick the model and effort from the table. If no row fits, use the cheapest tier you'd trust with it and say which in your suggestion.

## Asking

In `ask` mode, suggest it in one line before you start, and bundle several handoffs into one question:

> The test run and failure summary can go to Sonnet, low effort. OK?

On a yes, go ahead. On a no, do it yourself and don't ask again for that task.

## Briefing

The brief is everything the sub-agent knows. Include:

- the goal, in one or two sentences
- exactly where to look: paths, repositories, commands
- what is already known or ruled out
- limits: what not to touch, whether it may edit files
- what to return, and in what shape, kept short

## Checking

Before you rely on the result, check it the way criterion 3 promised: run the tests, recount, open two or three of the items it reported. If it's wrong, fix it, or redo the work yourself.

## The log

After each handoff, log it: `wiki.sh delegation log <kind> <model> <effort> <ok|fixed|redone>`. Without the script, append one line to `delegation-log.csv` in the collection's top folder. Create it with this header if it's missing:

```
date,project,kind,model,effort,result
2026-10-27,orders-api,test run,sonnet,low,ok
```

`date` is UTC. `kind` is a short phrase with no commas, such as `test run`, `file sweep`, or `boilerplate`. Use the same phrase each time for the same kind of work. `result` is `ok` (used as returned), `fixed` (you corrected it), or `redone` (you did it yourself). `wiki.sh delegation` sums the log.

## Making it a rule

- When the user has said yes to the same kind of handoff three times, ask once whether to add that kind to the **Auto** list. On a yes, add the kind there. If the user says so directly ("do test runs without asking"), add it right away.
- An Auto entry is one line starting with `- `, in the user's own words, such as `- test runs`. It doesn't have to match a table row.
- When the log shows that kind of handoff `redone` twice in its last five, suggest a stronger model for it, or `stay`.
- Edit `delegation.md` only after the user agrees. A change to the mode line comes from the user, or from `wiki.sh setup delegation`.
