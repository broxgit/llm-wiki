# Set up with Claude Code

About five minutes. This guide is for Claude Code anywhere it runs on your machine: in a terminal, in the Claude desktop app's **Code** tab, or in an IDE. They share one setup, so installing once covers all of them.

The desktop app's **Chat** tab and claude.ai on the web are not Claude Code and don't run plugins. For those, use [Set up with another agent](other-agents.md).

## Install

1. In a terminal, add this repo as a plugin marketplace and install the plugin:

   ```
   claude plugin marketplace add broxgit/llm-wiki
   claude plugin install llm-wiki@llm-wiki
   ```

2. Turn on auto-update. Marketplaces outside Anthropic's own start with it off, and without it you never get fixes. Open `~/.claude/settings.json`, find `"llm-wiki"` under `"extraKnownMarketplaces"`, and add `"autoUpdate": true` beside its `"source"`:

   ```json
   "llm-wiki": {
     "source": { "source": "github", "repo": "broxgit/llm-wiki" },
     "autoUpdate": true
   }
   ```

   In a terminal Claude Code session, `/plugin` > Marketplaces > `llm-wiki` > Enable auto-update does the same.
3. Start a new session: run `claude` in a repository, or open a new Code-tab session in the desktop app. If the desktop app doesn't pick up the plugin, quit and reopen it.
4. In that session, say "set up the wiki command". Claude links a small `wiki` script into `~/.local/bin`, so your terminal can run it.
5. In a terminal, run:

   ```
   wiki setup
   ```

   It asks one question at a time, and Enter takes the suggested answer. It creates your wiki collection in `~/wikis`, makes it a git repo, and walks through the [work journal](using.md#work-journal-and-standups).
6. Install gitleaks, which stops agents from committing a secret: `brew install gitleaks`.
7. If you added the wiki line to `~/.claude/CLAUDE.md` with an older version of this template, delete it. The plugin does its job, and both would point the session at the handbook twice.

Joining a team that already has a shared collection? Do [Teams](teams.md#join-a-shared-collection) before step 5.

## Moving from the old setup

Set up before the plugin existed, with a clone of this repo and a line in `~/.claude/CLAUDE.md`? One script does all of the above and tidies up. In the old clone:

```
git pull
./scripts/migrate-to-plugin.sh
```

It syncs your collection, installs gitleaks and the plugin, turns on auto-update, removes the old line, sets up the `wiki` command, upgrades your wikis, and asks before committing or pushing. It backs up each file it changes, and it's safe to run again.

## Check that it works

1. In a new session, ask: "What does your llm-wiki session context say?" Claude should quote a few lines naming the wiki for the repository you're in. If it has never heard of it, the plugin didn't load. See [Troubleshooting](troubleshooting.md).
2. Tell Claude a decision and its reason. For example: "We're using Postgres, not SQLite, because we need concurrent writers." The reply should end by naming a new file under `raw/`.
3. Open a fresh session in the same repository and ask about the decision. It should answer and cite a page under `wiki/`.

## What the plugin does

- **Points every session at the right wiki.** At session start, and again after `/clear` or compaction, it finds the wiki for the repository you're in and tells Claude to read its handbook first. Outside a repository, or in one with no wiki yet, it uses the shared wiki. The repository's own wiki appears the first time Claude has something to file there.
- **Gives Claude the skill** for finding, using and creating wikis.
- **Adds commands:**

  | Command | What it does |
  |---|---|
  | `/llm-wiki:status` | What needs attention across your wikis |
  | `/llm-wiki:save [focus]` | Save what this session established, then compile |
  | `/llm-wiki:compile [wiki]` | Turn waiting notes into pages now |
  | `/llm-wiki:standup [options]` | Your standup, from commits, journal and notes |

- **Offers to start an empty wiki from the repository's own docs**, with [`wiki seed`](using.md#start-a-wiki-from-a-repositorys-docs).
- **Saves before forgetting.** Right after the conversation is compacted, it asks Claude to capture anything in the summary that the wiki doesn't hold yet.
- **Keeps the `wiki` command current.** The plugin's files move to a new folder with every update. The `wiki` command lives in a folder that doesn't move, and each session points it at the newest version.

After that, you mostly don't do anything. [Using it](using.md) covers what Claude does on its own and what you can ask for.

## Updates

Every change pushed to this repo is a new version.

- **With auto-update on**, Claude Code fetches updates in the background.
- **Without it**, run `claude plugin marketplace update llm-wiki`, then `claude plugin update llm-wiki@llm-wiki`.
- **The `wiki` command** uses a new version as soon as it's installed. Sessions pick it up when they start: start a new one, or run `/reload-plugins` in a terminal session.
- **When an update changes the handbook**, Claude tells you once. Run `wiki upgrade --all` to bring your wikis up to it, then commit as it says.

`claude plugin list` shows the installed version, which is the commit it came from.

## A session that's already running

Sessions started before you installed the plugin don't have it. Say "save this session" in the old one first so nothing is lost, then start a new one.

## Uninstall

```
claude plugin uninstall llm-wiki@llm-wiki
```

Your wikis in `~/wikis` stay as they are. Remove `~/.local/bin/wiki` too, since it points into the plugin.
