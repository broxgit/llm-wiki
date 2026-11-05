# The llm-wiki tour

You are about to show the user what llm-wiki does for them, by doing it. These are instructions to you, not text to paste, except where a passage is quoted for you to say.

A sandbox is ready at `@DIR@`: a collection of three wikis in `wikis/` about a made-up webhook service, and that service's code in `code/`. Every feature below does real work there.

## Rules for the whole tour

- **It's a tour of llm-wiki, not of harbor-api.** The made-up service is only scenery. Say what the user gets from each chapter, in terms of their own work, before any detail of the service. Close every chapter with the **For you** line: what changes for them, what the agent does on its own, and what they'd ever need to say. Say it in your own words, as the point of the chapter.
- **Show the real thing.** Where this guide says to show something, quote the actual lines in a code block, briefly. Don't describe them. Leave out the rest of a command's output. Don't narrate the bookkeeping: the lock, the log and the sync just happen, unless they ask.
- **Plain words first.** The user may not know the terms yet. Say "the short list of pages" before you say "index", "turning notes into pages" before "compile", "the health check" before "lint", and "its rules" before "handbook".
- **Use the sandbox's command for everything: `@W@`.** It stands in for `wiki.sh` wherever the sandbox's handbook says that, and it can't reach the user's real wikis or settings. Chapter 7 is the one exception, and it only reads.
- **Nothing from the tour is knowledge.** Harbor-api is made up. Don't capture any of it, journal it, or log lookups for it in the user's real wikis. Real work that comes up mid-tour follows the real handbook as usual.
- **One chapter per reply,** except where a chapter waits on the user partway. After the **For you** line, end with the next chapter: its name, what they get from it in a line, and the sentence to say if it has one. Then wait. When they say it, go straight on, without inviting it again. The first chapter they see opens with what they get, since nothing came before it. "Next", "skip" and "stop" are always fine. Answer questions as they come.
- **Let the user drive where the guide says so.** Give them the sentence to say, and let them say it. If they'd rather watch, say it for them and carry on.
- **Be honest about the staging.** The problems in the sandbox were planted so that they turn up quickly, and its commits and notes were made when the sandbox was built. Say so if asked, and in chapter 6 without being asked. Real wikis get them more slowly.
- **The sandbox has a real handbook, and this guide sets its order.** Follow `@DIR@/wikis/harbor-api/AGENTS.md` and its `rules/` for how to do each step. If you've read the same handbook version this session, don't read it again. Three things wait for their chapter, whatever the handbook or `start` says about when: compiling waits for chapters 2 and 3, lint and stale findings for chapter 2, and the pattern proposal for chapter 4. Skip the handbook's step of logging lookups to `stats.csv`.

## Start

Say this, keeping its sense and its order, and fitting it to anything they've already told you:

> Your coding agent forgets everything between sessions, and what it does remember goes stale. llm-wiki gives it a memory it keeps up itself: a small markdown wiki for each project, in plain files you own. Almost all of it happens without you asking.
>
> I'll show you on a made-up project, so your real wikis aren't touched. Here's what you get:
>
> 1. A new session already knows why
> 2. It catches its own stale facts
> 3. You say it once, and it keeps it
> 4. You stop repeating corrections
> 5. It knows your other projects
> 6. It writes your standup
> 7. What it would do for you, from your real setup
>
> The first four take about 10 minutes. Do you want those, all of it, or one in particular?

If they already named a topic, say the first paragraph and go straight there.

## 1. A new session already knows why

Say what they get: they stop re-explaining a project at the start of every session.

Set the scene: **pretend you worked on this service months ago, and this is a brand new session. Nothing carries over from the last chat.**

Run `@W@ start harbor-api`. This is what a session reads first, and it's short. Quote the harbor-api lines of the index as they are, and say that this, a similar list from the shared wiki and a few rules are all it has read so far. None of it is code.

Invite them to ask: **"Why is the delivery queue in Postgres and not Redis?"**

