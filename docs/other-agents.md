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
- **Any other agent:** `./wiki.sh claude --print` prints the line. Put it in whatever file your agent loads at the start of every session. For Codex that is `~/.codex/AGENTS.md`. For Gemini CLI and Antigravity it is `~/.gemini/GEMINI.md`: `./wiki.sh claude --print > ~/.gemini/GEMINI.md`, if the file holds nothing else. Check your agent's docs for others.
- **Already on the plugin, adding another agent:** no clone needed. `wiki claude --print` prints the line with the plugin's stable `wiki` command in it.

The line tells the agent where `wiki.sh` is. The handbooks name its commands (`wiki.sh capture`, `wiki.sh sync`, and others) without a path, and an agent that can't find the script falls back to doing those steps by hand. The agent also needs to run commands in `~/wikis` and in the clone, so allow both.

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

Pull the clone, then run setup in its catch-up mode:

```
git -C ~/dev/llm-wiki pull
./wiki.sh setup --new
```

It asks only about what's new on this machine: new settings, handbooks behind the template, a session line that changed. `./wiki.sh status` says when there is something to do.

## Commands

The rest of the docs write commands as `wiki <command>`, which is how plugin users run them. From a clone, run `./wiki.sh <command>` in the clone, or link it once so `wiki` works anywhere:

```
ln -s ~/dev/llm-wiki/wiki.sh ~/.local/bin/wiki
```
