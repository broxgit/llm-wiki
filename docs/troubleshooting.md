# Troubleshooting

`wiki status` is the first thing to run. It lists every wiki and flags what's off.

## Setup

- **The agent ignores the wiki.** It never loaded the handbook.
  - Plugin: in a terminal, `claude plugin list` should show `llm-wiki@llm-wiki` as enabled. A session started before you installed it doesn't have it, so start a new one. In the desktop app, quit and reopen it if a new session still doesn't. Ask the session "what does your llm-wiki session context say?" to check.
  - Without the plugin: run `./wiki.sh claude`, or paste the line from [A session that's already running](other-agents.md#a-session-thats-already-running). In Claude Code, `/context` lists the instruction files that loaded.
- **The agent can't read or write the wiki.** It lacks access to `~/wikis`. Start Claude Code with `--add-dir ~/wikis`, or approve the prompt the first time it reaches for the folder. In the desktop app, add the folder to the session.
- **`wiki: command not found`.** Plugin: in a session, say "set up the wiki command". Clone: link it with `ln -s <clone>/wiki.sh ~/.local/bin/wiki`. Either way, `~/.local/bin` must be on your `PATH`.
- **`wiki` says it can't find the llm-wiki plugin.** Claude Code's record of the plugin points at a folder that's gone. Run `claude plugin list` to check it's installed, and reinstall it if not.
- **`wiki setup` says it needs a terminal.** It asks questions, so run it in a terminal, not through the agent. `wiki setup --list` shows the current values anywhere.

## Day to day

- **Notes pile up in `raw/` and never become pages.** `wiki status` flags `compile due` at five waiting and `lint due` after 10 compiles. The next session there compiles at startup. Say "compile" to do it now.
- **"Lock held" and nothing compiles.** A session crashed while compiling. A lock older than 30 minutes is ignored. `wiki unlock <name>` frees one right away.
- **Knowledge landed in the wrong wiki.** Tell the agent where it belongs. It asks before moving pages.
- **It saves too much or too little.** Tell it. Corrections are tallied, and a repeated one becomes a rule. To change the rule for everyone, see [Maintaining](maintaining.md).
- **An answer came from an out-of-date page.** Tell the agent what changed. It files a correction. `wiki stale` shows what else hasn't been checked in a while.

## Git and updates

- **A wiki's handbook is behind.** `wiki upgrade --all` brings every wiki up to date, then says what changed and what to do next. Outside git it keeps the old handbook as `AGENTS.md.bak`.
- **A wiki is ahead of your template.** A teammate upgraded it with a newer template. Plugin: `claude plugin marketplace update llm-wiki` in a terminal, then start a new session. Clone: `git pull` in the clone.
- **A commit was refused for a secret.** The agent replaces it with `[REDACTED]` and commits again. If it isn't a secret, add the `Fingerprint` line gitleaks printed to `.gitleaksignore` at the top of the collection.
- **An agent's commit won't push.** Run `wiki setup git`. It sets the repo's commit email and SSH key and test-pushes. A machine with a work key and a personal key usually needs the key named for this repo.
- **A merge conflict in a page.** The agent stops and asks. Resolve it like any git conflict. Conflicts in `index.md` and `log.md` resolve on their own.
