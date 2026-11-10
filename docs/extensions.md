# Extensions

An extension is a command of your own that `wiki <name>` runs. It is how an integration, such as a tracker, a publisher or a CI job, lives outside `wiki.sh`, and how you add one for your team.

This is the foundation only. An extension can add a command today. It can't yet be called when a note is captured or a wiki is compiled, and it can't add rules to the handbook. Those come once a couple of real extensions show what they need.

## Extensions that ship with llm-wiki

Some come with llm-wiki and are off until you turn them on, on each machine:

```bash
wiki extensions add jira
```

`wiki extensions` lists them, on or off. `wiki extensions remove jira` turns one off. `wiki setup --new` asks about a new one once.

### Jira

`wiki jira` reads Jira and never writes to it. For every open item whose heading names a ticket, such as `Waiting: Katherine | Release PROJ-123`, it says where the ticket stands:

```
== propm
  Release PROJ-123
      PROJ-123     Done, resolved 2026-11-08
```

`wiki jira check --close` then saves a note with a `Done:` line for each item whose tickets are all done, and syncs the wiki. The next compile closes the item. `wiki jira show PROJ-123` prints one ticket, and `wiki jira config` shows what is set and tests the sign-in.

Settings go in `~/.config/llm-wiki/jira`:

```
url = https://your-company.atlassian.net
email = you@your-company.com
token_cmd = security find-generic-password -s jira -w
projects = PROJ, OPS
```

- `email` is for Jira Cloud, with an [API token](https://id.atlassian.com/manage-profile/security/api-tokens). Leave it out for Jira Data Center, where the token is a personal access token.
- `token_cmd` is a command that prints the token, so the token itself stays in your keychain or password manager and out of the file. `JIRA_API_TOKEN` in the environment works too.
- On a Mac, store the token from the clipboard: copy it, then run `security add-generic-password -a "$USER" -s jira -U -w "$(pbpaste)"`. Don't let `security` prompt for it: the prompt keeps only the first 128 characters, and an Atlassian token is longer.
- `projects` is optional. Without it, any word shaped like a key is looked up, and the ones Jira doesn't know are skipped.

To have agents check for themselves, add a line to a wiki's `wiki/conventions.md`: "Before treating an open item that names a ticket as still waiting, run `wiki jira check`."

### Confluence

`wiki confluence publish <wiki>` copies one wiki into a Confluence space, for people who read there and use neither git nor Obsidian. It goes one way. The wiki's index becomes a page called `<wiki> wiki`, and each page under `wiki/` becomes a child of it, named `<wiki>: <title>` because Confluence allows one title per space.

- **Only what changed is written.** A page whose text is the same as last time is left alone, so its history in Confluence stays short.
- **A page it didn't make is never overwritten.** Its own pages carry the label `llm-wiki`. If a title is already taken by someone else's page, that page is reported, the rest are published, and the command fails so you notice.
- **Nothing is deleted.** A page that has left the wiki is reported and stays in Confluence until you remove it there.
- **Links between pages** point at the published pages. A link to a raw note or a file has nothing to point at there, so only its text is kept. Images in the wiki aren't uploaded.
- **Every page starts with a note** that it is a copy and that changes made in Confluence are overwritten.

`wiki confluence publish <wiki> --dry-run` says what would change and writes nothing. `wiki confluence render <file.md>` prints one file as Confluence would be sent it, and `wiki confluence config` shows what is set and tests the sign-in.

Settings go in `~/.config/llm-wiki/confluence`:

```
url = https://your-company.atlassian.net/wiki
space = ENG
parent = 123456
space.payments = PAY
```

- `space` is the key of the space to publish into. `space.<wiki>` and `parent.<wiki>` set it for one wiki. `parent` is optional: the id of a page to publish under.
- `url`, `email` and `token_cmd` are as for Jira, and fall back to the Jira extension's settings, so on Atlassian Cloud one sign-in serves both.

Everyone who can read the space can read what you publish, and a wiki holds whatever its sessions noted. Publish a wiki only to a space whose readers may see all of it, and run the dry run first. An agent should ask before publishing.

It uses Confluence's first REST API, the only one Data Center has. Atlassian marks it deprecated on Cloud, where it still answers.

## Write one

An extension is an executable file named `wiki-<name>`, in any language, in the extensions folder. `wiki extensions path` prints the folder:

```bash
mkdir -p "$(wiki extensions path)"
```

A small one, saved there as `wiki-recent`:

```sh
#!/bin/sh
# wiki-extension: The five newest notes in a wiki.
ls -t "$WIKIS_DIR/${1:?usage: wiki recent <wiki>}/raw" | head -n 5
```

Make it executable, and it is a command:

```bash
chmod +x "$(wiki extensions path)/wiki-recent"
```

```bash
wiki recent global
```

`wiki extensions` lists the extensions on this machine. The description beside each one is its `wiki-extension:` comment, which goes in the first ten lines.

## What an extension is given

Its arguments, exactly as typed after the name, and three environment variables:

| Variable | What it holds |
|---|---|
| `LLM_WIKI` | The wiki command, as a path the extension can run: `"$LLM_WIKI" capture …`. |
| `WIKIS_DIR` | The collection this call is for. Commands the extension runs through `$LLM_WIKI` use the same one. |
| `LLM_WIKI_EXTENSION` | The version of this contract, `1` today. It rises only if one of these changes. |

The extension's exit code is the command's. Its output goes straight to the terminal.

To save knowledge, run `"$LLM_WIKI" capture <wiki> <slug>` with the note on stdin, then `"$LLM_WIKI" sync <wiki>`. Don't write into `raw/` or `wiki/` yourself: capture names the note and sync takes its turn with other sessions.

## Rules

- **Names.** Lowercase letters, digits and dashes, starting with a letter.
- **A command of llm-wiki's own always wins.** An extension named `wiki-status` is never run, and `wiki extensions` says so.
- **Extensions are per machine.** The folder is outside every collection, so pulling a shared collection can never add a command to your machine. To share one with a team, keep it in a repository and have each person copy or link it into their folder.
- **`LLM_WIKI_EXTENSIONS_DIR`** names a different folder.

An extension runs with your permissions and can read every wiki. Install one only if you would run its code yourself.
