# News

What's new in llm-wiki outside the handbook, written for the person using it. Handbook changes are in `CHANGELOG.md`. `wiki update` and `wiki news` print what you haven't seen, and `wiki status` says when there's something new.

Format: one `## YYYY-MM-DD: title` section per entry, newest first. Each title is different. Under it, one line starting `- ` for each change a user would notice, four at most, and nothing else. Leave out what they wouldn't notice: the pull request has that. Add a `- Do:` line only when there is something for them to do. `wiki update` prints these as they are, so a long entry is a long update.

## 2026-11-09: `wiki sync` makes one trip to the remote

- `wiki sync` pushes first and pulls only when the remote has moved, so a sync takes about half the time.
- With nothing to push it pulls and says `up to date`. It says `synced:` only when something was pushed.

## 2026-11-09: `wiki open` lists what's waiting

- `wiki open` lists what agents recorded as waiting on someone or due on a date, across your wikis, with the ones past their date first.
- `wiki status` adds a line to its To do list when anything is open.
- With the plugin, opening a wiki page logs a lookup by itself, and a subagent's start shows in `wiki delegation` as OPEN until its outcome is recorded.

## 2026-11-09: `wiki report` splits lookups from upkeep

- The report's token tables now say how much of new input went to lookups (reads, searches, session starts) and how much to upkeep (captures, compiles, syncs).
- Calls through the wiki MCP tools (`wiki_search`, `wiki_capture` and the rest) are now counted. They were missing from the figure.
- Gemini's table gets the same line. The two tools' figures are not added together.

## 2026-11-09: `wiki find` takes a phrase

- `wiki find deploy token` searches for the phrase, as if quoted, where it said only "too many arguments".

## 2026-11-07: Gemini gets the wikis' reminders

- Gemini in Antigravity now gets a wiki's `before` and `on` reminders at the tool calls they apply to. Quit and reopen Antigravity once.

## 2026-11-06: Chat says "Pushed" only when a note was pushed

- Chat said "Pushed." for a note it saved where the wikis have no remote or no git repository of their own. It now says why the note wasn't pushed.

## 2026-11-06: `wiki find` gets faster

- `wiki find` is three to six times faster: about 40 ms where it took 120 to 250. So is the MCP server's search.
- It prints the same in any locale: a page's line is cut at 120 bytes and never inside a character, and an accented letter matches only in its own case.

## 2026-11-06: `wiki which` says when it can't read

- `wiki which` says it can't read a wiki folder or the collection, where it said no wiki covers the repository.

## 2026-11-06: Reminders for files stay inside the project

- A reminder for files, such as `payments/*`, no longer matches a folder of that name above the project.
- A background run that compiled none of its notes is recorded as `none`, where it said `partial`.
- `wiki start` leaves citations out of the rules it prints, and `wiki log --help` lists its options.

## 2026-11-06: Background compile counts its runs right, and a sandbox's refusals are named

- Background compile no longer records a run that finished as `partial` or `timeout`.
- Inside another agent's sandbox, commands say what they can't read or run, where they called it missing, old or empty.

## 2026-11-05: Fixes from a test run in another agent's sandbox

- `wiki lint`, `wiki stale` and `wiki deps` work when a folder under your code folders can't be read.
- With background compile on, `wiki start` says so when it can't start a run.
- In a reminder's pattern only `*` is special, so a pattern with `[` or `?` in it matches what it says.

## 2026-11-05: wiki journal backfill gets faster too

- `wiki journal backfill` writes its digest several times faster. The digest is the same.

## 2026-11-05: wiki report and standup get several times faster

- `wiki report` and `wiki standup` run several times faster with a small helper that `wiki update` downloads, about 3 MB.
- Nothing needs the helper. `wiki helper` says which is in use, and `wiki helper auto off` stops session start fetching it.

## 2026-11-05: The tour says what it's for

- The tour opens with what llm-wiki does for you, and each chapter ends with what changes for you.
- Do: if you stopped partway, run `wiki tour --clean`, then ask for the tour again.

## 2026-11-05: wiki relay is now its own tool

- The Copilot Cowork relay moved to its own tool, [llm-relay](https://github.com/broxgit/llm-relay). `wiki relay` now only says where it went.
- Do: if you use Copilot Cowork, install `relay` as its README says, and run `relay setup`.

## 2026-11-05: Reminders at the moment a rule applies

- A wiki can say when a rule applies, and Claude Code puts it in front of the agent then. The changelog for handbook v28 has the format.
- Do: restart open sessions, so they load the new hook.

## 2026-11-05: Notes can be compiled in the background, as an experiment

- `wiki compile on` has session start hand waiting notes to a background run, so sessions don't start by compiling. It is off by default.
- `wiki compile` shows the setting and how the last runs went. `wiki compile --help` has the rest.
- Do: to try it, run `wiki compile on`, and read a few of the pages it wrote before trusting it.

## 2026-11-05: Take the tour

- Ask your agent "Give me the llm-wiki tour" to learn the features by doing them on a made-up project. About 10 minutes, and your wikis aren't touched.

## 2026-11-05: Wikis in a second collection get found from anywhere

- A wiki in a second collection is found from any folder, and by the Chat tab too.
- A flag with no value, such as `wiki standup --since`, says so, where it used to exit with no message.

## 2026-11-04: Cowork reviews can see test results and say what they skipped

- The Cowork relay can run your Go checks on a copy of a merge request's branch and send Cowork the results. It asks first.
- Cowork's reviews end with a Coverage section saying what it read and what it skipped.

## 2026-11-04: Review merge requests with Copilot Cowork

- The Cowork relay sends a merge request's discussions, diff and branches for review, and saves the review where you keep yours.

## 2026-11-04: Show Copilot Cowork another branch

- The Cowork relay can share another branch, such as `master`, without you leaving yours.

## 2026-11-04: Copilot Cowork reads a repository's wiki

- A relay scan also sends the wiki that covers the repository: its index and compiled pages only, as a read-only copy.
- Do: check that your company allows that wiki's content in OneDrive, or scan with `--no-wiki`.

## 2026-11-04: wiki relay, so you stop attaching files to Copilot Cowork

- A round with Copilot Cowork is one command, one keypress, and telling Cowork "done". Nothing is attached by hand.

## 2026-11-03: Copilot Cowork can change code through runs on your Mac

- Copilot Cowork can work on a real repository without reaching it: it publishes a folder to OneDrive, and you run one command.

## 2026-11-03: Microsoft 365 Copilot can read your wikis

- `wiki setup microsoft-copilot --repo OWNER/REPO` lets a work or school Copilot answer from one wiki repository on GitHub, read-only.
- `wiki news` shows this list, and `wiki status` says when there's something unread.

## 2026-11-02: Search counts in the weekly report

- The weekly report counts searches that found something and sessions that opened wiki pages. It no longer shows a hit rate.

## 2026-11-01: The Claude desktop app's Chat tab and claude.ai

- `wiki setup chat` gives the desktop app's Chat tab tools to search, read and save to your wikis.
- A private claude.ai Project can read a collection through its GitHub connector. It can't save notes.
- Do: if you use the Chat tab, run `wiki setup chat` in the Terminal app, and add the line it prints to your profile preferences.

## 2026-10-30: Codex and Cursor setup

- `wiki setup codex` and `wiki setup cursor` give Codex and Cursor sessions their wiki at the start, loaded and pulled.
- The slash commands reach Antigravity, Codex and Cursor as skills: `wiki-status`, `wiki-save`, `wiki-compile`, `wiki-standup`.
- Do: run the setup for each tool you use.
