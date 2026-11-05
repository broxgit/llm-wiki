# News

What's new in llm-wiki outside the handbook, written for the person using it. Handbook changes are in `CHANGELOG.md`. `wiki update` and `wiki news` print what you haven't seen, and `wiki status` says when there's something new.

Format: one `## YYYY-MM-DD: title` section per entry, newest first. Each title is different. A short paragraph, then lines starting `- ` for what changed and `- Do:` for what to do about it. Add an entry for anything a user would notice, and none for fixes they wouldn't.

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
