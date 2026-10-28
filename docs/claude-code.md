# Set up with Claude Code

About five minutes. You need Claude Code and git. Not using Claude Code? Use [Set up with another agent](other-agents.md).

## Install

1. In Claude Code, add this repo as a plugin marketplace and install the plugin:

   ```
   /plugin marketplace add broxgit/llm-wiki
   /plugin install llm-wiki@llm-wiki
   ```

2. Turn on auto-update. Run `/plugin`, open Marketplaces, pick `llm-wiki`, and choose Enable auto-update. Marketplaces outside Anthropic's own start with it off, and without it you never get fixes.
3. Restart Claude Code and start a session in any repository.
4. In that session, say "set up the wiki command". Claude links a small `wiki` script into `~/.local/bin`, so your terminal can run it.
5. In a terminal, run:

   ```
   wiki setup
   ```

   It asks one question at a time, and Enter takes the suggested answer. It creates your wiki collection in `~/wikis`, makes it a git repo, and walks through the [work journal](using.md#work-journal-and-standups). If you skipped step 4, ask Claude for the command's full path.
6. Install gitleaks, which stops agents from committing a secret: `brew install gitleaks`.
7. If you added the wiki line to `~/.claude/CLAUDE.md` with an older version of this template, delete it. The plugin does its job, and both would load the handbook twice.

Joining a team that already has a shared collection? Do [Teams](teams.md#join-a-shared-collection) before step 5.

## Check that it works

1. In a session, tell Claude a decision and its reason. For example: "We're using Postgres, not SQLite, because we need concurrent writers."
2. The reply should end by naming a new file under `raw/`.
3. Open a fresh session in the same repository and ask about the decision. It should answer and cite a page under `wiki/`.

If it doesn't, see [Troubleshooting](troubleshooting.md).

## What the plugin does

- **Loads the right wiki into every session.** At session start, and again after `/clear` or compaction, it finds the wiki for the repository you're in and loads its handbook and index. Outside a repository, or in one with no wiki yet, it loads the shared wiki. The repository's own wiki appears the first time Claude has something to file there.
- **Gives Claude the skill** for finding, using and creating wikis.
- **Adds commands:**

  | Command | What it does |
  |---|---|
  | `/llm-wiki:status` | What needs attention across your wikis |
  | `/llm-wiki:save [focus]` | Save what this session established, then compile |
  | `/llm-wiki:compile [wiki]` | Turn waiting notes into pages now |
  | `/llm-wiki:standup [options]` | Your standup, from commits, journal and notes |

- **Keeps the `wiki` command current.** The plugin's files move to a new folder with every update. The `wiki` command lives in a folder that doesn't move, and each session points it at the newest version.

After that, you mostly don't do anything. [Using it](using.md) covers what Claude does on its own and what you can ask for.

## Updates

Every change pushed to this repo is a new version.

- **With auto-update on**, Claude Code fetches updates in the background. Run `/reload-plugins`, or restart, to load one.
- **Without it**, run `/plugin marketplace update llm-wiki`, then restart.
- **When an update changes the handbook**, Claude tells you once. Run `wiki upgrade --all` to bring your wikis up to it, then commit as it says.

## A session that's already running

Sessions started before you installed the plugin don't have it. Run `/reload-plugins`, or say "save this session" in the old one first so nothing is lost, then start a new one.

## The Claude desktop and web apps

They don't run Claude Code plugins. Zip the `skills/llm-wiki` folder, with the folder at the zip root, and add it under Customize > Skills. Then give the app access to `~/wikis`. The skill finds and uses the wikis, without the plugin's session hook.
