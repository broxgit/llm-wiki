# Using it

Once it's set up, you mostly just work. The agent checks the wiki, saves what matters, and keeps the pages tidy without being asked. This page covers what it does, what you can ask for, and the extras.

Commands are written as `wiki <command>`. From a clone without the link, that's `./wiki.sh <command>`.

## What to say

| Say | What happens |
|---|---|
| Nothing | The agent checks the wiki before answering, and saves decisions and findings at stopping points. |
| "Save this" | Saves what you just pointed at as a note now. |
| "Save this session" | Saves everything this session established. Plugin: `/llm-wiki:save`. |
| "Ingest" or "compile" | Turns waiting notes into pages now. Plugin: `/llm-wiki:compile`. |
| "Lint" | Health check: broken links, stale pages, duplicates, open questions. |
| "Don't save that", "off the record" | Leaves that one thing out. |
| "Leave the wiki alone" | No wiki writes until you say otherwise. |
| "What did I do yesterday?", "Give me my standup" | A standup from your commits, journal and notes. Plugin: `/llm-wiki:standup`. |
| "Seed a wiki from this repo's docs" | Starts the repository's wiki from its README, `docs/` and decision records, so it isn't empty on day one. See [Start a wiki from a repository's docs](#start-a-wiki-from-a-repositorys-docs). |
| "Backfill my journal" | Fills in past days from earlier sessions. See [Fill in past days](#fill-in-past-days). |
| "That belongs in the billing-api wiki" | Moves knowledge to the wiki that owns it, after asking. |

## What the agent does on its own

- **Query.** It checks the wikis before answering anything they might cover.
- **Capture.** It saves a note when the conversation produces a decision, direction from you, an established or corrected fact, a solved problem, or a research finding. It doesn't log finished work, since the code and git history already hold that. It captures at stopping points, about one or two notes an hour in a long session.
- **Compile.** It turns waiting notes into wiki pages at session start, at a pause, and whenever five are waiting.
- **Lint.** It runs a health check once 10 compiles have passed since the last one.

It tells you briefly what it wrote. It asks before resolving a contradiction or merging, deleting, or restructuring pages. If it doubts a fact you gave it, it files the fact, marks it with a `Check` line, and says so.

**Stale knowledge.** Each page records when its claims were last confirmed and, for claims about code, the commit. Before the agent writes code or publishes something that depends on a page, it checks the page against the code or the cited source, when that's at hand, and files a correction if the page is wrong. When it answers from a page more than 90 days old that it couldn't check, it says when the page was last verified. `wiki stale` lists those pages.

## Where things live

```
~/wikis/                 Your collection: one git repo for every wiki.
  global/                The shared wiki: tooling, conventions, glossary.
  billing-api/           One wiki per project, named after its repository.
    raw/                 Notes and sources as captured. Never edited.
    wiki/                The compiled pages.
    index.md             One line per page. Sessions read this first.
  journal/               Your work journal. Stays on this machine.
  delegation.md          Your handoff preferences. Stays on this machine.
```

Every wiki is plain markdown. Read pages in any editor, on GitHub, or in Obsidian.

## Many repositories

The goal: a session working in repository A that needs a client from repository D finds what any earlier session learned about that client.

- **One wiki per project, found by repository name.** The wiki for a repository is named after it, the last part of its remote URL, so the wiki for a dependency is found by name, with no search and no configuration.
- **Knowledge lives with its owner.** What a session learns about D's client goes in D's wiki, even when the session is working in A. A's wiki keeps only what's specific to how A uses it, and cites D's page.
- **Look before reading source.** When work touches another repository, the agent reads that repository's wiki index before answering from its code.
- **Wikis appear on demand.** The first session with something to file about a repository creates its wiki.
- **Unknown owner.** The agent searches the indexes by keyword. `wiki find <word>` does the same for you.
- **Shared knowledge.** Anything that holds beyond one project goes in the shared wiki: how you want agents to work, how shared libraries, internal tools and vendors behave, pipelines and environments, team practice, guild decisions. Before saving anything, the agent asks whether another repository would need it. Every session reads the shared wiki's index at its start, so what's there gets used.
- **Working agreements.** The shared wiki's `wiki/conventions.md` has a `For agents` section: how you want agents to work with you in every repository, such as when to commit, how to write, and when to ask. Every session reads it at its start. Corrections you repeat land there.
- **The wiki, not the agent's memory.** Some agents keep notes of their own, per project folder, which no other repository sees. The handbook tells them to save to the wiki instead, and [`wiki harvest`](#bring-in-claude-codes-own-memory) brings in what they saved before.

Keep work and personal knowledge in separate collections. Set `WIKIS_DIR` to use a second one.

### A repository whose folder name differs from its wiki

Sessions find a wiki by the repository's name. When a repository belongs to a project wiki under another name, say a `history` repo whose work lives in the `cloud-dvr` wiki, tell the tools once:

```
wiki cover cloud-dvr history
```

When no wiki covers a repository, `wiki which` suggests wikis with a similar name and prints this command.

### One project, several repositories

Some repositories are really one product: one piece of work touches several, and the same facts matter to all of them. Give those one wiki:

```
wiki new my-product
wiki cover my-product repo-one repo-two repo-three
```

A session in any of them then uses `my-product`. The test: if one session routinely works across the repositories, they are one wiki. If each is worked on alone and they only call each other, keep them separate.

## Project procedures and tools

Each project can say how work there gets done and what it needs, in its wiki's `wiki/conventions.md`:

```
## For agents

- Run pnpm check before calling a change done.
- After a push, check CI with gh pr checks and fix what fails.

## Tools

- gh (cli): PR status and CI after a push.
- supabase (mcp): the production database. Read-only unless asked.
```

`wiki start` prints both at every session start, after the shared wiki's, so every agent follows the same definition of done, not just the one whose app happens to remind it. It marks each `cli` tool installed or not. It can't see an agent's MCP servers, so the agent checks those, and tells you when the work needs one it doesn't have, instead of skipping the step. Sessions add lines as they learn them. To begin, tell a session in the project "record this project's procedures and tools".

`wiki setup tools` then offers, one tool at a time, to let Claude Code and Antigravity run the listed command-line tools without asking.

## Work and personal collections

One collection, `~/wikis`, is enough for most people. To keep work wikis apart from personal ones, each with its own git remote and its own shared wiki, add a second collection:

```
wiki setup collections
```

It asks for a name, a folder (`~/wikis-work`, say), and rules that pick which repositories go there. A rule starting with `~` or `/` matches a repository's folder, such as `~/dev/work/*`. Any other rule matches its remote URL, such as `*gitlab.com:acme/*`. The list lives in `~/.config/llm-wiki/collections`, one line per collection:

```
work  ~/wikis-work  *gitlab.com:acme/*,~/dev/work/*
```

From then on, `wiki` commands, `wiki start`, the Claude Code hook and the Antigravity plugin use the collection for the repository you're in. Anything that matches no rule stays in `~/wikis`. `wiki collections` lists them, `--collection NAME` picks one by name for any command, and `wiki status` mentions notes waiting in the others. Setting `WIKIS_DIR` still overrides all of it.

Setup doesn't move existing wikis. To move one, move its folder into the other collection and commit in both.

## Stop repeating yourself

When you correct the agent, paste review comments on code it wrote, or watch it do the same steps again, it notes that. Once the same thing has come up a few times, it asks one question with the evidence and offers a fix:

- **The same review comment keeps coming back.** It becomes a line on the project's conventions page, and agents check code against it before calling the work done.
- **You keep correcting how a shared library is used.** The rule goes in that library's wiki, so every repository that calls the library gets it.
- **The same procedure in different repositories** becomes a [team skill](#team-skills).
- **The same mechanical steps over and over** become a small script.

A pattern is ready after 3 sightings, or 2 when they are review comments or come from different repositories. A "no" is remembered. `wiki patterns` shows what every wiki is tracking.

Paste merge request comments into the session that wrote the code. They are the best evidence there is.

## Bring in Claude Code's own memory

Claude Code keeps notes of its own: corrections, working rules, project facts. It saves them per project folder, so a rule saved while working in one repository never reaches another, or a teammate. `wiki harvest` copies them into the wikis:

```
wiki harvest --dry-run    # where each note would go
wiki harvest
```

Notes about you, and corrections, go to the shared wiki, headed for its `For agents` conventions. Project facts go to the wiki of the project they were saved in. Notes from a folder with no known project go to the shared wiki, and the next compile files them where they belong. Each wiki gets a note saying where every copy came from. Your Claude Code memory is never edited or deleted, and running it again copies only what's new or changed. A tip mentions it when there's memory to bring in.

## Team skills

A skill that comes out of a repeated procedure lives in the wiki that owns it, as `skills/<name>/SKILL.md`: the shared wiki for skills that apply everywhere, a project's wiki for that project's. Everyone who syncs the collection gets it, and a fix reaches everyone. The skill holds the steps and points at wiki pages for the facts, so a corrected page corrects the skill. Each wiki's index lists its skills, so agents without skills can follow them as how-tos.

Claude Code looks for skills in `~/.claude/skills`. `wiki skills link` links every team skill there. The plugin does it at every session start, and `upgrade` and `setup` do it too, so new ones show up without you doing anything. `wiki skills` lists them. A skill of yours with the same name is left alone and shown as a clash.

To share a skill you already have, move its folder from `~/.claude/skills` into `~/wikis/global/skills/`, or a project wiki's `skills/`, then run `wiki skills link`. It's linked back where it was, and everyone else gets it on their next pull.

## Hand work to cheaper models

A session on your most capable model doesn't need to spend it on a test run or a sweep across 200 files. Sessions hand that kind of work to sub-agents on cheaper models, check what comes back, and keep design, debugging and review for themselves. This needs an agent that can run sub-agents on a chosen model, such as Claude Code.

Your preferences live in `~/wikis/delegation.md`:

- **mode:** `off` never hands off unless you ask. `ask`, the default, suggests each handoff and waits for a yes. `auto` hands off and tells you after.
- **Who does what:** kinds of work, each with a model and effort. Rows marked `stay` never leave the session. Edit it to match the models you use.
- **Auto:** kinds of work you've approved without asking. After you say yes to the same kind three times, the session offers to add it.

`wiki setup delegation` sets the mode. `wiki delegation` shows how often each kind of handoff came back fine, needed fixing, or was redone.

## Work journal and standups

Ask "what did I do yesterday?" or "give me my standup", and the agent answers from what you actually did:

- **Your commits** in every repository under your code folders, matched to each repository's `user.email`.
- **Journal entries.** One line the agent writes at a stopping point for work that leaves no commit: an investigation, a review, a dead end, a deploy.
- **Wiki notes and changes** in the range.
- **Work in progress:** uncommitted files, unpushed commits, open branches. These become "Today".
- **Open `Check` and `Conflict` lines** in the wikis. These become "Blockers".

`wiki standup` gathers that material. The agent writes it up as a standup, a summary by project, or a detailed report.

```
wiki standup                      # last workday through now
wiki standup --since week --format summary --exclude 'personal-*'
wiki standup --day 2026-10-21 --only 'billing-*'
```

The journal is personal. It sits beside the wikis, not in one, and isn't committed unless you set `commit` to `yes`. Add a line yourself with `wiki journal note <project> "what you did"`.

### Fill in past days

The journal starts empty, but Claude Code keeps a transcript of every session, and Antigravity keeps one of every Gemini conversation.

```
wiki journal backfill --since 14d
```

This writes a short digest, `~/wikis/journal/backfill.md`, per day and project, from both: what you asked for, which files changed, how it ended. It needs `python3`. Then tell an agent "backfill my journal". It writes entries from the digest and deletes it.

### Journal settings

Settings live in `~/wikis/journal/config`. Walk through them with `wiki setup journal`, change one with `wiki journal set <key> <value>`, and see them with `wiki journal`.

| Setting | Default | What it does |
|---|---|---|
| `enabled` | `yes` | Turns the whole feature on or off. Also `wiki journal on` and `off`. |
| `commit` | `no` | `yes` commits and pushes journal files with the wikis. `no` keeps them on this machine. |
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
| `max_commits` | `15` | Commits listed per repository in a report, newest first. `0` lists them all. Detailed reports always list them all. |

## Settings

`wiki setup` walks through every setting. Rerun it any time. It shows what you have and changes only what you change.

- `wiki setup --list` prints every setting and marks the ones still at their default.
- `wiki setup --new` asks only about what's new since you last ran it.
- `wiki setup plugin`, `wiki setup git`, `wiki setup journal` or `wiki setup delegation` reruns one section.
- `wiki setup format` edits one journal setting.

## Start a wiki from a repository's docs

A new wiki is empty, so for its first few days it can't answer much. Most repositories already explain themselves, so start the wiki from that:

```
wiki seed ~/dev/billing-api
```

It copies the repository's README, its agent instructions (`CLAUDE.md`, `AGENTS.md`, Cursor and Copilot rules), its Claude skills, top-level guides like `ARCHITECTURE.md` and `CONTRIBUTING.md`, its `docs/` folder, and decision records into the wiki's `raw/`, with a note saying where they came from. It takes only files git tracks, skips changelogs, licenses and dependencies, leaves out anything over 100KB, and stops at 20 documents. The next session in that repository compiles them as one batch: it reads them together and writes each page once. With more than ten waiting, it does what you asked first and compiles at the next pause. Say "compile" to have it done now. Run it without a path inside the repository. `--dry-run` shows what it would copy, `--max N` changes the limit, and running it again copies only what's new.

With the plugin, a session in a repository that has no wiki offers to do this.

The copies are the repository's docs as written, which can be out of date. The agent treats their claims about code as unchecked until it checks them against the code.

## Is it paying off?

Each time a session checks a wiki for a question, it logs whether the pages helped: a hit or a miss. The log stays on your machine.

```
wiki stats           # the last 30 days
wiki stats week
```

A wiki with a low hit rate is missing pages for the questions you actually ask, or covers a repository you rarely need help with.

## Weekly report

Once a week, Claude offers a short report on the wikis, at a stopping point. Ask for it any time with "give me my wiki report", or run `wiki report` to see the raw material.

- **Tokens:** what Claude Code spent per project over the week, from its own session records, and roughly how much of that went into reading the wikis. The wiki share is an estimate, from the size of what sessions read. With Antigravity installed, Gemini's conversations get a table of their own, by the project their file paths point at. It isn't added to Claude's, since the two count tokens differently.
- **What the wikis gained:** notes captured, notes compiled, pages created and updated, skills added.
- **Lookups:** how often each wiki answered the questions it was checked for.
- **Needs you:** what's waiting on a person. Open contradictions, proposed fixes nobody has answered, a pile of notes waiting to be compiled, pages unchecked for 90 days, and tips you muted. The report leads with this when there's anything in it.

`wiki report --since lastweek`, or any range `standup` takes, changes the period. A week with a report offer gets no tip, so there's only one nudge.

## Tips

Some features only help once you know they exist. When something in your own wikis suggests one would help, Claude mentions it, at most once a session and only at a stopping point. For example: a repository you're working in has docs but no wiki, a skill of yours lives only on this machine, or the journal has entries but you've never asked for a standup.

- A tip rests for two weeks after it's shown.
- Say "don't suggest that again", and Claude mutes it for good. `wiki tips --mute <name>` does the same, and `--unmute` brings it back.
- Once you've used the feature, its tip stops.
- `wiki tips` lists every tip that applies right now, with its evidence. `wiki status` says when there are any.

Tips come from the plugin's session hook, so other agents don't show them on their own. Run `wiki tips` now and then instead.

## Tab completion

Press Tab after `wiki` to fill in commands, wiki names, journal settings and their values, tip names, and folders for `wiki seed`. `wiki setup` offers to turn it on for zsh or bash: it adds one line to `~/.zshrc` or `~/.bashrc` that loads a small file in `~/.config/llm-wiki/`. Setup rewrites that file each time, and the candidates come from `wiki` itself, so updates never leave completion stale. Rerun the step alone with `wiki setup completion`.

## Living with your other tools

- **Markdown lint hooks.** If a hook checks every markdown file Claude writes, exclude `~/wikis/*/raw/*`. Notes in `raw/` are kept as captured and never edited, so a hook that flags one pushes the agent to break that rule. Pages under `wiki/` can stay linted.
- **"Only commit when I ask."** The handbook commits and pushes the wikis on its own, so add an exception for `~/wikis` to that rule, in your `CLAUDE.md` or the shared wiki's `For agents` conventions.
- **Commit-message conventions.** Wiki commits start with the wiki's name, such as `billing: ingest 3 notes`. If a skill or hook wants a ticket number first, tell it to skip `~/wikis`.
- **Reply style.** Reports and standups follow your own reply style when you have one, such as no headers or short replies.

## Several sessions at once

Safe. Saving a note adds one new file and touches nothing else, so any number of sessions can save at once. Compiling changes shared files, so a lock keeps it to one session per wiki. A session that finds the lock held skips compiling and carries on.

## All commands

Run `wiki` with no arguments for the full list. The ones you're likely to use:

| Command | What it does |
|---|---|
| `wiki status` | Every wiki: notes waiting, lock, handbook version, what's due. |
| `wiki start` | Session start in one call: the wiki for this folder, a pull, the indexes, `For agents`, and what waits. Agents run it; you can too. |
| `wiki find <word>` | Search every wiki's index, then page text. |
| `wiki collections` | The wiki collections on this machine and the repositories each one takes. `--collection NAME` picks one for any command. |
| `wiki deps [--all] [--write]` | Which repository owns which package, and which of your repositories use each other's, from `go.mod`, `package.json` and `pyproject.toml`. `--write` saves it to the shared wiki's `data/dependencies.csv`. |
| `wiki stale [days]` | Pages not verified in that many days, 90 by default, or 50 commits behind their repository. |
| `wiki patterns` | Recurring feedback, and which patterns are ready. |
| `wiki standup` | Raw material for a standup. |
| `wiki upgrade --all` | Bring every wiki's handbook up to the template's. |
| `wiki new <name>` | Create a wiki. Usually the agent does this. |
| `wiki cover <wiki> <repo>...` | One wiki for several repositories. |
| `wiki unlock <name>` | Free a stuck compile lock. |
| `wiki capture <wiki> <slug>` | Save a note piped in, named from the clock. Mostly for agents. |
| `wiki lock`, `wiki log`, `wiki sync` | The compile lock, a log entry, and commit-pull-push for one wiki. Mostly for agents. |
| `wiki index <wiki>` | Bring `index.md` in step with the pages' titles and summaries, keeping its order and headings. |
| `wiki lint <wiki>`, `--all` | The mechanical health checks: broken links and citations, index gaps, frontmatter, size, stale pages, waiting notes. Changes nothing. |
| `wiki seed [<repo>]` | Start a wiki from a repository's own docs. |
| `wiki harvest` | Copy Claude Code's own memory notes into the wikis. |
| `wiki pending [<wiki>]` | Notes waiting to be compiled. |
| `wiki skills [link]` | List team skills, or link them for Claude Code. |
| `wiki tips` | Features your own wikis suggest you'd get something out of. |
| `wiki completion zsh\|bash` | Tab completion for your shell. `wiki setup` turns it on. |
| `wiki report` | The weekly report: tokens, what the wikis gained, lookups, and what needs you. |
| `wiki stats [range]` | How often each wiki answered the questions it was checked for. |
