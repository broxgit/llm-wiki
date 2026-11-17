# News

What's new in llm-wiki outside the handbook, written for the person using it. Handbook changes are in `CHANGELOG.md`. `wiki update` and `wiki news` print what you haven't seen, and `wiki status` says when there's something new.

Format: one `## YYYY-MM-DD: title` section per entry, newest first. Each title is different. Under it, one line starting `- ` for each change a user would notice, four at most, and nothing else. Leave out what they wouldn't notice: the pull request has that. Add a `- Do:` line only when there is something for them to do. `wiki update` prints these as they are, so a long entry is a long update.

## 2027-01-05: type a note yourself, in an inbox

- Put a markdown note in a folder called `inbox`, in a wiki or at the top of your collection, and the next session takes it into the wiki's notes.
- It works from Obsidian, a phone or any editor. A note is taken once it has been left alone for two minutes.
- `wiki inbox` takes what is ready now and says why anything was left. `wiki obsidian` makes the collection's inbox.

## 2027-01-04: wiki uninstall, and setup from nothing

- `wiki uninstall` undoes what setup did on this machine and keeps your wikis. It asks first, and `--dry-run` only says what it would do.
- Your settings are moved to `~/llm-wiki-removed-<time>`, never deleted. It lists what it leaves, such as the plugin, and how to remove that.
- `wiki setup --fresh` does the same, then walks through setup as if for the first time.

## 2027-01-03: wiki github tells a session about new comments

- With `comments = yes`, a new comment or review from someone else on your open pull request is handed to the next session on that branch.
- The line says how many and from whom, never what they wrote. `wiki github comments` prints them, marked as text from outside.
- It is off unless you turn it on: `wiki extensions set github comments yes`, or `wiki extensions setup github`.

## 2027-01-02: wiki gitlab tells a session about new comments

- With `comments = yes`, a new comment from someone else on your open merge request is handed to the next session on that branch.
- The line says how many and from whom, never what they wrote. `wiki gitlab comments` prints them, marked as text from outside.
- It is off unless you turn it on: `wiki extensions set gitlab comments yes`, or `wiki extensions setup gitlab`.

## 2027-01-01: wiki jenkins works out the job from the remote

- Where jobs are named after the repository, set `job_pattern` once, such as `Platform/{path}`, and a clone with a `Jenkinsfile` needs no job named.
- Watching a job by hand that is named after its remote prints the pattern to set. `wiki extensions setup jenkins` asks about it too.
- `job_auto = yes` watches such a clone when a session starts in it. `job_remote` limits the pattern to your own group.

## 2026-12-31: an extension is offered where it fits

- A session that starts in a repository with a `Jenkinsfile`, a GitLab remote or GitHub workflows offers you the extension for it, if you don't use it there.
- It asks in two sessions at most. A no is kept for that repository: `wiki extensions offer <name> no`, or `never` for every repository.
- An extension of your own can be offered the same way, with a `wiki-detect:` comment. `docs/extensions.md` has it.

## 2026-12-30: wiki jenkins takes a job in an organization folder

- A job named after its GitLab or GitHub path, such as `group%2Fapp`, was refused. It is accepted now, as a path or as its address.
- The setup question for the job says you can paste the job's address from your browser.

## 2026-12-29: sign-in is set at a terminal, never by a session

- For Jira, Confluence and Jenkins, a session can no longer set the address, the account or where the token comes from. It still sets everything else.
- You set those yourself: `wiki extensions setup jira`, `confluence` or `jenkins`. An agent can still walk you through it and test the sign-in.
- An address that hides another, such as `https://real.example@evil.example`, is refused wherever it comes from, before any token is fetched.
- Do: run `wiki update`, then check your addresses are yours: `wiki extensions settings jira` and `wiki extensions settings confluence`.

## 2026-12-28: what failed in GitLab CI and Jenkins, and why

- `wiki extensions add gitlab` or `jenkins` adds `wiki gitlab` or `wiki jenkins`: the failing job, the first error line and a short saved log excerpt.
- Both only read: they fix nothing, start no agent and write nothing to GitLab or Jenkins. GitLab uses `glab`; Jenkins needs its address, your user and a token.
- With a clone watched, a pipeline or build that starts failing is handed to your next session in one line, and shown on your desktop, as GitHub's is.
- Do: only if you use them: `wiki gitlab watch` in a clone, or `wiki jenkins watch <folder> <job>`, after `wiki extensions add`.

## 2026-12-27: a session can no longer change where your Atlassian token is sent

