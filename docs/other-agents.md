# Set up with another agent

For Codex, Cursor, Copilot, Gemini, the Claude desktop app's **Chat** tab, claude.ai, or Claude Code without the plugin. Any agent that can read and write files on your machine works, with any model. About ten minutes.

Using Claude Code, including the desktop app's **Code** tab? [The plugin](claude-code.md) is less work.

## Install

1. Clone this repo. Anywhere is fine.

   ```
   git clone https://github.com/broxgit/llm-wiki.git ~/dev/llm-wiki
   ```

2. Run setup from the clone:

   ```
   cd ~/dev/llm-wiki
   ./wiki.sh setup
   ```

   It asks one question at a time, and Enter takes the suggested answer. It creates your wiki collection in `~/wikis` with a shared wiki, `~/wikis/global`, makes the collection a git repo, and walks through the [work journal](using.md#work-journal-and-standups). For Claude Code, it also adds the session line below.
3. Give your agent access to `~/wikis` and to the clone. Agents sandboxed to one project folder need both added as extra folders.
   - Claude Code: start it with `--add-dir ~/wikis`, or approve the prompt the first time it reaches for the folder.
   - Claude desktop app: add both folders to the session or conversation.
4. Point every session at its wiki. See the next section.
5. Install gitleaks, which stops agents from committing a secret: `brew install gitleaks`.

Joining a team that already has a shared collection? Do [Teams](teams.md#join-a-shared-collection) before step 2.

## Point every session at its wiki

One line in your agent's user-level instruction file covers every repository on the machine. It tells each session to find the wiki for the repository it's in and read its handbook.

- **Claude Code without the plugin:** `./wiki.sh setup` adds it to `~/.claude/CLAUDE.md`. So does `./wiki.sh claude`.
- **Any other agent:** `./wiki.sh claude --print` prints the line. Put it in whatever file your agent loads at the start of every session. For Gemini CLI that is `~/.gemini/GEMINI.md`. Check your agent's docs for others.
- **Antigravity and Codex:** use their plugins instead of a line. See [Antigravity](#antigravity) and [Codex](#codex) below. Cursor gets a hook too, and still takes a line: see [Cursor](#cursor).
- **Already on the plugin, adding another agent:** no clone needed. `wiki claude --print` prints the line with the plugin's stable `wiki` command in it.

The line tells the agent where `wiki.sh` is. The handbooks name its commands (`wiki.sh capture`, `wiki.sh sync`, and others) without a path, and an agent that can't find the script falls back to doing those steps by hand. The agent also needs to run commands in `~/wikis` and in the clone, so allow both.

### Antigravity

`wiki setup` notices Antigravity and offers an llm-wiki plugin for it, in `~/.gemini/config/plugins/llm-wiki/`. It's the counterpart of the Claude Code plugin:

- **A rule** that says where your wikis are and where `wiki.sh` is.
- **A SessionStart hook** that runs `wiki start` for the open project and hands its output to the conversation: the wiki, a pull, the indexes, `For agents`, and what waits. The model starts with it instead of spending its first calls on it.
- **The llm-wiki skill.**

Add it any time with `wiki setup antigravity`, then quit and reopen Antigravity once so it finds the new plugin. The same step offers Antigravity grants for what llm-wiki needs: read and write `~/wikis`, read the template, and run `wiki.sh`. Without them Gemini asks before each file and command. `wiki permissions` prints them. It adds nothing else: grants for git, npm and the like are yours to choose. Later updates reach new conversations on their own. If `~/.gemini/GEMINI.md` still has the wiki line from before, setup offers to remove it, so conversations don't get it twice.

Antigravity has separate settings for files and for commands, and the second matters here:

- **Non-Workspace File Access** lets the agent's file tools read and write `~/wikis`. Set it to `allow`.
- **Terminal Sandbox** and the **Command Allowlist** govern the commands it runs, `wiki.sh` among them. With the sandbox on, add `wiki.sh` to the allowlist or approve it when asked, or `wiki.sh` can't read or write `~/wikis`.

The agent captures notes with `wiki.sh capture <wiki> <slug> --file <note>`, a command with no pipe or heredoc, which an approval can cover from then on.

### Codex

`wiki setup` notices Codex and offers an llm-wiki plugin for it, the counterpart of the Claude Code plugin. Add it any time with `wiki setup codex`. It sets up three things:

- **A plugin with two hooks.** At session start it runs `wiki start` for the repository and hands its output to the session: the wiki, a pull, the indexes, `For agents`, and what waits. After compaction it tells the session to capture what the summary holds before answering. The plugin lives in `~/.codex/llm-wiki`, a local marketplace that setup adds and installs with the `codex` command.
- **A line in `~/.codex/AGENTS.md`** that says where your wikis are and that the hook runs `start`. It replaces the session line if you pasted one there before.
- **The llm-wiki skill and your team skills,** linked into `~/.codex/skills`.

Codex runs a plugin's hooks only once you trust them, and the desktop app doesn't ask. Run `codex` in a terminal once. It says 2 hooks need review: type `/hooks` and trust both, SessionStart and PostCompact. Each runs your `wiki` command with `__codex-start`. They stay the same across llm-wiki updates, so you trust them once.

Codex's sandbox blocks writes inside `~/wikis/.git`, even when `~/wikis` itself is writable. Hooks run outside it, so the pull at session start works. `wiki sync`, which commits, runs inside it: approve it to run outside the sandbox when Codex asks.

### Cursor

**With the Claude Code plugin installed,** Cursor needs nothing more. It loads Claude Code's installed plugins from the same copy Claude Code runs, so each session gets the plugin's hook. `wiki status` says when that copy is behind, and `wiki update` refreshes it.

**Without it,** `wiki setup cursor` adds a sessionStart hook to `~/.cursor/hooks.json`, Cursor's own hooks file, leaving any other hooks there alone. The hook runs `wiki start` for the open folder and hands its output to the session: the wiki, a pull, the indexes, `For agents`, and what waits. Setup then prints a line for Settings → Rules → User Rules. It replaces any earlier wiki line there, and tells the agent the hook already ran `start`. Setup also links the llm-wiki skill and your team skills into `~/.cursor/skills`. If you install the Claude Code plugin later, this hook steps aside so sessions don't get the brief twice.

Cursor has no hook after compaction. Its preCompact reply reaches only you, not the model, so there's no capture reminder after compaction there.

Cursor's sandbox blocks the pull and writes under `~/wikis` until a command runs with full permissions, which it asks for. `wiki sync` needs that approval to commit.

**Sandboxed agents.** Some agents, Antigravity among them, run commands in a sandbox that blocks folders outside the open project. There, `wiki.sh` stops with "can't write" or "can't read … allow ~/wikis there", and git fails if your git config includes another file, such as a work identity. Allow `~/wikis`, the clone and `~/.gitconfig*` in the agent's settings. Otherwise the agent asks you to approve each command outside the sandbox, and it may skip steps such as the session-start pull.

**Check its work from its transcripts.** Antigravity keeps them at `~/.gemini/antigravity/brain/<conversation>/.system_generated/logs/transcript_full.jsonl`, so a Claude Code session can read what it ran and grade a run against the handbook.

Rerun `./wiki.sh claude` after a template update changes the line, or paste the new `--print` output over the old line. It replaces its own line and leaves the rest of the file alone.

For tighter control, two alternatives:

- **Per project.** Add this to one project's own instruction file (`AGENTS.md`, `CLAUDE.md`, or similar):

  > This project's knowledge wiki is at `~/wikis/<repository-name>`. Read its AGENTS.md at session start and follow it.

- **Stricter, Claude Code only.** A sentence relies on the agent choosing to open the file. An import loads it every time. Put `@~/wikis/<repository-name>/AGENTS.md` on its own line in the project's `CLAUDE.md`. That costs roughly 2,900 tokens in every session.

**The desktop app's Chat tab and claude.ai:** they have no instruction file to put the line in. Zip the `skills/llm-wiki` folder, with the folder at the zip root, and add it under Customize > Skills. The skill finds wikis in the folders a conversation can reach, so connect `~/wikis` too.

## Check that it works

1. Tell the agent a decision and its reason. For example: "We're using Postgres, not SQLite, because we need concurrent writers."
2. The reply should end by naming a new file under `raw/`.
3. Run `./wiki.sh status`. The wiki is listed, and nothing is left waiting after the next pause.
4. Open a fresh session in the same repository and ask about the decision. It should answer and cite a page under `wiki/`.

If it doesn't, see [Troubleshooting](troubleshooting.md).

## A session that's already running

A session that is mid-task can join at any point.

1. Make sure it can reach `~/wikis` and the clone.
2. Paste:

   > Read AGENTS.md in `<path to the clone>` and follow it. My wiki root is `~/wikis/<repository-name>`.

3. Then say "save this session". The agent writes what the session has established so far into the right wikis.

## Updates

In the clone:

```
./wiki.sh update
```

It pulls the clone, then hands over to the new version, which pulls, upgrades and pushes every wiki collection, asks about anything new on this machine, and says how to bring sessions that are already open up to date. `./wiki.sh status` says when there is something to do.

## Commands

The rest of the docs write commands as `wiki <command>`, which is how plugin users run them. From a clone, run `./wiki.sh <command>` in the clone, or link it once so `wiki` works anywhere:

```
ln -s ~/dev/llm-wiki/wiki.sh ~/.local/bin/wiki
```
