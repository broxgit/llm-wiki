# The llm-wiki tour

You are about to show the user what llm-wiki does, by doing it. These are instructions to you, not text to paste.

A sandbox is ready at `@DIR@`: a collection of three wikis in `wikis/` about a made-up webhook service, and that service's code in `code/`. Every feature below does real work there.

## Rules for the whole tour

- **Use the sandbox's command for everything: `@W@`.** It stands in for `wiki.sh` wherever the sandbox's handbook says that, and it can't reach the user's real wikis or settings. Chapter 8 is the one exception, and it only reads.
- **Nothing from the tour is knowledge.** Harbor-api is made up. Don't capture any of it, journal it, or log lookups for it in the user's real wikis. Real work that comes up mid-tour follows the real handbook as usual.
- **One chapter per reply.** Say in a sentence or two what the chapter shows, do it, and show the result briefly: the command's useful lines, not all of its output. End with the one thing to try next, and wait. "Next", "skip" and "stop" are always fine. Answer questions as they come.
- **Let the user drive where the guide says so.** Give them the sentence to say, and let them say it. If they'd rather watch, say it for them and carry on.
- **Say what's normally invisible.** Most of this happens without being asked. Each chapter ends by saying which part the agent does on its own, and which part the user would ever need to say.
- **Be honest about the staging.** The problems in the sandbox were planted so that they turn up quickly, and its commits and notes were made when the sandbox was built. Say so if asked. Real wikis get them more slowly.
- **The sandbox has a real handbook, and this guide sets its order.** Follow `@DIR@/wikis/harbor-api/AGENTS.md` and its `rules/` for how to do each step. If you've read the same handbook version this session, don't read it again. Three things wait for their chapter, whatever the handbook or `start` says about when: compile waits for chapter 3, lint and stale findings for chapter 4, and the pattern proposal for chapter 5. Skip the handbook's step of logging lookups to `stats.csv`.

## Start

Say in a few lines that this runs on a made-up project, so it can't touch their wikis, and that it's about 10 minutes for the short version. Offer the choice: the short version (chapters 1 to 4), all of it, or a chapter by topic. List the chapter titles. If they already named a topic, go straight there.

## 1. It answers from what's been worked out

Run `@W@ start harbor-api`. This is what a session reads first, and it's short. Show the harbor-api part of the index and say that's all it has loaded so far.

Invite them to ask: **"Why is the delivery queue in Postgres and not Redis?"**

Answer as the handbook says: pick the page from the index, read only that, answer in a few lines, and cite the path. Point out that you didn't read the code or any old conversation, and that the answer holds the reason, including what was tried and turned down, which the code can't say.

On its own: all of it. They just ask.

## 2. It saves what matters

Invite them to say: **"We're dropping XML payloads at the end of Q3, because only two customers still use them. Save this."**

Save it with `@W@ capture harbor-api drop-xml-payloads`, piping the note in, and show the file. A note is a new file in `raw/`, in plain markdown, and it changes nothing else, so several sessions can capture at once.

Then say what you'd save without being told: decisions and why, their corrections, root causes, findings. Say what you wouldn't: small talk, guesses, and a log of finished work, since git already holds that. "Don't save that" and "off the record" leave one thing out. "Leave the wiki alone" stops all writes.

On its own: capturing at stopping points. "Save this" is only for when they want it now.

## 3. Notes become pages

Run `@W@ pending harbor-api`. Their note is waiting, with two planted ones. If chapter 2 was skipped, there are just the two.

Read `@DIR@/wikis/harbor-api/rules/compile.md`, `rules/conflicts.md` and `rules/patterns.md`, and compile for real: take the lock, write the pages, add the sighting to `patterns.md`, run `@W@ index harbor-api`, log, release, then `@W@ sync harbor-api -m "harbor-api: compile"`. There's no remote, so sync only commits. Link any new page from a page it relates to. Show the new page and its line in the index, and the counts. Don't run lint: it isn't due. Leave the pattern's status at `watching`, and don't mention it yet, because chapter 5 is about it.

One note says customers can send 1 MB, and the existing page says 256 KB. Neither corrects the other, so you must flag it and not pick. Show the `Conflict:` line on the page, and ask them: **"Which is right, 256 KB or 1 MB?"** Whatever they say, resolve it the way `rules/conflicts.md` says, keeping what the other claim said.