- Security fix: once a token is set up, a session can't change the Jira or Confluence address. A misled session could have sent your token elsewhere.
- The address, and where the token comes from, are yours to set in a terminal: `wiki extensions setup jira` or `confluence`. An agent still sets the rest.
- A plain `http://` address is taken only for your own machine, since it would send your sign-in unencrypted.
- Do: run `wiki update`. If a session ever changed your site, check it: `wiki extensions settings jira`.

## 2026-12-26: an agent can fix a failing CI run, if you turn it on

- Off unless you turn it on: `wiki github fix on`, in a terminal, for one clone. An agent then changes code and llm-wiki pushes it, with nobody watching.
- On your pull request: one commit to its branch. On the default branch: a new branch and a pull request. Never a force-push. Your repository's hooks don't run.
- Checked first: limits, no `.github/`, CI, key or build files (unless allowed), no secrets, no links. Gives up after two tries. `wiki github fix` lists them.
- Do: only if you want it, `wiki github watch` then `wiki github fix on` in a clone, and read what it says the agent may do.

## 2026-12-25: a failed CI run, on your desktop, with no session open

- `wiki extensions schedule on` has your machine check in every 5 minutes by itself, with no session open. `schedule off` removes it.
- With `wiki github` on, a run that starts failing shows a desktop notification. `wiki extensions set github desktop no` turns that off.
- `wiki extensions tick --due` runs only the extensions that are due. `wiki setup extensions` offers the schedule once.
- Do: run `wiki extensions schedule on`, and `wiki extensions every github 10m` to check more often than daily.

## 2026-12-24: what failed in GitHub Actions, and why

- `wiki extensions add github` adds `wiki github`: which CI run failed, in which job and step, the first error line, and a short saved excerpt of the log.
- With a clone watched, a run that starts failing on your branch is handed to your next session in one line, once.
- It can save a note in the wiki when a failure is fixed, so the same error is recognised next time. That is off until you turn it on.
- Do: run `wiki extensions add github`, then `wiki github watch` in a clone.

## 2026-12-23: a chat can create your first wiki

- Through the chat connector, your assistant can now create a wiki when you ask for one, and the folder wikis are kept in if there is none yet.
- It asks first, makes nothing outside that folder, and sets up no git. A backup and sharing still take `wiki setup`.

## 2026-12-22: a pattern for the folders inside says what it leaves out

- `wiki workflows add '<folder>/*' <wiki>` now says it covers the folders inside, not the folder itself, and gives the command for that folder too.
- An agent walking you through setup is told which pattern goes with which answer, to keep technical words out, and to end with how you can help.

## 2026-12-21: setup from start to finish, for anyone

- `wiki setup` now opens by saying what llm-wiki is and why, and ends with tips and ways to help improve it.
- It asks how you work: in a project's folder, in a folder per task, or in one folder for everything, and whether you work more than one way.
- Each step says what it is in everyday words first. An agent walking you through setup does the same, and needs no terminal to begin.
- Do: run `wiki setup --new` to be asked how you work. It is one question.

## 2026-12-20: a finished ticket asks before closing what only sat in its folder

- `wiki jira check --close` no longer closes an item tied to a ticket only by a note's `Ticket:` line. It asks you whether that one is finished too.
- An item whose heading names the ticket still closes by itself when the ticket is done.
- Do: run `wiki update`, then `wiki upgrade --all`, for handbook version 38.

## 2026-12-19: a chat with no wikis says where setup happens

- On a machine with no wikis, the chat connector now says setup takes a terminal and names the agent-led guide, not just "Run: wiki setup".
- A coding session with no collection now offers to walk you through setup first, with the terminal command as the other way.

## 2026-12-18: a wiki name with spaces is taken

- `wiki new "Acme Holdings"` now creates the wiki as `Acme-Holdings` and says so in its first line. Before, it refused and offered that name.

## 2026-12-17: the chat connector says why a save didn't sync

- When a note saved through the connector fails to sync, the reply now says what stopped it: the file a secret scan flagged, or the page in conflict.

## 2026-12-16: a ticket's waiting notes are handed over with its pages

- In a folder or on a branch named for a ticket, session start now lists the notes not compiled yet that belong to the ticket, after its pages.
- A note counts when it carries the ticket's `Ticket:` line or names the ticket in its text. Before, a session was told only that a note was waiting.

## 2026-12-15: plainer words for people who don't use git

