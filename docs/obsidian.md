# llm-wiki in Obsidian

Keep your wikis in Obsidian: read them there, type notes there, and run llm-wiki's commands from Obsidian's command palette. Your agent still writes the pages. Obsidian is where you read them and where your own notes come in.

Your wikis are a folder of plain markdown, and an Obsidian vault is a folder too. So the setup is: make that folder, then open it in Obsidian as a vault.

## What you need

- Obsidian on a computer. A phone can be added later, for reading and for typing notes.
- llm-wiki installed, so that `wiki` runs in a terminal. If it doesn't yet, follow [Set up with Claude Code](claude-code.md) or [Set up with another agent](other-agents.md) first, then come back.

## Set it up

About five minutes. Every command is typed in a terminal.

1. **Make the wikis folder.** This creates `~/wikis` with one shared wiki in it. If you already have it, skip this step.

   ```bash
   wiki init
   ```

2. **Prepare it for Obsidian.** This writes Obsidian's starter settings for the folder and makes an `inbox` folder for your own notes.

   ```bash
   wiki obsidian
   ```

   The first time, it tells you to open the folder by hand: in Obsidian, choose **Open folder as vault** and pick `wikis` in your home folder. Obsidian only needs showing once. After that, `wiki obsidian` opens the vault for you.

3. **Add llm-wiki's commands to Obsidian.**

   ```bash
   wiki obsidian --plugin
   ```

   Then close the vault's window and open the vault again. Obsidian asks **Do you trust the author of this vault?** The plugin it means is the one you just added, so choose **Trust author and enable plugins**. If it doesn't ask, open **Settings**, then **Community plugins**, choose **Turn on community plugins**, and check that **llm-wiki** is switched on in the list.

   You can tell it worked from the status bar at the bottom right, which now reads `wiki: nothing waiting`.

4. **Choose how your wikis are backed up.** Pick one.

   - **An app carries the folder**, such as Obsidian Sync or iCloud. Then you don't need git. Tell llm-wiki, naming the app, and it keeps every earlier version of your pages on this computer:

     ```bash
     wiki history on "Obsidian Sync"
     ```

   - **Git.** This keeps every version too, and can copy your wikis to a private place such as GitHub:

     ```bash
     wiki setup git
     ```

   If you do neither, your wikis work, but there is one copy of them and no way back from a bad change.

That's all. Ask your agent a question about your project, or tell it something worth keeping, and pages start to appear in the vault.

## Day to day

Read in Obsidian, and tell your agent what to change. Agents maintain the pages, so a sentence you type into a page may be rewritten at the next compile. To add something of your own, use one of these.

- **Type a note in the `inbox` folder.** Any markdown file there becomes a note of the shared wiki, and the next agent session works it into the pages. A wiki can have an `inbox` folder of its own, for notes about that project.
- **Save the note you're looking at.** Open the command palette, type `llm-wiki`, and choose **Save this note to a wiki**. A note inside a wiki's folder goes to that wiki. For any other note, it asks which.

The other commands, all under `llm-wiki` in the command palette:

| Command | What it does |
|---|---|
| What needs attention | Every wiki: notes waiting, what is due, and what to do about each. Also the inbox icon in the left bar. |
| Take in the inbox now | Takes your inbox notes in now, without waiting for a session, and says why any was left. |
| Find across every wiki | Searches every wiki for a word or phrase. |
| Sync: save and share this wiki | For the wiki of the page in view. With git, it commits and pushes. With `wiki history`, it saves a snapshot. |
| Compile this wiki's waiting notes | Asks an agent to work the waiting notes into pages, in the background. |

The status bar shows how many notes are waiting. When you open a page of a wiki that an agent is compiling at that moment, a notice says so, so that you don't type into a page that is about to be rewritten.

To look back, where you chose `wiki history`: `wiki history` lists the snapshots, and `wiki history show <snapshot> <file>` prints a page as it was. To put a page back, ask your agent to restore it from a snapshot.

## On a phone

The plugin runs a command on your computer, so it doesn't work on a phone. Reading does, and so does the inbox: once Obsidian Sync or iCloud carries the vault to your phone, type a note in `inbox` there. It reaches your computer with the sync, and the next session takes it in.

## A vault you already have

The steps above make a new vault at `~/wikis`. That is the simplest way, and the one to choose if you can.

To keep your wikis inside a vault you already have, name that folder in each setup command:

```bash
WIKIS_DIR="$HOME/My Vault" wiki init
WIKIS_DIR="$HOME/My Vault" wiki obsidian --no-open
WIKIS_DIR="$HOME/My Vault" wiki obsidian --plugin
```

Your own notes are left as they are. The folder gains a `WIKIS.md` file, a `global` wiki, an `inbox` folder, and two small items llm-wiki keeps for itself, `journal` and `delegation.md`.

The plugin's commands then work in that vault with nothing more. Your agent is different: it looks in `~/wikis` unless told otherwise. For sessions started from a terminal, add this line to your shell profile, `~/.zshrc` on a Mac:

```bash
export WIKIS_DIR="$HOME/My Vault"
```

A session started some other way, such as from the Claude desktop app, doesn't read that file, and still looks in `~/wikis`. That is the reason to prefer a vault at `~/wikis`.

## After an update

The plugin in your vault is a copy. After `wiki update`, bring it up to date and restart Obsidian:

```bash
wiki obsidian --plugin
```

## What it touches

- The plugin goes in the one vault that holds your wikis. It does nothing in any other vault, even if it were copied there.
- It runs the `wiki` command on your computer, only when you choose a command, apart from the count for the status bar. It sends nothing anywhere itself.
- Where the `wiki` command is, is written in `~/.config/llm-wiki/obsidian-command`, on your computer and not in the vault. So nothing a sync brings into the vault can change what runs.
- With `wiki history`, the earlier versions are kept in `~/.local/state/llm-wiki/history`, outside the vault, and never leave your computer. Hidden files are not kept.

## Things to avoid

- **Two apps carrying one folder.** Use Obsidian Sync or a cloud drive, never both.
- **The Obsidian Git plugin on this vault.** It commits on a timer and can rewrite history. `wiki sync` already does the committing and pushing.
- **Two computers compiling at once.** One can't see that the other has started. Let one session finish before another starts elsewhere.
- **Passwords in notes.** With git, `wiki setup git` can add a check that looks for them before anything is pushed. Without git, nothing looks before the app carries the note.

## If something is off

[Troubleshooting](troubleshooting.md#obsidian) has the common ones: the status bar says the command is not set up, Obsidian says the vault is not found, the plugin doesn't appear, or an inbox note isn't taken.

For how each piece works in more detail, see [Using it](using.md#browsing-in-obsidian).
