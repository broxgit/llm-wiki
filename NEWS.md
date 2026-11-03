# News

What's new in llm-wiki outside the handbook, written for the person using it. Handbook changes are in `CHANGELOG.md`. `wiki update` and `wiki news` print what you haven't seen, and `wiki status` says when there's something new.

Format: one `## YYYY-MM-DD: title` section per entry, newest first. Each title is different. A short paragraph, then lines starting `- ` for what changed and `- Do:` for what to do about it. Add an entry for anything a user would notice, and none for fixes they wouldn't.

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
