# News

What's new in llm-wiki outside the handbook, written for the person using it. Handbook changes are in `CHANGELOG.md`. `wiki update` and `wiki news` print what you haven't seen, and `wiki status` says when there's something new.

Format: one `## YYYY-MM-DD: title` section per entry, newest first. Each title is different. A short paragraph, then lines starting `- ` for what changed and `- Do:` for what to do about it. Add an entry for anything a user would notice, and none for fixes they wouldn't.

## 2026-11-06: Background compile counts its runs right, and a sandbox's refusals are named

A second, shorter run in Antigravity's sandbox confirmed yesterday's fixes there and showed what was still rough.

- A note captured while a background run was going counted against that run. A run that compiled its one note could be recorded as "0 of 1, partial". Only the notes waiting when the run began count now. Rows already in `wiki compile` keep the old count.
- A run that finished at the moment its time limit was being called off could be recorded as `timeout`, and a slow machine made that more likely. Only a limit that ran its full time counts now.
- Where Claude Code is installed and the shell isn't allowed to run it, which is the case in Antigravity's sandbox, `wiki start` says so and leaves the notes to the session. Before, it said a background run had the notes, and that run failed at once. `wiki compile <wiki>` and `wiki compile on` say the same.
- A run that fails prints the agent's last line next to the path of its output.
- Where a sandbox refuses a read, commands say so instead of calling the thing missing or empty: `wiki report` for your transcripts, `wiki compile` for its runs, `wiki setup --list` for `~/.claude/CLAUDE.md` and Claude Code's settings, `wiki deps` for your code folders, and `wiki status` for its news marker. Settings it can't read no longer count as allow rules to add.
- Session start marks a listed tool `NOT FOUND on this shell's PATH` where it said `NOT INSTALLED`. In another agent's shell the tool is often installed and its folder isn't on the PATH.
- The Antigravity, Codex, Cursor and Chat lines of `wiki setup --list` say `unknown, can't read ...` when a sandbox refuses their files, where they said `old` or `missing`. `wiki status` no longer counts those as new settings, and `wiki setup` leaves such a plugin alone, where it used to install it again.
- Do: run `wiki update`. Nothing else.

## 2026-11-05: Fixes from a test run in another agent's sandbox

Gemini ran the day's changes in Antigravity's sandbox and found six bugs. They are fixed.

- `wiki lint`, `wiki stale` and `wiki deps` printed nothing and failed when one folder under your code folders couldn't be read, which is the usual case inside an agent's sandbox. They now work with what they can read.
- With background compile on, `wiki start` says so when the agent's command isn't on that shell's PATH, where before it left the notes waiting without a word.
- The compile agent can be Claude Code by its full path, such as `agent=/Users/you/.local/bin/claude` in `~/.config/llm-wiki/compile`. It used to be run as an unknown agent, with no tool list.
- In a reminder's pattern only `*` is special, as the handbook says. A `[` or `?` used to be read as a shell glob, so a pattern like `[ -f x ]` matched nearly every command.
- The compiled helper put a reply on the wrong day within an hour of your day's start on a morning the clocks change, and left a transcript it couldn't read out of the token table. It now matches the built-in code in both.
- Session start replaces a downloaded helper that is damaged.
- Do: run `wiki update`. Nothing else.

## 2026-11-05: wiki journal backfill gets faster too

`wiki journal backfill` now writes its digest with the same compiled helper as `wiki report` and `wiki standup`. On one machine the default 14 days went from 14 seconds to under 3. The digest is the same.

- Do: run `wiki update`. Nothing else.

## 2026-11-05: wiki report and standup get several times faster

Parts of `wiki report` and `wiki standup` now run in a small compiled helper. On one machine a week's report went from 11 seconds to under 4, and a week's standup from 6 seconds to under 1. They print exactly what they printed before.

