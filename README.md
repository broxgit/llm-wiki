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
7. [Hand work to cheaper models](#hand-work-to-cheaper-models)
8. [Stop repeating yourself](#stop-repeating-yourself)
9. [Work journal and standups](#work-journal-and-standups)
10. [Run several sessions at once](#run-several-sessions-at-once)
11. [Share it with a team or a second machine](#share-it-with-a-team-or-a-second-machine)
12. [Troubleshooting](#troubleshooting)
13. [Change the rules](#change-the-rules)
14. [What's here](#whats-here)
15. [Install the Claude Code plugin](#install-the-claude-code-plugin)

## Setup, once per machine

You need an agent that can read and write files on this machine. Any model works.

1. Clone this repo. Anywhere is fine.

   ```
   git clone <this repo's URL> ~/dev/llm-wiki
   ```

2. Run setup from the clone. It walks through every choice one question at a time, and Enter takes the suggested answer.

   ```
   ./wiki.sh setup
   ```

   It creates `~/wikis` and the shared wiki `~/wikis/global`, makes the collection one git repo, and adds a remote if you have one. It sets the commit email for that repo, and an SSH key for it if your usual key belongs to another account. Then it test-pushes, so a wrong key shows up now instead of in an agent's session. It adds the line that lets every Claude Code session find its wiki, upgrades any out-of-date handbooks, and walks through the [work journal](#work-journal-and-standups) settings.

   Rerun it any time. It shows what you have and changes only what you change.

   - `./wiki.sh setup --list` prints every setting, marks the ones still at their default, and asks nothing.
   - `./wiki.sh setup git` or `./wiki.sh setup journal` reruns one section.
   - `./wiki.sh setup journal.format`, or just `./wiki.sh setup format`, edits one setting.

   Prefer plain commands? `./wiki.sh init --git` creates the collection and repo, and `./wiki.sh claude` adds the session line.

3. After you pull template updates, run:

   ```
   ./wiki.sh setup --new
   ```

   It asks only about what you haven't seen on this machine: new settings, handbooks behind the template, a session line that changed. `./wiki.sh status` says when there is something new.

4. Give your agent access to `~/wikis` and to this clone. Agents that are sandboxed to a project folder need both added as extra folders.
   - Claude Code: start it with `--add-dir ~/wikis`, or approve the prompt the first time it reaches for the folder.
   - Claude desktop app: add both folders to the session.

5. Claude Code: [install the plugin](#install-the-claude-code-plugin). It finds each session's wiki for you, so you can skip the next section.

## Use it in every new session

With the [Claude Code plugin](#install-the-claude-code-plugin) installed, skip this section: its session hook does this job. For other tools, or Claude Code without the plugin:

One line in your tool's user-level instruction file covers every repository on the machine. For Claude Code that file is `~/.claude/CLAUDE.md`, and this command adds the line:

```
./wiki.sh claude
```

The line tells each session to find the wiki that covers the repository it is working in and read its handbook. If you already ran this command with an older version of the template, run it again. It replaces its own line and leaves the rest of the file alone. A repository with no wiki yet gets one the first time a session has something to file. Nothing needs setting up per repository.

For any other tool, put the same line in whatever file it loads at the start of every session. `./wiki.sh claude` prints the text.

Two alternatives, if you want tighter control:

- **Per project.** Add this to one project's own instruction file (`AGENTS.md`, `CLAUDE.md`, or similar):

  > This project's knowledge wiki is at `~/wikis/<repository-name>`. Read its AGENTS.md at session start and follow it.

- **Stricter, Claude Code only.** A sentence relies on the agent choosing to open the file. An import loads the handbook at launch, every time. Put `@~/wikis/<repository-name>/AGENTS.md` on its own line in the project's `CLAUDE.md`. Claude Code asks once to approve it. The core handbook then costs roughly 2,900 tokens in every session.

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
- **Capture.** It saves a note when the conversation produces a decision, direction from you, an established or corrected fact, a solved problem, or a research finding. It does not log finished work, since the code and its git history already do. It captures at stopping points, about one or two notes an hour in a long session.
- **Compile.** It turns waiting notes into wiki pages at session start, at a pause, and whenever five are waiting.
- **Lint.** Every compile checks the log, and runs a health check once 10 ingests have passed since the last one.

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

## Hand work to cheaper models

A session on your most capable model doesn't need to spend it on a test run or a sweep across 200 files. Sessions hand that kind of work to sub-agents on cheaper models and keep design, debugging and review for themselves. Handing off is only worth it when the work is big, needs nothing from the conversation, and its result can be checked, so the session checks before relying on it.

Your preferences live in `~/wikis/delegation.md`. Git ignores it, so each person and each machine keeps its own:

- **mode:** `off` never hands off unless you ask. `ask`, the default, suggests each handoff in one line and waits for a yes. `auto` hands off and tells you after.
- **Who does what:** a table of kinds of work, each with a model and effort. Rows marked `stay` never leave the session. Edit it to match the models your tool offers.
- **Auto:** kinds of work you've approved without asking. After you say yes to the same kind three times, the session offers to add it here.

`./wiki.sh setup delegation` sets the mode. `./wiki.sh delegation` shows the mode and, from a log on this machine, how often each kind of handoff came back fine, needed fixing, or was redone. Kinds that keep getting redone get a suggestion to move up a model.

This needs a tool that can run sub-agents on a chosen model, such as Claude Code. Elsewhere sessions do the work themselves.

## Stop repeating yourself

Agents learn from repeat feedback. When you correct an agent, paste review comments on code it wrote, or watch it do the same steps again, it notes that in the wiki. Once the same thing has come up a few times, it asks one question with the evidence and offers a fix:

- **The same review comment keeps coming back.** It becomes a line on the project's conventions page, and agents check code against it before calling the work done.
- **You keep correcting how a shared library is used**, such as "go-common already records request metrics, don't add them". The rule goes in that library's wiki, so every repository that calls the library gets it.
- **The same procedure in different repositories** becomes a skill, or a how-to page for agents without skills.
- **The same mechanical steps over and over** become a small script, so the next run costs a command instead of a pile of tokens.

A pattern is ready after 3 sightings, or 2 when they are review comments or come from different repositories. A "no" is remembered, and that pattern is only raised again if it keeps happening. `./wiki.sh patterns` shows what every wiki is tracking. The rules are in `template/rules/patterns.md`.

Paste merge request comments into the session that wrote the code. They are the best evidence there is.

## Work journal and standups

Ask any session "what did I do yesterday?" or "give me my standup" and it answers from what you actually did.

It assembles the answer from records that already exist:

- **Your commits** in every repository under your code folders, matched to each repository's `user.email`. Other people's commits are left out.
- **Journal entries.** One line the agent writes at a stopping point for work that leaves no commit: an investigation, a review, a dead end, a deploy.
- **Wiki notes and wiki changes** in the range.
- **Work in progress.** Uncommitted files, unpushed commits, and open branches. These become "Today".
- **Open `Check` and `Conflict` lines** in the wikis. These become "Blockers".

`./wiki.sh standup` gathers that material. The agent writes it up as a standup (Yesterday, Today, Blockers), a summary by project, or a detailed report. You can run the command yourself to see the raw material.

```
./wiki.sh standup                      # last workday through now
./wiki.sh standup --since week --format summary --exclude 'personal-*'
./wiki.sh standup --day 2026-10-21 --only 'billing-*'
```

### Fill in past days

The journal starts empty, but your past sessions aren't lost. Claude Code keeps a transcript of each one.

```
./wiki.sh journal backfill --since 14d
```

This reads those transcripts and writes a short digest, `~/wikis/journal/backfill.md`: per day and project, what you asked for, which files changed, and how it ended. It needs `python3`. Then tell an agent "backfill my journal". It writes entries for those days from the digest, by the same rules as live entries, and deletes the digest. One entry by hand works too: `./wiki.sh journal note --day 2026-10-21 --at 16:40 <project> "<text>"`.

### Settings

The journal is on by default. Its settings live in `~/wikis/journal/config`. Walk through them with `./wiki.sh setup journal`, change one with `./wiki.sh journal set <key> <value>`, and see them with `./wiki.sh journal`.

| Setting | Default | What it does |
|---|---|---|
| `enabled` | `yes` | Turns the whole feature on or off. Also `./wiki.sh journal on` and `off`. |
| `commit` | `no` | `yes` commits and pushes journal files with the wikis. `no` keeps them on this machine and adds `journal/` to the collection's `.gitignore`. |
| `entries` | `yes` | `no` stops the agent writing journal lines. Reports still use commits and wiki notes. |
| `format` | `standup` | Default report shape: `standup`, `summary`, or `detailed`. |
| `since` | `lastworkday` | Default range: `lastworkday`, `yesterday`, `today`, `week`, `lastweek`, a number of days like `7d`, or a date. |
| `day_starts` | `04:00` | Work before this local time counts toward the previous day. |
| `workdays` | `12345` | Days that count as workdays, 1 for Monday. A Monday standup then covers Friday. |
| `code_dirs` | `~/dev` | Folders to search for repositories, separated by colons. |
| `depth` | `4` | How deep to search them. |
| `authors` | empty | Extra commit emails or names that are you, separated by commas. |
| `exclude` | empty | Repositories and wikis to leave out, as comma-separated globs, such as `personal-*`. |
| `save` | `no` | `yes` saves each report as `journal/YYYY-MM-DD-<format>.md`. |
| `keep_days` | `0` | Deletes journal days older than this. `0` keeps everything. |

The journal is personal. It sits beside the wikis, not in one, and is not committed unless you set `commit` to `yes`. Leave it off if your collection's remote is shared or is not where work notes should go.

You can add a line yourself: `./wiki.sh journal note <project> "what you did"`.

## Run several sessions at once

- **Capture** adds one new timestamped file to `raw/` and touches nothing else. Any number of sessions can do it at once.
- **Compile** changes shared files, so a lock file (`.compile-lock`) keeps it to one session at a time per wiki. A session that finds the lock held skips compiling and carries on.

Reading and querying are always safe.

## Share it with a team or a second machine

Make the collection one git repo (`./wiki.sh init --git`) and give it a remote. Then on each other machine:

1. Clone this template repo.
2. Clone the collection repo to `~/wikis`.
3. Run `./wiki.sh setup` from the template clone. It finds the cloned collection and asks the rest: this machine's commit email and SSH key, the session line, the journal. Then repeat Setup step 4.

The handbook tells agents to pull before writing and to commit and push after, touching only the wiki folders they changed. When two people change the same wiki, each wiki's `.gitattributes` has git keep both sides' lines in `index.md` and `log.md`, so those merge on their own. A conflict inside a page resolves like any git conflict. The compile lock only covers sessions on one machine.

Agents push to that remote on their own, so `init --git` installs a pre-commit hook that runs [gitleaks](https://github.com/gitleaks/gitleaks) and refuses a commit holding a key, token or password. Install it on each machine: `brew install gitleaks`. Without it, commits go through with a warning, and `./wiki.sh status` says they aren't scanned.

The journal and `delegation.md` stay on each machine. `./wiki.sh status` says when a wiki's handbook is newer than your template clone, meaning a coworker upgraded it first. Pull the template.

`WIKIS.md` at the top of the collection is what tells agents the folder is a collection. A single wiki can also be its own repo: `./wiki.sh new <path> --git`. A wiki inside some other repo is never committed by the agent.

## Troubleshooting

- **The agent ignores the wiki.** It never read the handbook. Run `./wiki.sh claude`, or paste the line from [Use it in an existing session](#use-it-in-an-existing-session). In Claude Code, `/context` lists the instruction files that loaded.
- **The agent can't read or write the wiki.** It lacks folder access. See Setup step 4.
- **Notes pile up in `raw/` and never become pages.** Run `./wiki.sh status`. It flags any wiki with five or more notes waiting as `compile due`, and any wiki past 10 ingests as `lint due`. The next session there compiles at startup. Say "ingest" to force it now. A lock older than 30 minutes is ignored. `./wiki.sh unlock <name>` frees one right away.
- **Knowledge landed in the wrong wiki.** Tell the agent where it belongs. Moving pages is the one thing it asks about first.
- **It saves too much or too little.** Edit the capture list under "Act without being asked" in `template/AGENTS.md`, bump the version, then upgrade.
- **An answer came from an out-of-date page.** Tell the agent what changed. It files a correction. `./wiki.sh stale` shows what else hasn't been checked in a while.
- **A wiki's handbook is behind the template.** `./wiki.sh status` flags it. `./wiki.sh upgrade --all` brings every wiki up to date, then says what changed since the version each wiki was on and what to do about it: commit the upgrade, refresh the session line, look at new settings. Outside git it keeps the old handbook as `AGENTS.md.bak`.
- **A commit was refused for a secret.** The agent replaces it with `[REDACTED]` and commits again. If it isn't a secret, add the `Fingerprint` line gitleaks printed to `.gitleaksignore` at the top of the collection.
- **An agent's commit won't push.** Run `./wiki.sh setup git`. It sets the repo's commit email and SSH key and test-pushes. A machine with a work key and a personal key usually needs the key named for this repo.

## Change the rules

The handbook is `template/AGENTS.md` plus the files in `template/rules/`. `AGENTS.md` loads in every session, so it holds only what every session needs. The rules files are read on demand: compile, conflicts, lint, peers, journal, patterns, delegation.

Edit any of them, bump the version at the top of `template/AGENTS.md`, add a section for the new version to `CHANGELOG.md`, and run `./wiki.sh upgrade --all` (or `./wiki.sh setup --new`) to roll it out.

To add a journal setting, add one line to `JOURNAL_SETTINGS` in `wiki.sh`: key, type, basic or advanced, default, description. That line writes the config entry, validates `journal set`, and makes `./wiki.sh setup --new` ask about it on every machine. A setting for something other than the journal needs its own step in `cmd_setup`.

`ROADMAP.md` lists planned improvements and what is still untested.

## What's here

```
AGENTS.md          Tells an agent this is the template and how to start a wiki from it.
CLAUDE.md          Imports AGENTS.md for Claude Code.
ROADMAP.md         Planned improvements, untested areas, and what was decided against.
CHANGELOG.md       What each handbook version changed. upgrade prints the parts you missed.
wiki.sh            Setup and upkeep: setup, init, new, cover, which, status, find, stale, patterns, delegation, upgrade, unlock, claude, journal, standup.
template/          The scaffold. Copied whole to start a wiki.
  AGENTS.md        The core handbook. Loaded in every session.
  rules/           The rest of the handbook. Read on demand.
  CLAUDE.md        Imports the handbook for Claude Code.
  .gitattributes   Lets git merge index.md and log.md from two people without a conflict.
  links.md         Shared wikis this one can fall back to.
  patterns.md      Recurring feedback, tallied toward a fix.
  repos.md         Repositories this wiki covers, when more than one.
  raw/             Immutable sources.
  wiki/            Compiled pages.
  data/            Structured data (CSV, SQLite).
hooks/pre-commit   The secret scan that init --git and upgrade install in wiki repos.
hooks/hooks.json   The plugin's session hook, which runs hooks/session-start.sh.
commands/          The plugin's slash commands: status, save, compile, standup.
.claude-plugin/    The plugin manifest, and the marketplace that lists it.
skills/llm-wiki/   The Claude skill that finds, runs, and scaffolds wikis. Ships with the plugin.
```

Once in use, a wiki also holds `index.md` (one line per page) and `log.md` (the change record).

The script only does file work. It never overwrites a file. The one time it touches a remote is in `setup`: it adds the remote you name and test-pushes with `--dry-run`, which sends nothing. Run `./wiki.sh` with no arguments for the command list. Set `WIKIS_DIR` to keep wikis somewhere other than `~/wikis`.

## Install the Claude Code plugin

This repo is also a Claude Code plugin marketplace. In Claude Code:

```
/plugin marketplace add broxgit/llm-wiki
/plugin install llm-wiki@llm-wiki
```

Restart Claude Code. Updates arrive with `/plugin update llm-wiki`, or on their own if auto-update is on for the marketplace. The plugin brings:

- **A session hook.** At every session start, and again after `/clear` or compaction, it finds the wiki that covers the repository the session works in, the same way `./wiki.sh which` does, and loads that wiki's handbook and index into the session. It also says how many notes are waiting and whether the handbook is behind. The agent can't skip it, unlike a line in `CLAUDE.md`. Outside any repository, or for a repository with no wiki yet, it loads the shared wiki.
- **The skill**, so there's no zip to upload.
- **Commands:**
  - `/llm-wiki:status`: what needs attention across your wikis.
  - `/llm-wiki:save [focus]`: save what this session established into the right wikis, then compile.
  - `/llm-wiki:compile [wiki]`: compile waiting notes now.
  - `/llm-wiki:standup [options]`: your standup, with the same options as `./wiki.sh standup`.
- **Its own copy of `wiki.sh` and the template.** Sessions use it, so a plugin update also updates the handbook that `upgrade` installs.

You still need a collection: run `./wiki.sh setup` from a clone once per machine. If you added the wiki line to `~/.claude/CLAUDE.md` before, delete it. The hook does its job, and both would load the handbook twice.

Other agents, and the Claude desktop and web apps, don't run Claude Code plugins. Use the line from [Use it in every new session](#use-it-in-every-new-session) there. For the Claude apps, zip the `skills/llm-wiki` folder with the folder at the zip root and add it under Customize > Skills.