Answer as the handbook says: pick the page from the index, read only that, answer in a few lines, and cite the path. Then point out what just happened: you didn't read the code or any old conversation, and the answer holds the reason, including what was tried and turned down, which the code can't tell you.

For you: you never re-explain this, and you don't ask for any of it. You just ask your question.

## 2. It catches its own stale facts

Say what they get: an agent with a memory can be confidently wrong, and this is what stops that.

Invite them to ask: **"How many times do we retry a failed delivery?"**

`wiki/concepts/webhook-retries.md` says 6, and it was last verified long ago. Run `@W@ stale`, which lists it, before you change anything, since it won't afterwards. Say that a memory alone would answer 6, and that before acting on a claim you check it against its origin when it's at hand. So read `@DIR@/code/harbor-api/delivery/retry.go`. It says 8, and `git -C @DIR@/code/harbor-api log --oneline` shows the commit that changed it. Quote those lines.

A claim you checked and found false is a correction, so you fix it without asking. Read `@DIR@/wikis/harbor-api/rules/compile.md` and `rules/conflicts.md`. Capture a short note saying what you checked and found, then compile that note alone, naming it as the source, so the two notes already waiting keep for chapter 3: take the lock, fix the page, its summary, `verified` and `commit`, run `@W@ index harbor-api`, log it with `--source`, release, and `@W@ sync harbor-api -m "harbor-api: correct the retry count"`. Show the diff.

Then run `@W@ lint harbor-api`, the health check, which finds the broken link planted in `wiki/decisions/postgres-queue.md`. It also lists the two waiting notes, which chapter 3 takes. That's the mechanical check only: the full pass in `rules/lint.md` isn't due. Fix the link without asking, because lint counts that as mechanical: the on-call page doesn't exist, so under the lock, keep the words and drop the link, log it as `rules/lint.md` says, release, and sync. Say what you'd ask about first: merging, deleting or moving pages.

For you: the wrong answer from memory is the failure llm-wiki exists to prevent, and all of this happens on its own. The full health check comes due after every 10 rounds of turning notes into pages.

## 3. You say it once, and it keeps it

Say what they get: a decision outlives the chat it was made in, without them writing anything down.

Invite them to say: **"We're dropping XML payloads at the end of Q3, because only two customers still use them. Save this."**

Save it with `@W@ capture harbor-api drop-xml-payloads`, piping the note in, and show the file. A note is a new file in plain markdown, and it changes nothing else, so several sessions can save at once. Say what you'd save without being told: decisions and why, their corrections, root causes, findings. Say what you wouldn't: small talk, guesses, and a log of finished work, since git already holds that. "Don't save that" and "off the record" leave one thing out. "Leave the wiki alone" stops all writes.

Now turn the notes into pages. Run `@W@ pending harbor-api`. Their note is waiting, with two from earlier sessions. If they skipped the sentence above, there are just the two.

Read `@DIR@/wikis/harbor-api/rules/compile.md`, `rules/conflicts.md` and `rules/patterns.md` if you haven't, and compile for real: take the lock, write the pages, add the sighting to `patterns.md`, run `@W@ index harbor-api`, log, release, then `@W@ sync harbor-api -m "harbor-api: compile"`. There's no remote, so sync only commits. Link any new page from a page it relates to. Show the new lines in the short list, and say that's what the next session sees. Leave the pattern's status at `watching`, and don't mention it yet, because chapter 4 is about it.

One note says customers can send 1 MB, and the existing page says 256 KB. Neither corrects the other, so you must flag it and not pick. Say that a tool that just overwrites would have lost one of these. Show the `Conflict:` line on the page, and ask them: **"Which is right, 256 KB or 1 MB?"** Then wait for them, and leave the **For you** line until they've ruled.

Whatever they say, capture their ruling in a short note so the page can cite it, and resolve it the way `rules/conflicts.md` says, keeping what the other claim said. Show the line that replaced the flag.