- In a collection with no git, `wiki sync` now says the wiki has no backup and isn't shared, and how to set that up.
- A wiki name with a space is still refused, but the refusal offers the nearest name that works: "Acme Holdings" gets `Acme-Holdings`.
- Through the chat connector, a saved note is reported in everyday words, without "pushed", "raw" or file paths.

## 2026-12-14: the search at your message stays in your project

- When you send a message, two ordinary words now find pages and notes only in the wiki of the project you are in, and in the shared wiki.
- A ticket's key or a name out of code is still found in any wiki, with your own project's pages first.
- Before, a session in one project was handed notes from others that happened to share two everyday words with the message.

## 2026-12-13: notes taken in a ticket folder know their ticket

- A note you capture in a folder, or on a branch, named for a Jira ticket now ends with a `Ticket: <KEY>` line.
- `wiki jira check` counts a ticket an open item's notes carry, so it can close that item without the key in its heading.
- With Jira set up, a session in a ticket folder is told which ticket it is on and that `wiki jira show` prints where it stands.
- A folder named python-3 or sprint-12 is no longer taken for a ticket.

## 2026-12-12: a covered repository can leave, or get its own wiki

- `wiki uncover <repo>` takes a repository off the wiki that covers it. Before, that meant editing `repos.md` by hand.
- `wiki uncover <repo> --new` also gives it a wiki of its own, which `wiki new` refuses while it is covered. Its pages stay put until you say to move them.

## 2026-12-11: your agent can walk you through setup

- Ask your agent to run `wiki setup --guide` (in Claude Code, `/llm-wiki:setup`): it goes through each setting with you, starting with the unanswered ones.
- A session can set Jira and Confluence settings now: `wiki extensions settings jira`, `wiki extensions set jira site <address>`. Your token stays yours.
- `wiki setup palette`, `theme` and `feedback` take a value, such as `wiki setup theme light`, and ask nothing.
- Every reminder to set up now says the guide is there.

## 2026-12-10: tickets and Confluence links bring their extensions

- Name a Jira ticket or paste a Jira or Confluence link and the agent offers that extension once, if it isn't set up. If it is, the agent uses it.
- An offer rests for a week. Say no and `wiki tips --mute ext-jira`, or `ext-confluence`, stops it for good.

## 2026-12-09: one look for every llm tool

- Every command prints as a timeline: stages down a line on the left, ✓ ! ✗ marks, and what to do next. The words agents read are the same.
- Colours are 24-bit where your terminal says it can show them (`COLORTERM=truecolor`), and the terminal's own 16 elsewhere.
- `wiki setup theme` (or `LLM_THEME=light`) suits a light background. `bash ui.sh`, in the llm-wiki folder, shows every piece.

## 2026-12-08: your message finds its pages

- When you send a message, the agent is handed the pages and notes, in any wiki, that fit its words. It used to have to go looking, and mostly didn't.
- A ticket key or a name out of code is enough by itself, ordinary words need two. A page or note is named once a session, and nothing is added when none fit.
- It works in Claude Code, Codex and Antigravity.
- Do: in Codex, run `wiki setup codex`, then `codex` in a terminal, type `/hooks` and trust the new hook.

## 2026-12-07: session start leaves your agents' rules alone

- A session in another collection, or with `WIKIS_DIR` set, no longer rewrites the agents' rule files. They name your default collection.
- A new wiki links to its own collection's shared wiki, not to `~/wikis/global`.
- An out-of-date handbook is the second line of session start, and the agent tells you. Waiting notes are compiled after it has answered you.
- Do: run `wiki upgrade --all`, for handbook version 35.

## 2026-12-06: a colour-blind palette

- `wiki` can show blue for ok and magenta for an error instead of green and red. The marks and words are the same.
- Do: run `wiki setup palette` and answer `colorblind`, or set `LLM_PALETTE=colorblind` in your shell. `wiki setup --new` asks once.

## 2026-12-05: search finds a note before it is compiled

- `wiki find` also searches the notes waiting to be compiled, newest first. A saved note used to be invisible to search until a compile.
- The same holds in a chat that reaches your wikis through the connector.

## 2026-12-04: a branch named for a ticket finds the ticket's pages

- Start a session in a repository on a branch such as `feature/VID-74441-fix`, and it is handed the pages that mention that ticket, whichever wiki they are in.
- It used to need the folder to be named for the ticket. A branch such as `release-2026` is not taken for one.

## 2026-12-03: the folder where you keep your clones is left alone

- A session started in a folder that holds more than 30 folders uses the shared wiki and says so. It was treated as a ticket folder, from its first 30.
- To give such a folder a wiki, or none: `wiki workflows add '<folder>' <wiki>` or `wiki workflows add '<folder>' none`.
- A long list of repositories with no wiki is cut to three names and a count.