- `wiki update` downloads the helper for your Mac or Linux machine, about 3 MB, from this project's GitHub releases. It is kept only if it matches a checksum that came with the code you already run.
- `wiki helper` says which helper is in use, and `wiki helper fetch` downloads it without updating anything else.
- A plugin can update without you running `wiki update`, so session start also fetches the helper, in the background, when it is missing or out of date. It tries once in six hours at most and says nothing. `wiki helper auto off` stops it, and `wiki setup --new` asks.
- Nothing needs it. Without one, the same commands run their built-in code, only slower. `LLM_WIKI_NO_GO=1` turns it off.
- If you have Go, you can build it instead: `go build -o bin/llm-wiki ./cmd/llm-wiki` in a clone.
- Do: run `wiki update`. Nothing else.

## 2026-11-05: The tour says what it's for

The tour used to start with a made-up service's queue and left you to work out why it mattered. It now opens with what llm-wiki does for you, names each chapter by what you get, and ends each with what changes for you.

- The first four chapters are now the strongest: a new session that already knows why, a stale fact caught against the code, a decision kept, and a repeated correction turned into a rule.
- Do: if you stopped partway, run `wiki tour --clean`, then ask for the tour again.

## 2026-11-05: wiki relay is now its own tool

The Copilot Cowork relay moved to its own repository, [llm-relay](https://github.com/broxgit/llm-relay), since it has little to do with wikis. Nothing else in llm-wiki changes, including `wiki setup microsoft-copilot`.

- `wiki relay` and `wiki setup copilot-cowork` now only print where they went, and fail. They'll go away in a later release.
- The commands are the same with a shorter name: `relay run`, `relay scan`, `relay mr`, `relay review` and `relay apply`. `relay setup` replaces `wiki setup copilot-cowork`.
- It keeps reading your settings from `~/.config/llm-wiki/relay` until you set new ones. It still sends a repository's wiki if the `wiki` command is installed.
- `--collection` didn't come along. To pick a collection for a scan, set `WIKIS_DIR`.
- Do: if you use Copilot Cowork, install `relay` as its README says, and run `relay setup`. That reinstalls the skill in OneDrive, which you have to do, because the old copy tells Cowork to give you `wiki relay` commands. Give it 10 minutes before a new conversation. Otherwise, nothing.

## 2026-11-05: Reminders at the moment a rule applies

A rule your agent read at session start is easy to lose two hours in. Now a wiki can say when a rule applies, and Claude Code puts it in front of the agent then.

- Add lines under `## Reminders` in a wiki's `wiki/conventions.md`, such as `` - before bash `git push`: Check that the hooks ran. `` or `` - on edit `payments/*`: Money is in cents. ``
- `before` stops the first matching call once, with the rule as the reason, and lets the same call through the second time. `on` hands the rule over with the call's result.
- The shared wiki's reminders apply everywhere, and each one is given once a session.
- It needs the Claude Code plugin and `python3`. Other agents don't get reminders yet.
- Do: `wiki update` brings it in, and the changelog for handbook v28 has the details. Sessions already open need a restart to load the new hook.

## 2026-11-05: Notes can be compiled in the background, as an experiment

Sessions spend their first minutes compiling notes that earlier sessions left, and in the first week half the notes never got compiled at all. A background run can take that over. It is off unless you turn it on.

- `wiki compile <wiki>` has a headless agent compile the wiki's waiting notes, and waits. `--background` doesn't wait.
- `wiki compile on` makes session start hand waiting notes to a background run, and tells your session to leave them. `wiki compile off` goes back.
- `wiki compile` alone shows the setting and the last runs: how many notes, how long, how old the oldest was, and how it ended.
- A run takes the compile lock, gets 20 minutes, never resolves a contradiction or lints, and syncs when it ends. The script frees the lock, so a run that dies can't leave it held.
- The agent is `claude` on sonnet. `~/.config/llm-wiki/compile` can name another: `agent=<a command that reads the prompt on stdin>`, or `model=<name>`.
- The run uses your own Claude Code permissions as well as the few it is given, so it can do what your sessions can.
- Sessions still compile at a pause, as the handbook says. This only takes the notes waiting at session start.
- Do: to try it, run `wiki compile on`, and look at `wiki compile` after a week. Read a few of the pages it wrote before trusting it.

## 2026-11-05: Take the tour

Ask your agent "Give me the llm-wiki tour" and it teaches you the features by doing them, on a made-up project. You ask its wiki a question, save a decision, watch notes become pages, rule on a contradiction, and see a wrong page get caught against the code.

- It runs in a sandbox in your temp folder, with its own wikis, code and settings, so your wikis and tips aren't touched. The last chapter reads your real setup, and says what would help you most.
- The short version takes about 10 minutes. You can skip around, or stop and pick up later. `wiki tour --clean` removes the sandbox.
- It's `/llm-wiki:tour` in the plugin, and the `wiki-tour` skill in Antigravity, Codex and Cursor. Any other agent that can run commands can follow `wiki tour`. The desktop app's Chat tab can't.
- Do: try it, or point a new teammate at it. Otherwise, nothing.

## 2026-11-05: Wikis in a second collection get found from anywhere

A second review of the code by Gemini found these, and each one was checked against the code first.

- `wiki relay scan` and `wiki relay mr` send the wiki of the repository they're about, whichever folder you run them from. Run from outside it, with the repository in a second collection, they used to send no wiki and say nothing. A checkout in a renamed folder now finds its wiki too.
- The Chat tab's `wiki_start` looks through every collection for the repository's wiki, unless you name one.
- A flag with no value, such as `wiki standup --since`, says so. It used to exit with no message.
- An example of a `> **Conflict:**` line inside a code fence no longer counts as open in `lint`, `standup` or `report`.
- `wiki report`'s token tables leave out what your journal's `exclude` setting names.
- `wiki setup --list` names every section you can use, and tab completion knows `setup copilot-cowork`, `setup microsoft-copilot` and the flags of each `relay` command.
- `wiki which` with no name covers the repository you're in.
- Do: `wiki update` brings these in. Nothing else.

## 2026-11-04: Cowork reviews can see test results and say what they skipped

The first real Cowork review worked with almost no effort, but every finding came from reading code, and its gaps only came out when asked. These changes address both.

- `wiki relay mr` offers to run `go build`, `go vet`, `go test` and `go mod tidy -diff` on a temporary copy of the branch, and sends the results to Cowork. It asks first, and names the author, because this runs the branch's code on your Mac. `--checks` and `--no-checks` answer for you.
- Reviews now end with a Coverage section saying what Cowork read and skipped. `wiki relay review` shows it before you save, and warns if it's missing.
- `relay mr` warns when your local branch has commits the merge request doesn't, because Cowork reviews what's pushed. The checks run with git hooks off.
- The prompt on your clipboard asks for a verdict and for what wasn't covered, so there's nothing to add to it.
- `remote-pair-run` now tells Cowork to follow every step of your review skill, load the skills it names and re-check what its sub-agents report, so your skill only needs the rules Cowork can't otherwise see. How well Cowork follows this hasn't been tried yet.
- Runs that test a merge request use a new `safe_worktree`, which turns git hooks off and proves your checkout didn't change. A hook spoiled one real run before this.
- Do: if you use Copilot Cowork, run `wiki setup copilot-cowork` again, and give it 10 minutes before a new conversation. You can remove the generic parts of any "In Copilot Cowork" section you added to your review skill. Otherwise, nothing.

## 2026-11-04: Review merge requests with Copilot Cowork

`wiki relay mr <url>` sends Cowork what a review needs, and `wiki relay review` brings the review back, so it no longer takes a pile of manual steps.

- `relay mr` sends the merge request's discussions, diff and branches, your Go libraries at their pinned versions, your earlier review, and the wiki. `--also` adds other repositories, or one folder of one. It only fetches in your clone, and puts a prompt for Cowork on your clipboard.
- `relay review` saves Cowork's file where you keep your reviews when you press `y`, and keeps your earlier copy as `.previous`.
- `relay apply` leaves a proven patch in your working tree when you press `y`, and never commits.
- It needs `glab`, and hasn't been tried with Cowork yet.
- Do: if you use Copilot Cowork, run `wiki setup copilot-cowork` again. It updates the skill and asks where your clones and reviews live. Otherwise, nothing.

## 2026-11-04: Show Copilot Cowork another branch

`wiki relay scan --branch master` shares that branch without you leaving yours, so Cowork can read the latest `master` while you're on a feature branch.

- It fetches, and sends the branch as origin has it, or your local copy if origin doesn't have it. Your checkout and uncommitted changes aren't touched, and those changes stay out of the scan.
- Do: if you use Copilot Cowork, run `wiki setup copilot-cowork` again so it knows to ask for this. Otherwise, nothing.

## 2026-11-04: Copilot Cowork reads a repository's wiki

`wiki relay scan` now also sends the wiki that covers the repository, so Cowork can follow your decisions and rules without you repeating them.

- Only that wiki's `index.md` and compiled pages go. Raw notes, other wikis and the shared wiki stay on your machine. The command says when it sends one.
- It's a read-only copy as of the scan, and Cowork can't save notes back. It hasn't been tried with Cowork yet.
- Do: if you use Copilot Cowork, run `wiki setup copilot-cowork` again to update the skill. Check that your company allows that wiki's content in OneDrive and through its tenant, or add `--no-wiki`. Otherwise, nothing.

## 2026-11-04: wiki relay, so you stop attaching files to Copilot Cowork

You no longer attach scans or reports. A round is now one command, one keypress, and telling Cowork "done".

- `wiki relay run` waits for OneDrive, checks every file, and runs a local copy once you press `y`. Running from the OneDrive folder itself sometimes got killed or refused. The report goes back by itself, only if a run happened.
- `wiki relay scan` shares your branch and uncommitted changes through OneDrive, including the branch's history. Untracked files stay out.
- It has worked with real Cowork from Apple's Terminal, on a throwaway repository: scans up to 50 MB, a failed run, its fix, and pressing `n`. macOS can refuse other terminal apps with `Operation not permitted`, as it once did iTerm, and the relay says so if it happens.
- Do: if you use Copilot Cowork, run `wiki setup copilot-cowork` again to update the skill, and run `wiki relay run` in Apple's Terminal. Otherwise, nothing.

## 2026-11-03: Copilot Cowork can change code through runs on your Mac

If work gives you far more Copilot than Claude, Cowork can now work on a real repository without reaching it. It publishes a folder to OneDrive, you run one command, and you attach the report.

- `wiki setup copilot-cowork` copies the `remote-pair-run` skill to your work OneDrive.
- The run waits for OneDrive to catch up, checks every file against a manifest, and ends in a clear PASS or FAIL. It never commits or pushes.
- It has been through one test with Cowork, on a throwaway repository.
- Do: nothing, unless you use Copilot Cowork at work. Then see "Set up with another agent" in the docs.

## 2026-11-03: Microsoft 365 Copilot can read your wikis

A work or school account can now ask Copilot questions and get answers from a wiki repository on GitHub. It's read-only, and limited to the one repository you install it on.

- `wiki setup microsoft-copilot --repo OWNER/REPO` registers a read-only GitHub App, builds the agent and provisions it. You select Create and Install, and sign in twice.
- `--update` changes an existing agent in place, when you add a wiki or a newer llm-wiki improves its instructions.
- `wiki news` is new too: it shows this list, and `wiki status` tells you when there's something unread.
- Do: nothing, unless you use Copilot at work. Then see "Set up with another agent" in the docs.

## 2026-11-02: Search counts in the weekly report

`wiki find` now records whether a search found anything, and the report counts sessions opening wiki pages, from your transcripts. It no longer shows a hit rate it couldn't back up.

- Do: nothing needed.

## 2026-11-01: The Claude desktop app's Chat tab and claude.ai

Sessions with no file access can use your wikis too.

- `wiki setup chat` gives the desktop app's Chat tab tools to search, read and save to your wikis, through a small server on your machine.
- A private claude.ai Project can read a collection through its GitHub connector. It can't save notes.
- Do: run `wiki setup chat` in the Terminal app if you use the Chat tab, and add the line it prints to your profile preferences.

## 2026-10-30: Codex and Cursor setup

Codex and Cursor get the automatic parts Claude Code has: each session starts with its wiki loaded and pulled.

- `wiki setup codex` installs a Codex plugin, and `wiki setup cursor` adds a session hook for Cursor without the Claude Code plugin.
- The slash commands reach Antigravity, Codex and Cursor as skills: `wiki-status`, `wiki-save`, `wiki-compile`, `wiki-standup`.
- Do: run the setup for each tool you use.