For you: it saves at stopping points, and turns notes into pages at session start, at a pause, or when five wait. All that's left to you is the ruling when two facts clash. "Save this" is only for when you want it now.

## 4. You stop repeating corrections

Say what they get: if they've ever made the same review comment twice, this is for them. The agent counts repeats, and offers to make them a rule.

Run `@W@ patterns`. If chapter 3 was skipped, compile the waiting notes first, since one holds the second sighting. "Wrap errors with context" shows as READY: two review comments on different merge requests. Quote the lines.

Propose the fix the way `rules/patterns.md` says, in one short question with the evidence: **add it to harbor-api's conventions, so it gets checked before code is called done?** Set the entry to `proposed` when you ask. If they say yes, add the line to `wiki/conventions.md`, and set the entry to `accepted`.

For you: every later session in the repository checks its code against that rule before calling it done, whichever agent runs it. Repeated procedures become skills and repeated toil becomes scripts the same way. It counts and proposes on its own, and you only answer yes or no.

If this was the last chapter they asked for, offer the rest in a line, and go to Finish unless they want more.

## 5. It knows your other projects

Say what they get: what was learned on one project is there when another one needs it, without copying it around.

Invite them to ask: **"What does billing need from our delivery events?"**

The index for harbor-api doesn't hold it, but its queue page cites `billing:wiki/concepts/invoice-events.md`. Read that page in the peer wiki and answer. Then run `@W@ find postgres`, which searches every wiki for one word, and show the shared wiki's page turning up.

Say how it's split: one wiki per project, named after the repository, plus a shared one for what holds everywhere. A lesson about another project goes in that project's wiki, once, and everything else cites it. A project over several repositories lists them with `wiki cover`.

For you: teammates get all of it through git, and you never have to say where anything lives.

## 6. It writes your standup

Say what they get: they can ask what they did, and the answer includes work that left no commit.

Run `@W@ journal note harbor-api "Traced a slow retry to one customer's endpoint. No fix needed."` Then run `@W@ standup --since today`, and write the result up as a short standup, as `@DIR@/wikis/harbor-api/rules/journal.md` says. Commits, the journal line and the wiki's notes all land in it. Leave out compile and lint bookkeeping. The commits were made when the sandbox was built, which is why they show as today's: say so in a line, and don't credit them to the user as today's work.

For you: the journal lines are written on their own, and you just say "give me my standup". `wiki report` is the weekly version, with tokens per project and a list of what needs you.

## 7. What it would do for you

Say what they get: everything so far was staged, and this is about their real setup.

Leave the sandbox. These commands read the user's real setup, and change nothing:

- `@REAL@ status`
- `@REAL@ tips`
- `@REAL@ which`, from the repository this session is working in, if there is one

`status` lists every wiki by name, so summarize it instead of reading it out, in case they're sharing their screen. A lock held by another session is normal, not a problem to raise. If `status` says there's no collection, say that `@REAL@ setup` in a terminal is the place to start, and that it's theirs to run. Otherwise pick the one to three things that would help them most, and say why from what you just read, with what you'd do. If this repository has no wiki, or a nearly empty one, the first is `wiki seed`. `wiki seed --dry-run`, run in the repository, shows what it would take. Ask before doing anything real.

Mention what's left out only if it fits how they work, in a line each: `wiki harvest` copies an agent's own memory notes into the wikis, team skills in `skills/` reach everyone who syncs, delegation hands busywork to cheaper models, `wiki mcp` reaches the wikis from the desktop app's Chat tab, and the separate `relay` tool (llm-relay) works with Microsoft Copilot Cowork.

## Finish

Close with the point: from now on they mostly say nothing, and just work. Then the few things worth knowing: "save this", "compile", "lint", "give me my standup", "don't save that", "leave the wiki alone". The full list is under "What to say" in `docs/using.md`.

Offer to remove the sandbox with `@REAL@ tour --clean`, and run it if they agree. Its notes go with it. Nothing was added to their real wikis.
