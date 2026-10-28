# Troubleshooting

`wiki status` is the first thing to run. It lists every wiki and flags what's off.

## Setup

- **The agent ignores the wiki.** It never loaded the handbook.
  - Plugin: in a terminal, `claude plugin list` should show `llm-wiki@llm-wiki` as enabled. A session started before you installed it doesn't have it, so start a new one. In the desktop app, quit and reopen it if a new session still doesn't. Ask the session "what does your llm-wiki session context say?" to check.
  - Without the plugin: run `./wiki.sh claude`, or paste the line from [A session that's already running](other-agents.md#a-session-thats-already-running). In Claude Code, `/context` lists the instruction files that loaded.
- **The agent can't read or write the wiki.** It lacks access to `~/wikis`. Start Claude Code with `--add-dir ~/wikis`, or approve the prompt the first time it reaches for the folder. In the desktop app, add the folder to the session.
- **`wiki: command not found`.** Plugin: run `~/.claude/plugins/data/llm-wiki-llm-wiki/bin/wiki link`, then open a new terminal. If that file doesn't exist, start a Claude Code session once first. Clone: link it with `ln -s <clone>/wiki.sh ~/.local/bin/wiki`. Either way, `~/.local/bin` must be on your `PATH`.
- **`wiki` says it can't find the llm-wiki plugin.** Claude Code's record of the plugin points at a folder that's gone. Run `claude plugin list` to check it's installed, and reinstall it if not.
- **Auto-update is off.** `wiki status` says so. Run `wiki setup plugin` to turn it on.
- **Tab completion doesn't work.** Run `wiki setup completion`, then open a new terminal. `wiki setup --list` shows whether it's on.
- **`wiki setup` says it needs a terminal.** It asks questions, so run it in a terminal, not through the agent. `wiki setup --list` shows the current values anywhere.

## Day to day

- **Notes pile up in `raw/` and never become pages.** `wiki status` flags `compile due` at five waiting and `lint due` after 10 compiles. The next session there compiles at startup. Say "compile" to do it now.
- **"Lock held" and nothing compiles.** A session crashed while compiling. A lock older than 30 minutes is ignored. `wiki unlock <name>` frees one right away.
- **Knowledge landed in the wrong wiki.** Tell the agent where it belongs. It asks before moving pages.
- **It saves too much or too little.** Tell it. Corrections are tallied, and a repeated one becomes a rule. To change the rule for everyone, see [Maintaining](maintaining.md).
- **An answer came from an out-of-date page.** Tell the agent what changed. It files a correction. `wiki stale` shows what else hasn't been checked in a while.

## Git and updates

- **A wiki's handbook is behind.** With the plugin, the next session upgrades it on its own. Otherwise `wiki upgrade --all` brings every wiki up to date, then says what changed and what to do next. Outside git it keeps the old handbook as `AGENTS.md.bak`.
- **A wiki is ahead of your template.** A teammate upgraded it with a newer template. Plugin: `claude plugin marketplace update llm-wiki` in a terminal, then start a new session. Clone: `git pull` in the clone.
- **A pull fails with "cannot pull with rebase: You have unstaged changes".** Another wiki has notes waiting, uncommitted, and a rebase won't run around them. `wiki sync <wiki>` commits just that wiki and pulls with a merge, which doesn't mind them. Never stash in `~/wikis`.
- **The push test in setup failed.** It says why, and the fix. Most often: the remote is an `https` URL (switch it to `git@…`); the key isn't on your account or its passphrase isn't loaded (`ssh-add --apple-use-keychain <key>`); or your network blocks port 22 (set up SSH over port 443 in `~/.ssh/config`). If your normal SSH works for the host (`ssh -T git@gitlab.com`), you don't need to name a key: run `wiki setup git.identity` and answer `-`.
- **A safety check refused to delete `journal/backfill.md`.** Run `wiki journal backfill --done`, which removes it.
- **`wiki which` says no wiki covers a repository that has one.** Its folder name differs from the wiki. Run `wiki cover <wiki> <repository>`.
- **A commit was refused for a secret.** The agent replaces it with `[REDACTED]` and commits again. If it isn't a secret, add the `Fingerprint` line gitleaks printed to `.gitleaksignore` at the top of the collection.
- **An agent's commit won't push.** Run `wiki setup git`. It sets the repo's commit email and SSH key and test-pushes. A machine with a work key and a personal key usually needs the key named for this repo.
- **A merge conflict in a page.** The agent stops and asks. Resolve it like any git conflict. Conflicts in `index.md` and `log.md` resolve on their own.
