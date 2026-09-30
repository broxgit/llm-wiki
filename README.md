# llm-wiki

A knowledge base that an LLM agent maintains as plain markdown. Sources get compiled once into small linked pages. Questions get answered from the pages.

## What's here

```
AGENTS.md    The handbook. Every rule lives here.
CLAUDE.md    One-line pointer to AGENTS.md.
index.md     One line per wiki page. The map.
log.md       Append-only record of changes.
raw/         Immutable sources.
wiki/        Compiled pages.
data/        Structured data (CSV, SQLite).
skills/      Optional Claude skill that finds and runs the wiki.
```

## Use it

Point an agent at this folder and tell it to read `AGENTS.md`. Then hand it a source and say "ingest", or ask a question.

- **Claude:** `CLAUDE.md` already points at `AGENTS.md`. The skill in `skills/llm-wiki/` is optional. It lets Claude find the wiki and scaffold new ones without being told. To install it, zip the `skills/llm-wiki` folder with the folder at the zip root and add it under Customize > Skills.
- **Other tools:** many read `AGENTS.md` on their own. If yours doesn't, paste it into the system prompt.

## Notes

- `AGENTS.md` in this folder is the source of truth. The skill carries a copy as a template for new wikis. Where the two differ, this folder's copy wins.
- Pull before ingesting. Every ingest touches `index.md` and `log.md`.
- Anyone with the repo sees everything in it. Keep private knowledge in a separate wiki.