## 2026-12-02: a ticket folder finds the ticket's pages in any wiki

- Start a session in a folder named for a ticket, such as `VID-74003`, and it is handed the pages that mention that ticket, whichever wiki they are in.
- It used to get only the wikis of the clones in the folder, so a page filed under another repository's wiki was never found.
- `wiki start` prints the same pages, for agents that have no session hook.

## 2026-12-01: a locked wiki says who holds it

- A session that finds a wiki locked for compiling is told who holds it: a background compile and how far it has got, or a session and the folder it is in.
- `wiki lock <wiki> --who` says the same at any time. A session can name itself with `--as`, and a later one is given that name.
- A background compile that was stopped no longer leaves its wiki locked for half an hour.

## 2026-11-30: a ticket folder whose repositories have no wikis yet

- In a folder of clones that have no wikis yet, the agent asks once whether to use their wikis as they get them, and keeps a yes or a no.
- It no longer asks how such a folder is laid out, or offers only to remember "no wiki" for it.

## 2026-11-29: wiki list names your wikis

- `wiki list` prints the wikis in your collection and the repositories each one covers. `wiki list --names` prints the names alone, for a script.
- A ticket folder with words after its number, such as `INFRA-1235-fix-dns`, is offered the same pattern as its siblings.
- Tab completion offers `list` and `workflows`.

## 2026-11-28: a session outside a repository asks once where it belongs

- In a folder that isn't a git repository, the agent asks once how folders like it work, and keeps your answer as a pattern in your shared wiki.
- Later sessions in that kind of folder use the pattern and say which one they recognised. Tell the agent if it is wrong.
- `wiki workflows` lists the patterns, and adds, removes and tries them. A pattern can also say a folder uses no wiki.
- Do: run `wiki upgrade --all`, for handbook version 34.

## 2026-11-27: a session in a folder of clones uses their wikis

- Start a session in a folder that holds clones, such as one for a ticket, and it uses the wikis of those clones. It used the shared wiki and said nothing.
- The session says at the start which wikis it is using and why, so you can say if that is wrong.
- In a folder with no repository in it, the agent asks whether you want llm-wiki used there.

## 2026-11-26: Confluence can tell your wiki when a page changes

- `wiki confluence` now watches pages you name: a change to a page's text or status is noted in a wiki, once a day, in the background. It only reads.
- An open item whose heading has a page's address closes when the page is marked Verified.
- Setup for Jira and Confluence says what each choice does before asking, and ends with what is set. Publishing is a separate yes or no.
- Do: run `wiki extensions setup confluence` to name pages to watch.

## 2026-11-25: calling `wiki` wrongly exits 2

- An unknown command or option, or a missing argument, now exits 2, where a failure exits 1. A script can tell the two apart.
- `docs/conventions.md` is at version 2, with that, a note on `--yes`, and warnings on standard error styled as standard error is.

## 2026-11-24: an extension that is on says when it isn't set up

- Turning on Jira or Confluence in `wiki setup` now asks for the Atlassian site and email, tests the sign-in, and asks for each one's own settings.
- `wiki status` lists an extension that is on and not set up, with the command that fixes it: `wiki extensions setup <name>`.
- A wrong address, a taken title and a run that keeps being put off are now said, where they used to look like nothing to do.
- Do: if you turned an extension on before this, run `wiki extensions setup jira`, or `confluence`.

## 2026-11-23: a wiki's open items and pages, for a program

- `wiki open --data` prints every open item, and `wiki pages <wiki> --data` every page with its title, one a line and tab separated.
- They are for extensions and scripts, so they stop reading the wiki's files themselves. `wiki pages <wiki>` alone lists the pages for you.

## 2026-11-22: colour in `wiki setup` and `wiki update` at a terminal

- At a terminal, both have bold headings, a green tick on what was done, a yellow `!` on what is left for you, and cyan for the commands you type.
- `wiki setup --list` shows `<- new` in yellow. The words are the same, and a pipe stays plain. These two and `status` have colour.

## 2026-11-21: one Atlassian sign-in for Jira and Confluence

- The site, email and token command go in `~/.config/llm-wiki/atlassian`, and both extensions read them there.
- An extension's own file still wins, so settings you already have keep working with no change.
- `wiki jira config` and `wiki confluence config` say where each value came from.

## 2026-11-20: colour in `wiki status` at a terminal

