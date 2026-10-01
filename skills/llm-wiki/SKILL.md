---
name: llm-wiki
description: Runs the user's markdown knowledge wikis without being asked. Checks them before answering, captures decisions and findings, ingests, lints, scaffolds. Use when a wiki or knowledge base is in play.
---

# LLM Wiki

The user keeps knowledge bases as plain markdown folders, one per code repository, plus shared ones for general knowledge. Each wiki's `AGENTS.md` is its handbook. The handbook is written to work with any model, so the rules live there, not here. This skill does three things: it finds the right wiki, hands control to its `AGENTS.md`, and scaffolds a new wiki when none exists.

The user does not want to hand-hold. Once a wiki is found, use it on your own judgment for the rest of the session.

## 1. Find the wiki

A wiki root is any folder that holds both `AGENTS.md` and `index.md`.

Look in this order:

1. A path the user gave in this conversation.
2. A path named in the project's own agent instruction file.
3. The folder under `~/wikis/` named after the repository the session is working in.
4. The current working directory and its parents.
5. Folders connected from the user's computer. Check each root and one level down.

The user keeps wikis under `~/wikis/` by convention, one folder per repository, with a shared one at `~/wikis/global`. The shared wiki is a fallback. It is the session's main wiki only when the user says so or the session is not working in any repository.

If the user's computer isn't linked, or no folder is connected, say so in one line and ask them to connect the wiki folder. Connecting `~/wikis` covers every wiki at once. If several project wikis turn up, ask which one this session should use. If none turn up, go to section 4.

Remember the root for the rest of the session. Don't search again.

### The template repo is not a wiki

The user keeps a template repo, usually named `llm-wiki`. It has a `template/` folder, a `wiki.sh` script, and an `AGENTS.md` that says it is a template. It has no `index.md`. Never store knowledge there. Use it only as the source for scaffolding.

## 2. Follow the handbook

Read `<root>/AGENTS.md` in full, then `<root>/index.md`. Do what `AGENTS.md` says. The copy in the wiki is the authority.

`AGENTS.md` is the core. It names files under `rules/` for compile work, conflicts, lint, and peer wikis. Read one of those only when `AGENTS.md` says the work calls for it.

Read and edit the files where they live. Pull a file into a scratch area only for a step that can't be done in place.

## 3. When to act

Don't wait to be asked. The handbook's "Act without being asked" section is the rule. In short:

- **Query** the wiki before answering anything it might cover.
- **Capture** on your own at milestones: a decision, an established or corrected fact, a problem solved, a research finding, finished work.
- **Compile** pending files at a pause, under the compile lock. Skip it if another session holds the lock.
- **Check before acting.** Before you write code that depends on a wiki claim, check the claim against the code if the code is at hand. File a correction when it no longer holds.
- **Lint** under the lock when the log shows 10 or more ingests since the last one.
- **Ask first** before resolving a contradiction, merging or deleting pages, or restructuring.
- **Other wikis.** Wikis in the same folder are peers, named after repositories. File what you learn about another repository in that repository's wiki, and check a peer's index when the work touches its code. `links.md` names shared wikis for general knowledge. Cite other wikis' pages instead of copying them.
- **Hold back** when the user says so. "Don't save that" and "off the record" cover that one item. "Leave the wiki alone" stops all writes.

Direct requests still work: "save this", "save this session", "ingest", "lint". "Save this session" works mid-conversation in a session that started before the skill was loaded.

Tell the user what you wrote, briefly, at the end of the reply. For a capture, the file path. For compile work, pages created, pages updated, corrections applied, conflicts found.

Leave the wikis alone for questions clearly outside the subject of this wiki and the others. Reading an index costs tokens.

## 4. Scaffold a new wiki

If no wiki turned up and the user didn't ask for one, offer once to set one up, then drop it. Scaffold only when the user asks or agrees.

1. Settle the location. The default is `~/wikis/<repository-name>`, named after the repository the session is working in. Use it without asking when `~/wikis` already exists. Otherwise confirm with the user. One wiki per repository, not one per session. Never inside the template repo.
2. Build it from one of these, in this order:
   - **The template repo.** Run its `wiki.sh new <wiki root>`. Without a shell, copy everything inside its `template/` folder into the new root, hidden files included, then create `index.md` containing `# Index` and `log.md` containing `# Log`.
   - **An existing wiki.** Copy its `AGENTS.md`, `CLAUDE.md`, `links.md`, `.gitignore`, and `rules/` folder. Add `raw/`, `wiki/`, and `data/` folders. Create `index.md` and `log.md` as above.
   - **Neither is reachable.** Don't write a handbook from memory. Tell the user the template repo is needed and ask where it is.
3. Check `links.md`. If the shared wiki it points at doesn't exist, offer once to scaffold it the same way.
4. If the wiki sits inside a project folder, or this session is working in one, and that project has its own agent instruction file that doesn't mention the wiki, offer once to add this line to it: `This project's knowledge wiki is at <wiki root>. Read its AGENTS.md at session start and follow it.` That line lets future sessions find the wiki with no prompting.
5. If the folder isn't in a git repo, offer to initialize one. Git gives the wiki history and undo.
6. Capture anything from the current session that meets the handbook's bar.