On its own: compiling at session start, at a pause, or when five notes wait. The only part left to them is the ruling on a contradiction.

## 4. It checks itself

Invite them to ask: **"How many times do we retry a failed delivery?"**

`wiki/concepts/webhook-retries.md` says 6, and it was last verified long ago. Run `@W@ stale`, which lists it, before you change anything, since it won't afterwards. Say that before acting on a claim, you check it against its origin when it's at hand. So read `@DIR@/code/harbor-api/delivery/retry.go`. It says 8, and `git -C @DIR@/code/harbor-api log --oneline` shows the commit that changed it.

A claim you checked and found false is a correction, so you fix it without asking. Capture a short note saying what you checked and found, then compile it under the lock: the page, its summary, `verified` and `commit`. Show the diff. Then run `@W@ lint harbor-api`, which finds the broken link planted in `wiki/decisions/postgres-queue.md`. That's the mechanical check only: the full pass in `rules/lint.md` isn't due. Fix the link without asking, because lint counts that as mechanical: the on-call page doesn't exist, so keep the words and drop the link. Say what you'd ask about first: merging, deleting or moving pages.

On its own: all of it, and lint comes due after 10 compiles. The wrong answer from memory, the one this prevents, is the failure llm-wiki exists for.

## 5. The same correction doesn't come twice

Run `@W@ patterns`. If chapter 3 was skipped, compile first, since a note there holds the second sighting. "Wrap errors with context" shows as READY: two review comments on different merge requests.

Propose the fix the way `rules/patterns.md` says, in one short question with the evidence: **add it to harbor-api's conventions, so it gets checked before code is called done?** Set the entry to `proposed` when you ask. If they say yes, add the line to `wiki/conventions.md`, and set the entry to `accepted`. Say that every later session in this repository reads it, whichever agent runs it, and that repeated procedures become skills and repeated toil becomes scripts the same way.

On its own: counting and proposing. They only answer yes or no.

## 6. Knowledge has one home

Invite them to ask: **"What does billing need from our delivery events?"**

The index for harbor-api doesn't hold it, but its queue page cites `billing:wiki/concepts/invoice-events.md`. Read that page in the peer wiki and answer. Then run `@W@ find postgres`, which searches every wiki for one word, and show the shared wiki's page turning up.

Say how it's split: one wiki per project, named after the repository, plus a shared one for what holds everywhere. A lesson about another project goes in that project's wiki, once, and everything else cites it. Teammates get it through git. A project over several repositories lists them with `wiki cover`.

On its own: all of it.

## 7. What did I do?

Run `@W@ journal note harbor-api "Traced a slow retry to one customer's endpoint. No fix needed."` Then run `@W@ standup --since today`, and write the result up as a short standup, as `@DIR@/wikis/harbor-api/rules/journal.md` says. Commits, the journal line and the wiki's notes all land in it, which is why work that left no commit still counts.

On its own: the journal lines. They say "give me my standup". `wiki report` is the weekly version, with tokens per project and a list of what needs them.

## 8. Your own setup

Leave the sandbox. These commands read the user's real setup, and change nothing:

- `@REAL@ status`
- `@REAL@ tips`
- `@REAL@ which`, from the repository this session is working in, if there is one

`status` lists every wiki by name, so summarize it instead of reading it out, in case they're sharing their screen. A lock held by another session is normal, not a problem to raise. If `status` says there's no collection, say that `@REAL@ setup` in a terminal is the place to start, and that it's theirs to run. Otherwise pick the one to three things that would help them most, and say why from what you just read, with what you'd do. If this repository has no wiki, or a nearly empty one, the first is `wiki seed`. `wiki seed --dry-run`, run in the repository, shows what it would take. Ask before doing anything real.

Mention what's left out only if it fits how they work, in a line each: `wiki harvest` copies an agent's own memory notes into the wikis, team skills in `skills/` reach everyone who syncs, delegation hands busywork to cheaper models, `wiki mcp` reaches the wikis from the desktop app's Chat tab, and `wiki relay` works with Microsoft Copilot Cowork.

## Finish

Close with what to say from now on, which is nothing most of the time, then: "save this", "compile", "lint", "give me my standup", "don't save that", "leave the wiki alone". The full list is under "What to say" in `docs/using.md`.

Offer to remove the sandbox with `@REAL@ tour --clean`, and run it if they agree. Its notes go with it. Nothing was added to their real wikis.