- At a terminal, `wiki status` has a bold header, yellow notes, a mark on each To do line, cyan for what you type. Words are the same, and a pipe stays plain.
- Errors from commands you run are `error:` in red. `NO_COLOR` turns it all off, and `LLM_WIKI_STYLE=on` or `off` decides for you.
- `docs/conventions.md` is the guide the commands follow.

## 2026-11-19: how often extensions run by themselves

- `wiki extensions every 4h` sets how often extensions run by themselves: `90m`, `4h`, `2d`, `3w`. It was fixed at 24 hours, still the default.
- `wiki extensions every jira 2h` gives one extension an interval of its own, which wins over the one for all.
- `wiki setup --new` asks once, when such an extension is on.

## 2026-11-18: Jira tells a dropped or blocked ticket from a finished one

- A ticket closed as Won't Do, Duplicate or Cancelled no longer closes its item. The item stays open, and a new one asks you to decide.
- A blocked or flagged ticket opens an item saying so, once. It closes by itself when the block clears.
- A ticket reopened after its item was closed opens the item again.
- `done_statuses = Released` in Jira's settings names what counts as done, where Jira's own grouping doesn't fit.

## 2026-11-17: Jira and Confluence with nobody asking

- With `auto_close = yes` in Jira's settings, a ticket that finishes closes the open item that names it, checked once a day in the background.
- With `auto = <wikis>` in Confluence's settings, those wikis are published when a sync changes their pages.
- Both are off until you set them, and neither prints into a session. `wiki extensions log <name>` shows the last runs.

## 2026-11-16: extensions can run by themselves

- An extension can ask to be run in the background after a sync changes a wiki, or once a day from session start. Nothing is printed into a session.
- `wiki status` says when an extension's last run failed, and `wiki extensions log <name>` shows what it printed.
- `wiki extensions tick` runs the daily event now, for cron. The Jira and Confluence extensions don't use events yet.

## 2026-11-15: a Confluence extension

- `wiki confluence publish <wiki>` copies a wiki's pages into a Confluence space, one way, for people who read there. Unchanged pages are left alone.
- It never overwrites a page it didn't make, and deletes nothing. `--dry-run` says what would change.
- Do: to use it, run `wiki extensions add confluence`, then `wiki confluence --help`. Publish only to a space whose readers may see the whole wiki.

## 2026-11-14: a Jira extension

- `wiki jira` says where the Jira tickets your open items name stand. `wiki jira check --close` notes the finished ones as done. It never writes to Jira.
- Extensions that ship with llm-wiki are off until `wiki extensions add <name>`. `wiki setup --new` asks about a new one once.
- Do: to use it, run `wiki extensions add jira`, then `wiki jira --help` for the three settings.

## 2026-11-13: commands of your own, as extensions

- `wiki <name>` runs an executable named `wiki-<name>` in your extensions folder, with the collection and the wiki command handed to it.
- `wiki extensions` lists them, and `wiki extensions path` prints the folder. `docs/extensions.md` shows how to write one.

## 2026-11-12: browse your wikis in Obsidian

- `wiki obsidian` writes starter settings for one vault over the whole collection and opens it. `wiki setup --new` asks once where Obsidian is installed.
- Editing a property in Obsidian rewrites a page's lists one item a line. Lint and the waiting-notes count read that form now.
- Lint reports `[[wikilinks]]`, which it can't follow.
- Do: run `wiki obsidian` if you want to browse there. Read in Obsidian, and ask an agent to change a page.

## 2026-11-11: a reminder to record releases and deploys

- When an agent runs a release or deploy command, such as `gh release create` or `terraform apply`, the plugin reminds it once a session to record the job.
- After three recorded runs of the same job, the agent offers to script it.

## 2026-11-09: `wiki delegation` counts each handoff once

- A handoff that a reminder stopped once was logged twice. It is logged once, when it goes through.
- `wiki delegation log` closes the handoff the plugin saw start, so OPEN goes down when you record an outcome.
- Do: rows already doubled or left open in `delegation-log.csv` stay as they are. Edit the file to clear them.

## 2026-11-09: `wiki sync` makes one trip to the remote

- `wiki sync` pushes first and pulls only when the remote has moved, so a sync takes about half the time.
- With nothing to push it pulls and says `up to date`. It says `synced:` only when something was pushed.

## 2026-11-09: `wiki status` copes with a wiki that has no log.md

- `wiki status` stopped with exit 2 and half a table at a wiki that had no `log.md`. It now shows every wiki and counts that one's ingests as none.
- `wiki helper` and `wiki update` no longer list which commands the helper speeds up.

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
