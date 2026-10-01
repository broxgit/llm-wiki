# llm-wiki

A template for knowledge bases that an LLM agent maintains as plain markdown. Sources get compiled once into small linked pages. Questions get answered from the pages.

This repo holds the rules and the scaffold. It is not a wiki. Each wiki lives in its own folder, one per project, plus a shared one for knowledge that applies everywhere. A project is usually one code repository. It can also be a group of repositories that make up one product.

**Contents**

1. [Setup, once per machine](#setup-once-per-machine)
2. [Use it in every new session](#use-it-in-every-new-session)
3. [Use it in an existing session](#use-it-in-an-existing-session)
4. [Check that it works](#check-that-it-works)
5. [What the agent does on its own](#what-the-agent-does-on-its-own)
6. [Many repositories](#many-repositories)
7. [Run several sessions at once](#run-several-sessions-at-once)
8. [Share it with a team or a second machine](#share-it-with-a-team-or-a-second-machine)
9. [Troubleshooting](#troubleshooting)
10. [Change the rules](#change-the-rules)
11. [What's here](#whats-here)
12. [Install the skill](#install-the-skill)

## Setup, once per machine

You need an agent that can read and write files on this machine. Any model works.

1. Clone this repo. Anywhere is fine.

   ```
   git clone <this repo's URL> ~/dev/llm-wiki
   ```

2. Create the wiki collection. Run this from the clone. It makes `~/wikis`, the shared wiki `~/wikis/global`, and with `--git` one git repo that holds every wiki.

   ```
   ./wiki.sh init --git
   ```

3. Optional. Give the collection a remote so it syncs.

   ```
   cd ~/wikis
   git remote add origin <a private repo URL>
   git push -u origin HEAD
   ```

4. Give your agent access to `~/wikis` and to this clone. Agents that are sandboxed to a project folder need both added as extra folders.
   - Claude Code: start it with `--add-dir ~/wikis`, or approve the prompt the first time it reaches for the folder.
   - Claude desktop app: add both folders to the session.

5. Optional, Claude only. [Install the skill](#install-the-skill).

## Use it in every new session

One line in your tool's user-level instruction file covers every repository on the machine. For Claude Code that file is `~/.claude/CLAUDE.md`, and this command adds the line:

```
./wiki.sh claude
```

The line tells each session to find the wiki that covers the repository it is working in and read its handbook. If you already ran this command with an older version of the template, run it again. It replaces its own line and leaves the rest of the file alone. A repository with no wiki yet gets one the first time a session has something to file. Nothing needs setting up per repository.

For any other tool, put the same line in whatever file it loads at the start of every session. `./wiki.sh claude` prints the text.

Two alternatives, if you want tighter control:

- **Per project.** Add this to one project's own instruction file (`AGENTS.md`, `CLAUDE.md`, or similar):

  > This project's knowledge wiki is at `~/wikis/<repository-name>`. Read its AGENTS.md at session start and follow it.

- **Stricter, Claude Code only.** A sentence relies on the agent choosing to open the file. An import loads the handbook at launch, every time. Put `@~/wikis/<repository-name>/AGENTS.md` on its own line in the project's `CLAUDE.md`. Claude Code asks once to approve it. The core handbook then costs roughly 2,600 tokens in every session.

With the skill installed, Claude also finds wikis in the folders a session can reach. A line is more dependable.

## Use it in an existing session

A session that is already mid-task can join at any point.

1. Make sure the session can reach `~/wikis` and this clone. See Setup step 4.
2. Paste:

   > Read AGENTS.md in `<path to this clone>` and follow it. My wiki root is `~/wikis/<repository-name>`.

3. Then say:

   > Save this session.

   The agent writes what the session has established so far into the right wikis as dated notes. It compiles them into pages at the next pause.

You can do this in several sessions at the same time. Saving never collides. From then on each session uses the wikis on its own.

## Check that it works

1. Tell the session a decision and its reason.
2. The reply should end by naming a new file under `raw/`.
3. Run `./wiki.sh status`. The wiki is listed, and nothing is left waiting after the next pause.
4. Open a fresh session and ask about that decision. It should answer and cite a page under `wiki/`.

## What the agent does on its own

The handbook tells the agent to use judgment, not wait for commands.

- **Query.** It checks the wikis before answering anything they might cover.
- **Capture.** It saves a note when the conversation produces a decision, an established or corrected fact, a solved problem, a research finding, or finished work.
- **Compile.** At a pause it turns waiting notes into wiki pages and updates the index and log.
- **Lint.** It runs a health check after every 10 ingests.

It tells you briefly what it wrote. It still asks before resolving a contradiction or merging, deleting, or restructuring pages. If it doubts a fact you gave it, it files the fact, marks it with a `Check` line, and says so.

**Stale knowledge.** The world changes and pages don't. Each page records the date its claims were last confirmed and, for claims about code, the commit. Before the agent writes code or publishes something that depends on a page, it checks the page against the code, or against the cited source for facts like votes, quotes, and figures, when that is at hand. If the page is wrong it tells you and files a correction. When it answers from a page it couldn't check that is more than 90 days old, it says when the page was last verified. `./wiki.sh stale` lists pages past that age.

You can always steer it. "Don't save that" and "off the record" cover one item. "Leave the wiki alone" stops everything. "Save this", "ingest", and "lint" force it.

## Many repositories

The design goal: a session working in repository A that needs a client from repository D finds what any earlier session learned about that client.

Three rules in the handbook make that work.

- **One wiki per project, found by repository name.** For a single repository the wiki is named after it: the last part of its remote URL. So the wiki for a dependency is found by name, with no search and no configuration. See below for projects that span several repositories.
- **Knowledge lives with its owner.** What a session learns about D's client goes in D's wiki, even when the session is working in A. A's wiki keeps only what is specific to how A uses it, and cites D's page.
- **Look before you read source.** When the work touches another repository, the agent reads that repository's wiki index before answering from its code or from general knowledge.

Around those:

- **Wikis appear on demand.** The first session with something to file about a repository creates its wiki. A missing folder just means nothing is recorded yet.
- **Unknown owner.** The agent searches the indexes by keyword and opens only the wikis that match. `./wiki.sh find <word>` does the same for you.
- **Shared knowledge.** Third-party libraries, tooling, and conventions go in the shared wiki. Each wiki's `links.md` lists the shared wikis it falls back to, and ships pointing at `~/wikis/global`. A line whose path doesn't exist on a machine is skipped.
- **Citations.** Pages refer to other wikis as `repository-name:wiki/path.md`. They never copy.

Keep work and personal knowledge in separate collections.

### One project, several repositories

Some repositories are really one product. One piece of work touches several of them, and the same facts matter to all of them. Give those one wiki. Splitting them makes the agent file the same fact in two places.

```
./wiki.sh new my-product
./wiki.sh cover my-product repo-one repo-two repo-three
```

`cover` lists the repositories in the wiki's `repos.md`. A session in any of them then resolves to `my-product`, and `./wiki.sh which repo-two` prints it. Inside the wiki, shared knowledge is filed once by topic, and each repository gets a page only for what is specific to it.

The test for grouping: if one session routinely works across the repositories, they are one wiki. If each is worked on alone and they only call each other, keep them separate.

## Run several sessions at once

- **Capture** adds one new timestamped file to `raw/` and touches nothing else. Any number of sessions can do it at once.
- **Compile** changes shared files, so a lock file (`.compile-lock`) keeps it to one session at a time per wiki. A session that finds the lock held skips compiling and carries on.

Reading and querying are always safe.

## Share it with a team or a second machine

Make the collection one git repo (`./wiki.sh init --git`) and give it a remote. Then on each other machine:

1. Clone this template repo.
2. Clone the collection repo to `~/wikis`.
3. Repeat Setup step 4 and `./wiki.sh claude`.

The handbook tells agents to pull before writing and to commit and push after, touching only the wiki folders they changed. Two people changing the same wiki resolve like any git conflict. Index and log conflicts keep both sides' lines.

`WIKIS.md` at the top of the collection is what tells agents the folder is a collection. A single wiki can also be its own repo: `./wiki.sh new <path> --git`. A wiki inside some other repo is never committed by the agent.

## Troubleshooting

- **The agent ignores the wiki.** It never read the handbook. Run `./wiki.sh claude`, or paste the line from [Use it in an existing session](#use-it-in-an-existing-session). In Claude Code, `/context` lists the instruction files that loaded.
- **The agent can't read or write the wiki.** It lacks folder access. See Setup step 4.
- **Notes pile up in `raw/` and never become pages.** Run `./wiki.sh status` to see what is waiting and who holds the lock. Say "ingest" to force a compile. A lock older than 30 minutes is ignored. `./wiki.sh unlock <name>` frees one right away.
- **Knowledge landed in the wrong wiki.** Tell the agent where it belongs. Moving pages is the one thing it asks about first.
- **It saves too much or too little.** Edit the capture list under "Act without being asked" in `template/AGENTS.md`, bump the version, then upgrade.
- **An answer came from an out-of-date page.** Tell the agent what changed. It files a correction. `./wiki.sh stale` shows what else hasn't been checked in a while.
- **A wiki's handbook is behind the template.** `./wiki.sh status` flags it. `./wiki.sh upgrade --all` brings every wiki up to date. Outside git it keeps the old handbook as `AGENTS.md.bak`.
- **An agent's commit won't push.** The collection repo needs a working git identity and key on this machine, like any repo.

## Change the rules

The handbook is `template/AGENTS.md` plus the files in `template/rules/`. `AGENTS.md` loads in every session, so it holds only what every session needs. The rules files are read on demand: compile, conflicts, lint, peers.

Edit any of them, bump the version at the top of `template/AGENTS.md`, and run `./wiki.sh upgrade --all` to roll it out.

`ROADMAP.md` lists planned improvements and what is still untested.

## What's here

```
AGENTS.md          Tells an agent this is the template and how to start a wiki from it.
CLAUDE.md          Imports AGENTS.md for Claude Code.
ROADMAP.md         Planned improvements, untested areas, and what was decided against.
wiki.sh            Setup and upkeep: init, new, cover, which, status, find, stale, upgrade, unlock, claude.
template/          The scaffold. Copied whole to start a wiki.
  AGENTS.md        The core handbook. Loaded in every session.
  rules/           The rest of the handbook. Read on demand.
  CLAUDE.md        Imports the handbook for Claude Code.
  links.md         Shared wikis this one can fall back to.
  repos.md         Repositories this wiki covers, when more than one.
  raw/             Immutable sources.
  wiki/            Compiled pages.
  data/            Structured data (CSV, SQLite).
skills/llm-wiki/   Optional Claude skill that finds, runs, and scaffolds wikis.
```

Once in use, a wiki also holds `index.md` (one line per page) and `log.md` (the change record).

The script only does file work. It never overwrites a file and never touches a remote. Run `./wiki.sh` with no arguments for the command list. Set `WIKIS_DIR` to keep wikis somewhere other than `~/wikis`.

## Install the skill

Optional, Claude only. Zip the `skills/llm-wiki` folder with the folder at the zip root and add it under Customize > Skills. Without the skill, the lines above do the same job.
