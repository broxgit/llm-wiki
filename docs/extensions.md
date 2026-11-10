# Extensions

An extension is a command of your own that `wiki <name>` runs. It is how an integration, such as a tracker, a publisher or a CI job, lives outside `wiki.sh`, and how you add one for your team.

This is the foundation only. An extension can add a command today. It can't yet be called when a note is captured or a wiki is compiled, and it can't add rules to the handbook. Those come once a couple of real extensions show what they need.

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
