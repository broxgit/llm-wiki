# Roadmap

Potential improvements to the wiki template, in rough order of payoff. Work from the top of Next. When an item is finished, move it to Done with the date and what changed.

Each item says why it matters, a sketch of how, and what is still undecided.

## Next

### Port wiki.sh to Go, one command at a time

- **Why:** see the first step under Done. The aim is one binary that needs no Bash 3.2 workarounds and no Python.
- **Sketch:** the MCP server is in the helper, and still runs `wiki.sh` for `start`, `status` and `sync`, which are most of what `wiki.sh` is. `capture` and `feedback add` are in the helper. The table of `status` is in the helper now; the rest of `status` reads the machine's setup and stays Bash. `start` and `sync` stay in Bash, decided on 2026-11-09 after reading both. `start` launches the background compile and the helper fetch by running `wiki.sh`, so a Go `start` would still need it, and the rest of it is the machine's setup that the `status` port left in Bash: the collection rules, matched as shell patterns, the tips file, the feedback reminder, the `command -v` checks and the compile lock. Porting only its read-only middle would change nothing for the server. `sync` commits through the secret-scan hook, which is Bash, and calls `index` and the lock. Neither would be faster: the remote is most of their time. To get to one binary, port what they lean on first: the launcher of `compile`, the lock, `index` and the hook. Small and separate: `chat_state`, `chat_write` and `mcp --print` still need `python3`, so `wiki setup chat` does too. `find` is ported as it was: index lines, then one line from each of five pages, in the order of their paths. Ranked section results would be new, so they are a change of their own. Still Bash in routing: choosing the collection (`collection_for`, which runs at the top of every command, the core ones included), `wiki_root`, `repo_map` and the `links.md` lookups. Each port prints what the old code prints, checked by the smoke tests, and adds nothing.
- **Open:** whether the desktop app's Chat tab itself runs the helper's server as it ran the Python one: the smoke tests and the Claude CLI can't show that. And when the ported commands may drop their old Bash and Python. The helper now reaches people through `wiki update`, but that has to prove itself first. The core commands (`start`, `capture`, `lock`, `sync`, `index`) stay in Bash until then, so a session can never break over a missing binary.

### Extensions: integrations outside wiki.sh

- **Why:** Obsidian, Jira, Confluence, CI and git hosting are each optional, and each one built into `wiki.sh` is code every user carries. Teams also want to add their own. Decided on 2026-11-10: integrations become extensions, home-grown ones are supported as far as they can be, and the features stay agent-agnostic, with a thin layer for each agent.
- **Sketch:** everything the first two extensions needed is done (see Done): the command seam, events, a sign-in they share, and a wiki's content as data. Next: CI (Jenkins, GitLab CI and GitHub Actions as separate extensions over one shared prompt), and moving `wiki obsidian` out. A third extension written by someone else would be the real test of the contract.
- **Open:** how a team shares extensions. They are per machine on purpose, so a pull can't add a command. A shared collection could carry them behind a step that asks each person once, on each machine, whether to trust each one. Where extensions that ship with llm-wiki live, and whether `wiki update` installs them. How an extension adds a handbook rule without `wiki upgrade` dropping it, and what that costs in context. Whether the helper needs to know about extensions at all.

### Learn where a person works, by asking

- **Why:** llm-wiki assumed a session belongs to one repository. Most of one team starts sessions in a folder for a ticket, which holds clones, and for weeks their project wikis never loaded and nothing said so. Decided on 2026-11-11: never guess silently; ask when unsure; write what is learned into the person's own wiki, so the questions get rarer.
- **Sketch:** steps 1 and 2 are done (see Done): a folder of clones uses their wikis, and patterns remember the answer. Next, ticket folders: the ticket's key, from the folder's name, in every capture, so the Jira extension can close their open items, and where the ticket stands at session start. Then `wiki setup` asks how you work, and writes the first pattern.
- **Open:** how many wikis to read in full when a folder's clones belong to many. Where a ticket's own state goes: the maintainer said "both, maybe", the repo's wiki and the personal journal. Whether a git repository that holds clones is placed as a folder of clones is: a teammate asked on 2026-11-12 about checking her ticket folder into git, and the "home repo" pattern (one repository you always start in, with the others cloned inside it and ignored) has the same shape. Today such a folder is a repository like any other, so the wikis of the clones inside aren't used. Whether a wiki's `repos.md` should say more than a name for each repository: what it is, where it lives on this machine and where to clone it from, so a session in a ticket folder can find or fetch a repository the ticket needs and the folder lacks. Seen on a real ticket the same day. A clone two folders down isn't seen, and two different repositories with one name share a wiki: both found in the first hand test on real ticket folders, neither decided.

### Know whether sessions capture and compile

- **Why:** `wiki stats` measures lookups only. Saving and compiling are the parts that failed in the first week (50 of 109 notes never compiled), and nothing measures them now.
- **Sketch:** `wiki status` flags a wiki whose repository has commits in the last two weeks but no new notes in that time.
- **Open:** wait for two weeks of `wiki stats` first. It may not be needed.

## Later

- **Find repeated work in transcripts.** Scan the transcripts on disk (`~/.claude/projects`, Antigravity's) for command sequences repeated across sessions, and report them as candidate toil. Look at this only if handbook v32 still misses repeats.
- **Merge requests in standups.** Reviews and MRs opened live in GitHub or GitLab, not in git history. Pulling them in would need an API token and a host per remote.
- **Backfill from more places.** The desktop app's Chat tab and claude.ai aren't on disk, so they're out of reach without an agent that has chat search. (The desktop Code tab is in `~/.claude/projects`, and Gemini's Antigravity conversations are read since 2026-10-29.)
- **A hosted MCP server,** so web agents can search everything and save notes. A claude.ai Project covers reading for now. Build this only if saving notes from the web keeps coming up: it puts private notes behind a public URL, so it needs sign-in and a security review first.
- **Team digest.** A weekly roll-up across several people's journals, for a lead. Needs a shared, opt-in journal location.
- **Review flow for teams.** Agents push straight to the collection. A team may want a weekly digest of changes, or pull requests.
- **Microsoft 365 Copilot through gitlab.com.** Parked on 2026-11-03; the code is on the `microsoft-copilot-gitlab` branch. It worked once, signed in as an account in a paid company group, but GitLab's server follows the signed-in account, so the agent could read everything that account can. A dedicated Reporter account should fix that, but a free one, owning its own free group with MCP access on, gets a 403: "MCP server not enabled for any of your groups". Revive this if GitLab explains that denial, or if an account in a group that counts can be limited to one project. Until then, the GitHub route is the way: code can stay on GitLab, with only the wikis the agent reads on GitHub.
- **Terse page style.** Held on 2026-11-02. Measured on one sample page, terse plain-word notes used 56% of the tokens of default prose, but wiki reads were about 1.9% of a week's new input tokens, so the saving is under 1%. It would mean rewriting every page or keeping two styles, and teammates read the pages too. If token savings become a goal, look at long sessions first: most of the volume is cache reads. If it ever comes back, test answer quality first, and skip abbreviations and JSON, which saved nothing more in the same test.

## Untested

Things that have never been run for real. Treat them as unproven until crossed off.

- `wiki tour` with a person, or with any agent but Claude. Whether its chapters land, and how long they take, is a guess until then.
- `wiki.sh unlock` and `claude` on macOS. `setup` and `journal backfill` have since run on Macs in real use (2026-10-28 and 2026-10-29); every other command ran cleanly on macOS (bash 3.2, BSD `date`) on 2026-10-28.
- `wiki.sh journal backfill` on transcripts from Claude Code versions other than the one it was written against. It needs `python3`.
- Git sync between two people or two machines. Pull, commit, and push from one machine worked in real use on 2026-10-01.
- Two sessions taking the compile lock in the same second.
- The released helper in real use. The fetch has run against a folder standing in for GitHub, and the build matched the lock from two folders on one Mac. Since then CI on Linux has built the same bytes as the Mac that wrote the lock, and a real download verified (2026-11-05). In Antigravity's sandbox, which blocks the network, the fetch failed with one clear line and the commands fell back (Gemini, 2026-11-05). Unknown: whether a work Mac's security tooling lets a downloaded, linker-signed binary run.
- Reminders in real use. A headless session on a throwaway wiki was stopped once by a `before` reminder, retried, and got an `on` reminder as context. Unknown: whether real sessions act on them or route around them, how many a wiki can hold before they turn into noise, whether one refusal per rule per session annoys more than it helps, and what the hook costs across a long session. Claude Code and, since 2026-11-07, Gemini in Antigravity run them; no other agent does. Not seen yet: Antigravity itself running its hook (see Done).
- Background compile in real use. One real run so far. Unknown: whether a cheaper model's pages are as good as a session's, whether a run started from the session hook survives the hook ending in every agent, how it behaves inside Codex's and Cursor's sandboxes, and any agent other than `claude`. From Antigravity it can't run: that shell's PATH has no `~/.local/bin`, and with `claude` named by its full path the sandbox refuses to execute it ("Operation not permitted"), as well as blocking the network and `~/.local/state/llm-wiki`. `wiki start` says which of the two it is and leaves the notes to the session (Gemini, 2026-11-05 and 2026-11-06). Runs recorded before 2026-11-06 counted a note captured mid-run as left waiting, so a `partial` from then may have been a whole run. After a week, read `wiki compile` and some of the pages it wrote. If it holds, the handbook can stop telling sessions to compile, which is the larger gain.
- A wiki with two shared wikis listed in `links.md`.
- Real scale: hundreds of wikis, hundreds of pages. Real use so far is 10 wikis and 53 pages.
- The version 8 triggers in real use. They passed a dry run only.
- Agents other than Claude pulling at session start, and syncing. Gemini in Antigravity and Codex pull through their plugins' hooks; Codex's and Cursor's sandboxes block writes to `~/wikis/.git`, so `wiki sync` there, and Cursor's `wiki start`, run outside the sandbox. Copilot is still untried.
- Delegation in real use: whether sessions suggest handoffs at the right size, and whether the log shows real savings. The log records outcomes, not tokens. Token counts per handoff would need the tool's usage data.
- Stats in real use: what page-open counts mean a wiki should go. Sessions don't log lookups reliably, so hit rate can't answer that.
- Seed in real use: how long compiling 20 seeded documents takes, and whether the pages are worth it.
- `scripts/migrate-to-plugin.sh` and the interactive parts of `wiki setup` in CI. Both ran by hand in fake homes on 2026-10-28; CI only shellchecks the script. Testing them needs a pseudo-terminal that works on Linux and macOS runners.
- The plugin's data folder name. Docs hard-code `~/.claude/plugins/data/llm-wiki-llm-wiki`, seen on three machines. A fork under another marketplace name gets a different folder.
- Sessions upgrading wikis on their own (plugin, 2026-10-28): whether they pull before upgrading, and two machines upgrading one shared collection at once.
- Tips in real use: whether people act on them or mute them all. Look at the mutes after a few weeks and drop the tips everyone mutes. Usage before 2026-10-28 wasn't recorded, so early standup and find tips may point at features already used.
- Bulk compile in real use: how long twenty seeded documents take, and whether planning by topic gives better pages than one at a time. No agent has run it yet.
- The weekly report in real use: whether people ask for it, and whether the token estimate for wiki reads is close enough to be useful.
- Shared knowledge in real use: whether sessions now file general lessons in the shared wiki, and whether they stop saving to their own memory. The weekly report's correction count is the first signal. Whether harvested notes get filed in the right wiki at compile.
- Capture after compaction in real use: whether sessions capture before answering when the user's message arrives with the hook's message. On 2026-10-28 one session answered first and captured a turn late, which led to the "before you answer anything" wording. Watch for raw notes timed just after a compaction.
- Cursor's own sessionStart hook (`wiki setup cursor`) in a live session without the Claude Code plugin: whether Cursor runs it outside its sandbox, so the pull works.
- Codex's PostCompact hook in a live session. The smoke tests cover its reply; no Codex session has compacted with it yet.
- Feedback in real use: whether agents keep notes unprompted, whether they pick real llm-wiki problems over their own mistakes, and whether the scrubbing misses private names in practice. Read the first filed issues closely.
- The MCP server in the desktop app's Chat tab itself. On 2026-11-01, Codex used it end to end, and the Claude CLI on its cheapest model, with no other tools or settings, called `wiki_start` for a plain question and captured a decision without being asked. The Chat tab itself did not: asked plainly, it answered from memory and past chats (handbook v12), even after the server's instructions said the wikis come first. Told to use the tools, it found the right rule and cited the page. So setup now gives a line for the user's profile preferences, and with it a plain question went to the wikis (one test, 2026-11-01). Whether it holds across other subjects, and whether Chats capture without being asked.
- The GitHub route beyond one test: how a Project answers a question its files don't cover, how much of a collection fits, a whole repository added to a plain chat, and other web agents' GitHub connectors.
- Microsoft 365 Copilot beyond a few runs (2026-11-03; real wikis on the user's work Mac): an answer inside the Mac app, a question spanning several wikis, and a toolkit newer than the pinned version. Whether reading one index really fixes the first question: two chats passed, and the cap on tool calls per turn is a guess. `--update` ran live once; whether GitHub keeps the sign-in after it wasn't reported.
- Patterns in real use: whether agents write `Feedback:` lines unprompted, and whether the thresholds are right.
- The Read and handoff hooks in a real Claude Code or Antigravity session (handbook v29): that `Read` reaches the plugin's hook with the path in `file_path`, that `start_session` arrives as an `mcp__*start_session` tool, and that Antigravity's `read_file` carries `Path` or `AbsolutePath`. Only JSON fed by the smoke test has been seen.

## Decided against

- **Embeddings or a vector database.** Lookup by repository name plus keyword search covers the need. Embeddings also tie the data to one embedding model.
- **A custom UI.** Obsidian and GitHub already render markdown.
- **More scaffolding automation.** Setup is one command.

## Done

### One look for every command (2026-11-13)

- **Why:** decided on 2026-11-13: the timeline look picked for `relay mr` (a question, stages on a rail, items, a card to paste, YOUR TURN and its steps) is the house style of llm-wiki, llm-relay and any llm tool after them, so no command looks plainer than the others.
- **What changed:** conventions version 4 names the pieces and the colour roles, and `ui.sh`, kit version 4, draws them: one file each tool carries byte for byte, held to the guide by its sha256. 24-bit colour where the terminal says so, a colour-blind palette and a light theme (`wiki setup palette`, `wiki setup theme`). Every command a person reads in both tools prints through the pieces; `tests/ui-lint.sh` fails on anything that doesn't, and `scripts/gallery.sh` keeps what each prints. llm-relay says "Copilot Cowork" wherever a person reads it. The work went on a long-lived `ui-house-style` branch in each repository, merged to `main` once, so nobody saw a half-moved look.
- **Untested:** how the 24-bit colours and the light theme look in terminals other than the tests'; auto can't tell a light background in macOS's Terminal, which sets no `COLORFGBG`.

### Patterns: a session outside a repository asks once where it belongs (2026-11-11)

- **Why:** the second step of "Learn where a person works, by asking" under Next. Step 1 said which wikis a session in a folder of clones used, and remembered nothing, so the same folder was placed, and would have been asked about, every time. The maintainer's answers on 2026-11-11: a good guess asks once; a pattern seen again is used, and the session says so at the start with a way to say it is wrong; with no pattern, ask whether to use llm-wiki there at all, then about the layout, then whether to remember it.
- **What changed:** patterns are lines of a fixed shape in `workflows.md` at the root of the shared wiki: a full path that may hold wildcards, and one of "the wikis of the repositories inside", a wiki's name, or "no wiki". `place_all` in `wiki.sh` reads them for a folder outside a repository, and both `wiki start` and the Claude Code session hook use it. The first line that fits wins, a `*` stops at a slash, and a path with no wildcard is written ahead of the patterns. A match is named in the session's opening text. No match adds the question to ask and the exact command that records the answer, with a pattern offered: a folder named like a ticket, `INFRA-17937`, gets one for its siblings. A no-wiki pattern makes `wiki start` print `wiki: none` and the hook say only that llm-wiki isn't used. `wiki workflows` lists, adds, changes, removes and tries patterns. Handbook version 34 adds `rules/workflows.md` and one row in `AGENTS.md`.
- **Still untested:** all of it in a real session: whether an agent asks in its first reply, proposes a sensible pattern, and records it. Whether "ask once" feels like once when the user declines to have it remembered, since the next session asks again. Antigravity, Codex and Cursor. A pattern that names a second or third wiki: one line gives one wiki.

### A session in a folder of clones uses their wikis, and says so (2026-11-11)

- **Why:** the first step of "Learn where a person works, by asking" under Next. A session started in a folder that was no repository got the shared wiki, and only the agent was told. One person worked that way for weeks without her project wikis loading, and found out by guessing.
- **What changed:** `place` in `wiki.sh` looks one level down, at 30 folders at most, for git repositories, and maps each to its wiki. `wiki start` and the Claude Code session hook both use it, the hook through a hidden `__place`, so the two can't disagree. Where the clones have wikis, the first is the session's and the others are printed too, three in full at most and any more by name; a clone with no wiki is named, with how to make one; two clones one wiki covers load it once. Every such session is told which wikis are in use and why, and to tell the user in one line, with how to say it is wrong. A folder with no repository in it gets the shared wiki, says so, and the agent asks whether llm-wiki should be used for that work. Inside a repository nothing changes, and nothing is read into the home folder, the collection's own or the temporary folder, where a hook or the MCP server lands with no folder to go on. `wiki which`, which the compiled helper also answers, is untouched.
- **Still untested:** in a real session, whether the agent passes the line on and asks. Antigravity, Codex and Cursor, which reach it through `wiki start`. Reminders come from the first wiki only. Nothing is remembered yet, so the same folder is placed again every time.

### Extensions: Confluence watches pages (2026-11-11)

- **Why:** the Confluence extension only published a wiki outward. The maintainer had expected the opposite: watch Confluence pages and tell the agent, as Jira does for tickets. He found out at setup's prompt for a space to publish into, which read as if his wikis were about to be published. The question a team asks first is what happened elsewhere, which is information coming in.
- **What changed:** watching is the extension's main job, and it reads only. `watch.<wiki>` names pages by address or id, or a whole space as `space:KEY`. `wiki confluence check` says what changed since the wiki last heard, and `--save` notes it: a page read for the first time with its text, a page whose text changed with who, when and a diff, and a page whose status changed. With pages named, the tick event does that once a day. An open item whose heading has a page's address closes when the page's status is in `done_states`, Verified by default. The version last noted for each page is a line in the wiki's own notes, so machines agree; the text a diff is made against is kept on each machine, and a machine without it notes the full text. A space is watched from the moment it is named, by a search for pages modified since, asked a day early and narrowed here, since the search reads dates in the account's time zone. Publishing is unchanged and still off unless chosen.
- **What changed in setup:** both extensions' setups open by saying what the extension does, explain each choice before asking it, and end with "What is set" and "What happens now". Confluence's is three numbered steps: sign in, watch, publish. Each page is checked as it is named, with its title and status or why it was left out. It lists the statuses the site offers before asking which mean finished. Publishing is one yes or no, and a no says nothing of yours goes to Confluence. Jira's asks for `done_statuses` too.
- **Found on the way:** a second note saved in the same second is named `<stamp>-<slug>-2.md`, and neither extension recognised it as its own, so Jira could have noted an item twice. Both now do.
- **Checked on a real Confluence Cloud site, read only:** a page's version, author and date; that a page with no status answers `{}`; the statuses a space offers (Rough draft, In progress, Ready for review, Verified); and the search for pages modified since a date.
- **Still untested:** a page that has a status, on a real site: the name is read from `contentState.name`, which is from memory of the API and was not seen. Watching a real page through a real change. A space with more than 100 changed pages. Data Center, which has no page status.

### Conventions version 2 (2026-11-11)

- **Why:** llm-relay adopted version 1 and came back with three things the guide didn't settle: what a usage error exits with, whether `--yes` is owed, and warnings on standard error that took their style from standard output, so `2>errors.log` at a terminal put colour codes in the file.
- **What changed in the guide:** exit 2 is "called wrongly": an unknown command or option, or a missing argument. The flag names are for when a tool has such a flag, and a tool may have no `--yes` where the question is the safeguard, as llm-relay's `run`, `review`, `apply` and `answer` have none. The helper block gains `die_usage`, `say_warn_err` and `typed_err`, the last two styled by standard error; the Python block gains the same. One line names llm-relay's way of keeping agents' output plain: `style_off` whenever standard input isn't a terminal.
- **What changed in llm-wiki:** `wiki.sh` exits 2 at 57 places that are usage errors, through `die_usage`, and the Jira and Confluence extensions do for theirs. `capture`, `feedback add` and a flag given no value still exit 1: the compiled helper answers those too and exits 1 for any refusal, and the two must match. Nothing in `wiki.sh` warns on standard error with a mark yet, so the new helpers are there for llm-relay and for later.
- **Next:** the llm-relay session copies version 2 and its helper block in its own pull request, once this is merged.

### Extensions: on, not set up, and silent (2026-11-11)

- **Why:** the maintainer updated his work Mac, answered yes to both extensions in `wiki setup --new`, and nothing told him to write a settings file. Setup's only pointer was half a line beside his answer, `wiki status` had no line for an extension that was on with no sign-in, and `wiki jira` with no settings said no open item named a ticket. Each command had been tested, and the path of someone turning an extension on never had. He asked for it fixed and for a check that there were no other gaps like it.
- **What changed, the contract's version 3:** an extension with a `wiki-setup:` comment answers `--wiki-ready` (exit 0, or one line saying what is missing) and `--wiki-setup` (its own questions, at the terminal). `wiki setup` runs the setup right after a yes, `wiki extensions setup <name>` runs it again, `wiki status` and `wiki extensions` list one that isn't ready with that command, and no event runs it until it is. The answer is kept beside the extension's logs; status asks again only those that weren't ready. The program an extension's first line names is checked for every extension, so one in Python on a machine without `python3` says so, with "Do: install python3", when run, in status, and where setup would offer it.
- **What changed, Jira and Confluence:** each has a guided setup. The shared part asks for the site and email, writes `~/.config/llm-wiki/atlassian`, says where to make a token and gives the clipboard command for the keychain, and never asks for the token. Then it tests the sign-in and says who it signed in as. Jira asks for its projects and whether to close items by itself; Confluence asks for its own address where the site isn't Atlassian Cloud, the space, and the wikis to publish by themselves, after saying who can read a space. With no sign-in, each command now fails with `isn't set up: <what>. Run: wiki extensions setup <name>`.
- **What an independent audit found, and what was done:** a second agent on a cheaper model walked the new-user paths against stand-in servers and reported fourteen findings, all reproduced. Fixed: a mistyped address counted as "offline" for ever, so a tick put off is now tried again after half an hour and three in a row is a To do line; an address that answers but isn't Jira made every ticket "unknown" and the run "ok", and now fails saying so; on a server of one's own, Confluence's error said to set the site that was already set; a wiki in `auto` that isn't there stopped the wikis after it; a taken title was printed as "created", was missed by the dry run, and had no fix; `wiki extensions tick` exited 0 when a run failed; `projects` hid tickets without saying; a misspelled event, or a comment below line ten, was never run and never said why; an unknown command printed the whole usage with no line naming the word; "is not a wiki" had no next step; and commands about an extension that is off didn't say how to turn it on. The docs' own example extension exited 0 on a usage error.
- **Left as they are, on purpose:** an item `auto_close` noted as done stays in `wiki open` until a compile runs, and `wiki status` has no line for fewer than five waiting notes; the docs now say plainly that a compile closes it. `wiki obsidian --no-open` ends without a next step, because setup, its caller, prints one. `wiki extensions` and its sub-commands are still unstyled: three commands were chosen for style. `wiki update --wikis-only` ending with a note when nothing changed was seen once and not understood.
- **Still untested:** the guided setup at a real terminal, with a real keychain and a real Atlassian site. Everything ran with answers on standard input against the stand-in servers.

### Terminal style for `wiki setup` and `wiki update` (2026-11-11)

- **Why:** `docs/conventions.md` was applied to `wiki status` first. Brock decided llm-wiki restyles three commands and stops: these two are the other ones.
- **What changed:** `section()` prints its heading bold, keeping the `== `. In `setup`, a line the step itself prints and that says something was written, turned on, added or already in place has the green tick after any indent; a failure, or something the person must do, has the bold yellow `!` with its command in cyan. `setup --list` has `<- new` in yellow, `(default)` dim and the command lines in cyan. `update` puts the tick or the `!` where its `- ` was, bolds its `== ` headings and a NEWS entry's title line, and prints the rest of an entry as written. Prompts keep their words, and the bracketed default isn't dimmed, since it says what Enter does. The helper block, the Go helper and every other command are as they were, and `upgrade`'s session note is still plain.
- **Still untested:** how it renders in a real terminal. Left plain: lines that come from another command through a pipe (what `init`, `scaffold`, `install_hook`, `cmd_obsidian` and the like print, indented by setup, and what `upgrade --all` prints inside `update`), and the "Can't read" lines, which say nothing was changed and give no fix.

### Extensions: a wiki's content as data (2026-11-11)

- **Why:** each extension parsed the wiki's files itself. Jira read `open.md` with its own parser, and Confluence walked `wiki/` and read frontmatter with its own. A change to either format would have broken them without a test failing, and every later extension would have written the same parsers again.
- **What changed:** `wiki open --data [<wiki>]` prints every entry of the open items, the closed ones too, one a line, tab separated: wiki, state, kind, who, due, status, the notes it came from, heading. `wiki pages <wiki> --data` prints each page under `wiki/`: path, updated, verified, title, where the title is the frontmatter's, or the page's first line when that is a heading, or the file's name. `wiki pages <wiki>` alone lists them for a person. Both are plain whatever the terminal is. They are Bash and awk, with no Python. The Jira extension's `ledger` and the Confluence extension's `wiki_pages` now run them through `$LLM_WIKI`, and their own parsers are gone; Confluence still reads a page's text from its file. `docs/extensions.md` gives the fields as part of what an extension can rely on.
- **Still untested:** an extension by someone else reading them. A heading or a title with a tab in it has the tab turned into a space.

### Extensions: one Atlassian sign-in (2026-11-11)

- **Why:** Confluence had no sign-in of its own and read the Jira extension's settings file, which was a workaround: someone who used Confluence alone had to write a file named for Jira. Both extensions needed one place for a vendor's sign-in.
- **What changed:** `~/.config/llm-wiki/atlassian` holds `site`, `email` and `token_cmd`, and both extensions read it. For each value the first found is used: the extension's own environment variable, Atlassian's (`ATLASSIAN_SITE`, `ATLASSIAN_EMAIL`, `ATLASSIAN_API_TOKEN`), the extension's own file, the shared file. On Atlassian Cloud, Confluence's address is the site's with `/wiki` after it; for any other site it is not guessed, and `url` goes in Confluence's own file. Confluence still reads the Jira extension's file last, so nobody's setup breaks. `config` in each names the shared file and says where the address, the email and the token came from. No change to `wiki.sh`: the two extensions each carry the same few functions.
- **Still untested:** the shared file on a real site, since the maintainer's settings are in Jira's own file, which still works. Data Center, where the two addresses differ.

### One terminal style: the conventions guide and `wiki status` (2026-11-11)

- **Why:** llm-relay 0.2.18 gave four commands colour and marks, and the two tools should look and behave alike, governed by one written guide.
- **What changed:** `docs/conventions.md`, version 1: when style is on, the vocabulary, what never gets style, layout, the conventions beyond style (fixes, errors, exit codes 0, 1 and 75, flags, program output, voice), and the helpers in Bash and Python. `wiki.sh` has the helpers, `LLM_WIKI_STYLE=on|off`, `+` where the locale isn't UTF-8, a red `error:`, and `style_off` for every command an agent reads. `wiki status` is the first command restyled: its words are unchanged. A smoke test keeps the helper block the same as the guide's. The compiled helper is untouched and still prints plain text.
- **Still untested:** how it renders in a real terminal, on a light theme, and in Windows Terminal. `setup`, `update` and the rest are next, then the copy in llm-relay.

### Extensions: how often the tick comes (2026-11-11)

- **Why:** the tick came once in 24 hours for every extension, with no setting. For someone working through a chain of releases, a ticket that finished in the morning closed its item the next day. And one interval doesn't fit every extension: Jira's check is cheap, while Confluence's catch-up reads every page of each wiki it publishes.
- **What changed:** `wiki extensions every <time>` sets how long passes between ticks on this machine, as a number and a unit, `90m`, `4h`, `2d` or `3w`, from five minutes to 52 weeks. `wiki extensions every <name> <time>` gives one extension its own, which wins over the one for all, and `every <name> default` takes it away. `wiki extensions every` lists both. They are kept as typed in `~/.config/llm-wiki/extensions-tick`, as `every=` and `every.<name>=`. 24h is still the default. `wiki setup` asks once for the one for all, when an extension that is on runs on tick; `setup --list` and `wiki extensions` show both. `LLM_WIKI_TICK_MINUTES` still overrides them, for the smoke tests.
- **Still untested:** in real use.

### Extensions: what a Jira ticket's state means (2026-11-11)

- **Why:** the extension knew done from not done and nothing else. Jira's done group holds Won't Do, Duplicate and Cancelled too, so an item waiting on a ticket that was dropped was recorded as done, as if the work had happened. And a blocked prerequisite, which changes what to work on today, was never mentioned.
- **What changed:** a ticket is done, abandoned, blocked or open. Abandoned is Jira's done group with a resolution or status that says the work didn't happen. Blocked is a status with "block" in its name, or the Flagged field, whose id is looked up once per run. `check --close` notes only what changes a decision. All tickets done: `Done:` for the item. Abandoned: the item stays open, and `Waiting: user | Jira: <KEY> was closed as <resolution>, and "<item>" still waits on it`. Blocked: `Waiting: <who> | Jira: <KEY> is blocked, holding up "<item>"`, once, and a `Done:` for that item when the ticket is no longer blocked. An item this extension closed in the last 60 days whose ticket is no longer done: `Waiting:` with its own heading, which opens it again. A move between in development, in testing and the like notes nothing. What has been noted is the wiki's own state, the open items and the notes `wiki pending` lists, so two machines agree and nothing is kept per machine. `done_statuses` names the statuses that count as done where the grouping doesn't fit. The note's file is still `*-jira-done.md`.
- **Tried on a real Jira Cloud site, read only:** the Flagged field was found, and a closed ticket's resolution was read and counted as done.
- **Still untested:** an abandoned, a blocked and a reopened ticket on a real site, and what a compile makes of the `Waiting:` lines. Whether "block" in a status name fits real workflows.

### Extensions: Jira and Confluence act on events (2026-11-11)

- **Why:** events existed and no extension used them, so someone still had to run `wiki jira check --close` or `wiki confluence publish`.
- **What changed:** the Jira extension asks for `tick`. With `auto_close = yes` in its settings it runs `check --close` once a day in the background, so a finished ticket becomes a `Done:` note and the next compile closes the item. The Confluence extension asks for `sync` and `tick`. With `auto = <wikis>` it publishes a named wiki when a sync changed `index.md` or a path under `wiki/`, and on `tick` it publishes each named wiki again to catch up, which costs a read for each unchanged page. Both settings are off by default and are per machine. During an event, a site that can't be reached exits 75, "not now", and so does a publish whose only problems were version clashes; a refused sign-in is a failure that `wiki status` lists. `config` in each shows whether auto is on.
- **Still untested:** either one through a real session start, where the run has to outlive the session hook. Confluence auto-publish on a real site. Two machines with the same wiki in `auto`. A keychain `token_cmd` from a background run started by an agent, which may not be allowed to read the keychain.

### Extensions: events (2026-11-11)

- **Why:** an extension saved tokens only when someone asked for it, and asking is a session's turn. Token reduction is a main goal, and it is why the extensions were kept over an agent's own connectors: a job a command can do should cost no model at all.
- **What changed:** the contract's version 2. An extension names events in a `wiki-events:` comment and is run in the background as `wiki-<name> --wiki-event <event> [wiki]`. `sync` follows a `wiki sync` that left the wiki's files different, with the changed paths in the file `LLM_WIKI_CHANGED` names. `tick` comes from `wiki start`, at most once in 24 hours for each extension. Output goes to a log under `~/.local/state/llm-wiki/extensions/<name>/`, and how the run ended to a status file: exit 0 is done, 75 is "not now" and says nothing, anything else is a failure that `wiki status` lists with `wiki extensions log <name>` as its fix. One run at a time for each extension and wiki, with a later sync's paths kept for the next; five minutes at most; a sync made inside an event starts none. `wiki extensions tick` runs the tick now, for cron, and `wiki extensions` shows what each one runs on. `cmd_sync` is now a wrapper round `sync_do`, and lets go of the collection's sync lock before starting anything.
- **Why two events:** a capture through the MCP server is saved by the helper and never passes through `wiki.sh`, while every saved note ends in a sync, so `sync` sees them all. A compile ends in a sync too, and the changed paths say whether pages changed. Status reads the status files itself, so no extension runs when someone asks for status.
- **Still untested:** a real agent's session start launching a tick, and whether that run outlives the session hook in each agent, which is the same open question as background compile. Inside an agent's sandbox. Two machines running the same extension for one wiki. No shipped extension uses events yet.

### Extensions: Confluence, the second one (2026-11-10)

- **Why:** a team has people who read in Confluence and use neither git nor Obsidian. The wiki's pages should reach them without anyone copying text.
- **What changed:** `extensions/wiki-confluence`, Python with the standard library only. `wiki confluence publish <wiki>` makes the wiki's index a page called `<wiki> wiki` and each page under `wiki/` a child of it, titled `<wiki>: <title>` since Confluence allows one title per space (two pages with one title get their path added). It converts markdown to Confluence's storage format itself: headings, paragraphs, nested lists, fenced code as the code macro, tables, block quotes, rules, inline code, emphasis, links and remote images. A link to another page of the wiki becomes a link to that page's title; a link to a raw note or a file keeps only its text. Each page it makes carries the label `llm-wiki` and a hash of its title and body in the version comment, so an unchanged page isn't written, and a page without the label is never overwritten. A taken title is reported, the rest are published, and the command exits 1. A page gone from the wiki is reported and left. `--dry-run` writes nothing; `render` prints one file's markup; `config` tests the sign-in. Settings: `space`, `parent`, and `space.<wiki>` and `parent.<wiki>`; `url`, `email` and `token_cmd` fall back to the Jira extension's file.
- **What Confluence needed that the seam didn't give:** the same as Jira, and the Next item has the list. Also a markdown converter, which belongs to this extension alone.
- **Checked:** all 673 pages and indexes of the maintainer's real wikis render as well-formed markup.
- **Tried on a real Confluence Cloud site (2026-11-10), in a personal space, with a scratch wiki of three pages:** the first publish created the index page under the space's home and the two pages under it, each with the label and its hash in the first version's comment. A second publish wrote nothing. After one page changed, a third publish wrote only that page, as version 2. Read back, the stored markup kept the info note, the code macro and its language, the table, the nested list, the block quote, the strike-through, the link to the other page by title, and the outside link. The sign-in came from the Jira extension's settings.
- **Still untested:** Confluence Data Center; how the pages look to a reader, which nobody has checked by eye; a title taken by someone else's page and a page gone from the wiki, on a real site; a wiki of several hundred pages; and a space with restrictions. It uses `/rest/api/content`, which Atlassian marks deprecated on Cloud since 2023 and still serves; Data Center has no other. Images in the wiki aren't uploaded, and pages aren't nested by folder.

### Extensions: Jira, the first one (2026-11-10)

- **Why:** an open item such as "waiting on the release of PROJ-123" stayed open until someone told an agent the ticket was done. A teammate asked what llm-wiki relies on to know something was released: only being told.
- **What changed:** `extensions/wiki-jira`, Python with the standard library only. `wiki jira` reads each wiki's `open.md`, finds open entries whose heading names a ticket, and prints each ticket's status from Jira's REST API (`/rest/api/2`, the same on Cloud and Data Center). `check --close` captures a note with a `Done:` line for each entry whose tickets are all done, and syncs; an entry already noted and not yet compiled isn't noted again. `show` and `config` print a ticket and the settings. It never writes to Jira. The sign-in is email and API token for Cloud, or a bearer token for Data Center, and the token comes from `JIRA_API_TOKEN` or a `token_cmd`, never the settings file. To ship it, `wiki.sh` gained extensions that come with llm-wiki in `extensions/`, off until `wiki extensions add <name>` (a list on each machine), with a setup question for each new one and a row in `setup --list`. A file of the user's own with the same name wins.
- **What Jira needed that the seam didn't give:** a way to ship and be turned on (added). Its own settings file, since there is no shared place for an extension's settings and `setup --list` doesn't show them. The open items as data: it reads `open.md` itself, because `wiki open` prints for people. A moment to run without being asked, such as session start, so an agent hears a ticket is done: not built, and for now a line in a wiki's conventions tells agents to run it. And a way to close an entry at once: a `Done:` note takes effect only at the next compile.
- **Tried on a real Jira Cloud site (2026-11-10):** the sign-in with an email and a classic API token read from the macOS keychain by `token_cmd`; `show` on a closed ticket, one in development and a key that doesn't exist; `check` and `check --close` on a scratch wiki naming those tickets, with words like UTF-8 and SHA-256 skipped. Two things it turned up: the first sign-in failed because `security`'s own prompt had kept only 128 characters of a 192-character token, so the docs say to store it from the clipboard, and the refusal now prints after the settings it refers to.
- **Still untested:** Jira Data Center, a scoped API token (those need Atlassian's gateway address, which isn't supported), a ticket the account may not see, `check --close` on a wiki with a remote, and an agent acting on the conventions line.

### Extensions: the command seam (2026-11-10)

- **Why:** the first step of "Extensions" under Next. It is the cheapest seam and commits to the least.
- **What changed:** `wiki <name>` runs an executable named `wiki-<name>` from `~/.local/share/llm-wiki/extensions` (`LLM_WIKI_EXTENSIONS_DIR` names another folder), with its arguments as typed and its exit code passed on. It is given `LLM_WIKI`, a path to run the wiki command by, `WIKIS_DIR`, the collection the call is for, and `LLM_WIKI_EXTENSION`, the contract's version, 1. A command of `wiki.sh`'s own always wins, the hidden ones and `relay` included. `wiki extensions` lists them with the `wiki-extension:` comment as a description, and says why one is ignored: a built-in's name, a name that isn't lowercase letters, digits and dashes, or a file that isn't executable. Tab completion offers them. `docs/extensions.md` is the contract. Bash only: the helper doesn't dispatch commands.
- **Still untested:** an extension written by anyone else, one in a compiled language, and the plugin's stable `wiki` command running one.

### Browse the wikis in Obsidian (2026-11-10)

- **Why:** the wikis are plain markdown, and Obsidian gives search, links and a graph over them. Opened as a vault with Obsidian's defaults, though, the collection's `git status` is never clean, links come out as `[[wikilinks]]` that lint can't follow, pasted files land outside any wiki, and editing a property rewrites `sources: [a, b]` one item a line, which lint and the waiting-notes count read as no sources at all.
- **What changed:** `wiki obsidian` writes starter settings for one vault over the collection (names checked against Obsidian 1.12.7's own code) and opens it once Obsidian knows the folder. `.obsidian/` and `.trash/` are ignored in new collections and added by `wiki upgrade`. Lint, `compiled_stems` and the helper's `internal/status` read a list with one item a line. Lint reports wikilinks. Handbook v33 keeps lint from giving frontmatter to a note the user made. `wiki setup` asks once where Obsidian has run.
- **Tested in a real vault (Obsidian 1.12.7, 2026-11-10, a copy of two wikis):** opening the folder keeps the starter settings; removing a tag in the properties panel rewrote every list in the frontmatter one item a line, indented two spaces, and lint and pending read the page as before; the graph showed about as many nodes as there are pages outside `raw/` (142, against 262 raw notes); `wiki obsidian` opened the vault once Obsidian listed it.
- **Also tried there:** a link picked from Obsidian's `[[` suggestions was written as `[go-port-status](decisions/go-port-status.md)`; a note made with a page open landed in that page's folder; a pasted image landed in `attachments/` beside the note. Lint reported the new note as having no frontmatter, missing from the index and an orphan, and nothing else.
- **Still untested:** `wiki obsidian` on Linux, and the setup question in a real terminal.

### Repeated operational work gets counted (2026-11-10)

- **Why:** `rules/patterns.md` turns repeated work into a script or a skill at three sightings, and for repeated work it almost never fired: across every wiki there were no `toil` entries and two `procedure` entries, each seen once. llm-relay had been released by hand 14 times with nothing recorded. A line was written only when the agent knew the job had been done before, which a new session never does, and "work the user asks for as routine" read as exempting every release.
- **What changed:** handbook v32 records an operational job from its first run, names the line after the job so sightings add up, counts each separate request, and has lint drop a job seen once and not again for 180 days. The plugin's tool-call hook gives a built-in reminder, once a session, on a command that looks like a release or a deploy (`builtin_reminders` in `wiki.sh` lists them).
- **Still untested:** whether agents now record these jobs. About a week after release, run `wiki patterns` and count the `toil` and `procedure` entries, looking for noise (coding tasks logged as jobs) and split counts (one job under two wordings). Fewer than two operational entries across the wikis means the wording didn't work.

### The Go port: wiki feedback add (2026-11-09)

- **Why:** the second of the commands the helper's MCP server still ran `wiki.sh` for.
- **What changed:** `internal/feedback` and the helper's `feedback-add` keep a note, or count one with the same summary as seen again, as `feedback_add` did. `wiki.sh` passes the folder, the mode file and the lines a note carries about the machine, and `cmd_mcp` passes the same to the helper's server, which keeps notes itself. The old code is `feedback_note`, now under `LC_ALL=C` and with a quiet `mkdir`. Protocol 14.
- **Still untested:** the port in real use.

### The Go port: wiki capture (2026-11-09)

- **Why:** the helper's MCP server still ran `wiki.sh` for every note it saved, and `capture` is the smallest of the commands left, so it is the first port that writes. Speed isn't the reason: `capture` in Bash takes about a tenth of a second.
- **What changed:** `internal/capture` and the helper's `capture` save a note, or a copy of a file, as `cmd_capture` did, and say the same, refusals included. The helper's first line says which answer follows, since the note is on stdin and a refusal sent as a failure would leave the Bash nothing to read. The helper's MCP server saves through the package. The old code is now `capture_note`, and makes the slug under `LC_ALL=C`. Protocol 13.
- **Still untested:** the port in real use. The smoke test runs each case through both and compares what they print and the file they leave.

### Handbook v29: sessions record what they lost (2026-11-09)

- **Why:** the handbook's by-hand logging mostly didn't happen, and some knowledge had nowhere to go. In the week to 2026-11-09 the report found 9 logged lookups against 25 page reads in the transcripts, no handoff logged of seven sessions and three subagents, and what waited on the user lived only in a conversation. The rule: a hook where a hook can see the event, a line in a note where it can't, and no new step done from memory. Agreed with the user on 2026-11-09. Two halves, one handbook version.
- **What changed, the notes:** `Verified:` lines in a capture, stamped at compile. `Waiting:`, `Due:` and `Done:` lines, tallied by compile into each wiki's `open.md` (`template/open.md`, `rules/open.md`), listed by the new `wiki open` (`open_ledger`, `cmd_open`), counted in `wiki status`, and checked by lint. A `lesson` kind for `Feedback:`. Captures for changes git doesn't record, and a place for deferred work. `AGENTS.md` grew by four lines.
- **What changed, the hooks:** `hooks/pre-tool-use.sh` now also matches `Read`. A read of a `.md` page under `<collection>/<wiki>/wiki/` appends `date,wiki,hit` to that collection's `stats.csv`, once per wiki per session (`<session id>.reads` beside the reminders), and a handoff (`Agent`, `Task`, a `start_session` tool) appends a `started` row to `delegation-log.csv`. Both are in `hooks/reminders.py`, which Antigravity's hook runs too, for `read_file` and `view_file`. The wrapper starts Python only for a read whose path has `/wiki/` and ends `.md`, for a handoff, or when the session has reminders. Step 6 of Query is gone. `wiki delegation` has an OPEN column and says what a `started` row is.
- **Still untested:** whether agents write the `Verified:`, `Waiting:` and `Due:` lines unprompted, and whether compile matches a `Done:` to the right entry (a `Done:` matches an open entry whose heading contains its text, ignoring case). The count in `wiki status` is Bash, not the helper. Nobody has watched the hooks run in a real Claude Code or Antigravity session: the smoke test drives them with JSON, and what Claude Code sends for `start_session` (the tool is a `mcp__ccd_session__` one) and what Antigravity sends for a read is as documented or seen once. A session whose reads go through a shell command or the MCP tools isn't caught by the Read hook (the MCP server logs its own). A page the agent reads is logged, whether or not it answered, so every logged lookup is a hit.
- **Open:** whether to drop hit and miss from `wiki stats` and the tip that reads them. Whether Gemini's `invoke_subagent` should log a handoff too. Decided against: recording what a lookup saved, which would be a guess about a path not taken; counting approvals, since nothing follows from the count; and a registry of the sessions at work in a repository.

### The report splits wiki use into lookups and upkeep (2026-11-09)

- **Why:** `wiki report` gave one figure, "Wiki reads", and it left out the MCP tools, which pass relative paths, so sessions using them weren't counted. One number also mixed looking things up with keeping the wikis up to date.
- **What changed:** each tool call that touches the wikis is a lookup or upkeep (`wiki_kind` in both Pythons, `classify` in `internal/tokens/class.go`): `wiki_read`, `wiki_search`, `wiki_start` and `wiki_list` are lookups, `wiki_capture`, `wiki_status` and `wiki_feedback` upkeep; a path call is upkeep for the edit tools and a lookup otherwise; a command is upkeep when any wiki subcommand in it is outside `find`, `start`, `which`, `news`, `tips`, `patterns`, `stats`, `report`, `standup` and `help`. The Wiki reads column is the total of both, and each table ends with the two shares. Protocol 12.
- **Still untested:** the rule on a transcript with the wiki tools in Antigravity, and `wiki.sh` named as a file argument (`grep x wiki.sh docs/a.md`), which reads as a subcommand and counts as upkeep.

### Reminders for Gemini in Antigravity (2026-11-07)

- **Why:** reminders ran only in Claude Code. Antigravity documents a hook before each tool call.
- **What changed:** `wiki setup antigravity` (and the next conversation's `__agy-start`) adds a `PreToolUse` and a `PreInvocation` hook to the plugin's `hooks.json`, and copies `hooks/agy-hook.sh` and `hooks/reminders.py` into the plugin's `hooks/` folder, so wiki.sh's 40 ms start isn't paid per call and a plugin update can't leave the hooks pointing at a folder that is gone. `__agy-start` writes the conversation's rows to `reminders/agy-<id>.tsv`. `reminders.py --antigravity` reads Gemini's tool names as Claude's (`run_command` as Bash, the file-edit tools as Edit, `invoke_subagent` as Agent) and keeps the matching. A `before` reminder returns `deny` once. Antigravity's `PreToolUse` reply has no context field, so an `on` reminder is queued in `agy-<id>.pending` and handed over by the `PreInvocation` hook as a system message, once; a queue over a day old is dropped. Every path prints an explicit reply and exits 0, since exit codes are undocumented. Each run adds a line to `agy-hooks.log`. Smoke tests cover each reply and path.
- **Still untested:** Antigravity itself running it. Unknown: whether a plugin's `hooks.json` takes `PreToolUse` and `PreInvocation` (the docs describe only the global file), whether the hooks run outside the terminal sandbox as the `SessionStart` hook does, whether `PreInvocation` follows the tool result, and whether Gemini acts on the reminders. `.local-work/gemini-tests/nov-7-2026-reminders/` tells the three failures apart.

### The Go port: the table of wiki status (2026-11-07)

- **Why:** `wiki status` was the slowest thing the Chat tab's MCP server does, about 0.8 to 0.9 seconds on the maintainer's Mac with 14 wikis, and `wiki_status` runs it in both servers. Timing its parts on a copy of the real collection put about 430 ms in the table, a row for each wiki, and the rest in reading the machine's setup: about 160 for the setup steps, 95 for the tips, 50 for Python reads of Claude's plugin files and 28 for the secret scan's hook.
- **What changed:** the helper's `status` makes the table, the to-do lines its rows give, and the count of notes waiting in each other collection, and `cmd_status` prints them and does the rest as before. Its answer is a first line `status` and one tagged line for each thing, taken only whole; otherwise `status_table`, the old loop, makes the table. Everything after the table stays Bash: it reads setup that only `wiki.sh` knows, and new setup steps and tips would otherwise be written twice. `status_table` now runs under `LC_ALL=C`. Two things change for users: in a UTF-8 terminal, wikis whose names differ only in case sort capitals first, as the desktop app already showed them, and a file that isn't UTF-8 no longer stops `status` partway on macOS with no message, which it did when `sed` met a Latin-1 byte in a handbook. What the helper isn't sure of stays with the Bash: anything it can't read, a NUL byte, a link under `wiki/`, a name with a line break, a wiki with no `log.md`, and dates in `patterns.md` that awk might compare as numbers. Measured as medians of 15 on the copy: `wiki status` 737 ms before and 411 after with the desktop app's environment, 809 and 375 in a UTF-8 terminal; `wiki_status` through the helper's MCP server, start to reply, 806 and 461, and 833 and 413. The helper's part takes 19 ms. Both ways printed the same stdout, stderr and exit code on the copy in five locales, and on Linux (GNU sed and grep, mawk, bash 5.2) on the copy and on a fixture with every kind of row. Found and left alone: a wiki with no `log.md` still ends `status` with exit 2 and no message, as it did before.

### The Go port: the MCP server (2026-11-06)

- **Why:** it is the one part of llm-wiki that runs for as long as a chat does, and it needed `python3` beside `wiki.sh`. Speed was not the reason, and the gain is small: on the maintainer's Mac, with 19 wikis and 627 pages, the Python server started in 41 ms and searched in 40 with the helper's `find` behind it, and nobody feels 30 ms in a chat.
- **What changed:** `internal/mcp` and the helper's `mcp` serve the protocol, and `wiki mcp` starts them when `go_helper` finds a helper, and `mcp/server.py` as before when it doesn't. The choice is made once: a server that is up can't fall back, so the helper's answers every line whatever it holds, and writes nothing but replies to stdout. The desktop app's config is unchanged, `wiki.sh` with `mcp`. For the same requests both servers give the same replies, compared as JSON, and leave the same files. `wiki_list` and `wiki_read` are Go, and `wiki_search` uses `internal/find` with no `wiki.sh`, writing the search's line in `stats.csv` and `used:find` in the tips file itself, once. `wiki_start` finds the collection through `internal/routing`. Still `wiki.sh`, run as the Python runs it: `start`, `status`, `capture`, `sync` and `feedback add`, and `find` or `which` where the Go isn't sure, such as a link under `wiki/`. Three of Python's habits had to be copied for the replies to match: it gives its children `LC_CTYPE=C.UTF-8` when no locale is set, which `wiki mcp` now sets for the helper; it reads bytes that aren't UTF-8 as one U+FFFD for each broken character; and it reads `\r` as a line end. On purpose the helper's server differs where the Python trips: a line that isn't UTF-8 is a parse error and not the end of the server, which it was when the server was started from a UTF-8 terminal; `NaN` is a parse error; and a wrong type in the arguments is an error that names the argument. `mcp/server.py` now reads a `repos.md` that isn't UTF-8, where `wiki_list` failed. One thing changed in `wiki.sh` outside the server: `stats_log` cuts the logged word at 60 bytes and never inside a character, under `LC_ALL=C`. It used `cut -c`, which counts characters on macOS and bytes on Linux, so a second writer could not have matched it on both. Measured as medians: start to first reply 41 ms before and 25 after, a search for "the" 40 and 2, a word found nowhere 41 and 5, `wiki_start` with a repository 179 and 143. `wiki_status`, at 920 ms, is `wiki.sh` either way. The Claude CLI, pointed at each server over a scratch collection, made the handshake and three tool calls and got the same six replies from both. Not tested: the desktop app's Chat tab itself.

### The Go port: wiki find (2026-11-06)

- **Why:** it is the next step toward the MCP server, whose search runs `wiki find` once for each collection, and it was the slowest lookup a session makes: 120 to 250 ms on the maintainer's Mac, with 19 wikis and 626 pages, most of it one `grep -r` and up to five `awk`, `sed` and `cut` for every wiki.
- **What changed:** `internal/find` and the helper's `find` do the search, and print what the Bash prints: for each folder with an `index.md`, the index lines that mention the word, then up to five pages whose text mentions it and whose index line doesn't, each with its first line outside the frontmatter. The helper's first line says how the search went, `found <wiki>` or `none`, and `cmd_find` logs it to `stats.csv` as it always has, so a search is logged once whichever answers. The old search is now `find_search`, and runs under `LC_ALL=C`: the order of wikis and pages, which letters match whatever their case, and where a page's line is cut no longer depend on the locale. A shell with no `LANG`, such as the desktop app's, already printed that, and ended a line inside a character when the 120th byte fell in one. Both now cut at 120 bytes and then drop a character the cut left unfinished, so what `find` prints of UTF-8 pages is UTF-8 everywhere. That mattered more than it looked: the MCP server reads `find` through Python as text, and a broken character there failed the whole search. `mcp/server.py` now also reads with `errors="replace"`, so no output of `wiki.sh` can end a call. In a UTF-8 terminal two things change: an accented letter matches only in its own case, and a line with such letters is cut a few characters sooner, at 120 bytes, not 120 characters. What the helper isn't sure of stays with the Bash: anything it can't read, a word with a backslash or a line break, a file with a NUL byte, and a link under `wiki/`. Measured as the median of 30 runs: a word in 236 lines of results 250 ms before and 39 after, and a word found nowhere 120 and 41. The helper and the Bash printed the same for 61 real words on a copy of the maintainer's wikis, every output valid UTF-8, and the smoke test compares them on Linux too. Ranked section results, which this item used to name, are not what `find` prints and were left out: a port adds nothing.

### The Go port: wiki which (2026-11-06)

- **Why:** routing, working out which wiki covers a repository, is what `find` and the MCP server build on, and none of it was in Go. Speed was not the reason: `wiki which` took 35 to 110 ms on the maintainer's Mac with 19 wikis, and about 35 of that is Bash starting up and choosing the collection.
- **What changed:** `internal/routing` and the helper's `which` answer `wiki which`, for a name or for the repository the command runs in: the wiki named after it, the one whose `repos.md` lists it, or the advice with its close matches. `wiki.sh` still chooses the collection, and `which_wiki` stays for `start`, `sync`, `new` and `cover`. A repository no wiki covers now takes about 44 ms, not 105, and one found through `repos.md` 41, not 48. One found by its own name takes 40, not 35, because asking the helper costs two processes and the Bash needed none. Both ways print the same for every case the smoke test compares: a second collection, a renamed folder matched by its remote, a wiki that lists several repositories, and folders and files that can't be read. What the helper isn't sure of stays with the Bash: anything it can't read, two wikis that list one repository, and a name with a backslash or a line break. `which_miss` now runs its `tr`, `grep` and `sort` under `LC_ALL=C`, so the order of close matches no longer depends on the locale.

### The Go port: journal backfill (2026-11-05)

- **Why:** `wiki journal backfill` took about 13 seconds for the default 14 days on the maintainer's Mac (1,160 transcripts, 2.2 GB). Timing its Python's parts showed 8 of those seconds went to 730 git calls, one after another, and 5 to reading JSON, most of it in one 282 MB transcript.
- **What changed:** the helper's `journal-backfill` takes the Python's arguments, writes the same digest through a temporary file renamed into place, and prints the same line. `journal_backfill` keeps the options, the dates and `--done`. It asks git side by side and reads a long transcript in pieces side by side. 14 days now take about 2.5 seconds, not 14, and one day about 1.2, not 5. The digest matched byte for byte for 20 runs on a frozen copy, from one day to the full history, with and without excludes. The Python now reads files in sorted order: ties between prompts in one minute, the last reply and the order of files changed used to follow the directory order. Records it might read differently or stop at, such as JSON that isn't an object, bad UTF-8 or a lone surrogate, stay with the Python. `internal/pyos` now holds the path, glob, time and git code the ports share.

### Session start fetches the helper (2026-11-05)

- **Why:** a plugin updates without anyone running `wiki update`, which left the helper a step behind and the ported commands on their slower code.
- **What changed:** the Claude Code hook and `wiki start` start a background fetch when the release a checkout names isn't on the machine. It is verified against `helper.lock` like any fetch, says nothing, and tries once in six hours, so a machine that is offline or in a sandbox doesn't try at every session. `wiki helper auto off` turns it off, and `wiki setup` asks about it once. Helper releases are now published as prereleases, so GitHub doesn't show one as the project's latest release.

### The helper reaches people who don't build it (2026-11-05)

- **Why:** each port added a second copy of a command, and its speed reached only whoever built the helper. Deleting the old copies needs the helper to be something everyone has.
- **What changed:** `helper.lock` holds, in the same commit as the source, the SHA-256 of the helper for four platforms. `scripts/helper.sh` builds them reproducibly with a pinned compiler, CI checks the lock on Linux and publishes the binaries as a release named by the source's hash, from the pull request, so it exists before the merge. `wiki update` and `wiki helper fetch` download the one for this machine and keep it only if it matches the lock. `wiki.sh` uses a helper built in the checkout, then the release its lock names, then an older release that speaks the protocol. Nothing is deleted yet.

### The relay moved to its own repository (2026-11-05)

- **Why:** one repository per tool. The relay is about Copilot Cowork and OneDrive, not wikis, and every plugin user was getting it.
- **What changed:** `scripts/relay.sh`, `cowork/` and their tests and docs moved to [llm-relay](https://github.com/broxgit/llm-relay), with their history. What was planned and untested for them moved to its roadmap. `wiki relay` and `wiki setup copilot-cowork` print where they went and exit non-zero, for one release. Remove those two stubs and their smoke tests after that.

### The Go port: the standup's body (2026-11-05)

- **Why:** `wiki standup` took about 6 seconds for a week and 20 for the full history on the maintainer's Mac. It held no Python, so the time was forks: 416 git calls run one after another, a sed and a grep per note, and a `date` per day of the range.
- **What changed:** the helper's `standup-activity` prints everything from `# Activity` to `Totals:`. `wiki.sh` keeps the options, the dates and `--save`. A week now takes about 0.7 seconds, and the full history about 0.75. It makes the same git calls, side by side. Output matched byte for byte for 20 option sets on frozen copies of the code and the wikis. `cmd_standup` now runs under `LC_ALL=C` and sorts callouts by file, so the order doesn't depend on the locale or the file system. Patterns with brackets or backslashes, and files that aren't plain text, stay with the Bash.

### The Go port: the Gemini token table (2026-11-05)

- **Why:** after the Claude table, the Gemini table was the slowest part of `wiki report`, about 2.3 of its 4.6 seconds on the maintainer's Mac.
- **What changed:** the helper's `report-tokens-gemini` prints the table `report_tokens_gemini` prints. Timing the Python on 27 conversations (28 MB) showed about 2.3 of 2.5 seconds under a profiler went to 308 git calls, again not parsing. The table now takes about 0.35 seconds, not 2.05, and printed the same bytes for every range compared on a frozen copy, from one day to the full history, with and without excludes. The Python stops at the first step it can't read, so the port returns an error on anything it isn't sure of and leaves those to the Python. Both now read files in sorted order.

### The Go port starts: the token table (2026-11-05)

- **Why:** `wiki.sh` passed the ~2,500 lines the pre-rollout decision set for considering a rewrite long ago, and leans on 29 inline Python blocks. A port also needs a first step small enough to check.
- **What changed:** `cmd/llm-wiki` and `internal/` hold an optional helper, standard library only, that `wiki.sh` uses when it's built and falls back from when it isn't. Its first command is the Claude Code token table of `wiki report`. Most of the old time went to asking git, twice per folder, for each session's project, so the helper reads transcripts and asks git several at a time. On a week of real transcripts (228 files, 1.1 GB) the table took 7.4 seconds in Python and 1.5 in Go, and printed the same bytes as the Python for every range compared on a frozen copy of the transcripts, from one day to the full history. Compared on live transcripts, two ranges differed until rerun on the copy, because a running session wrote between the two runs. A smoke test compares the two on every run where `go` is installed. `docs/maintaining.md` has the rules for a port.

### Reminders at the point of use (handbook version 28, 2026-11-05)

- **Why:** a rule shown at session start isn't in mind when it applies. On 2026-11-05 a session started a sub-session on the most expensive model, against a rule in the shared wiki whose index line it had read that morning.
- **What changed:** `## Reminders` lines in `wiki/conventions.md` say when a rule applies: `before` or `on`, then `bash`, `edit` or `tool` with a pattern. The session hook writes each session's reminders, and a new PreToolUse hook (`hooks/pre-tool-use.sh`, `hooks/reminders.py`) matches each tool call against them. `before` refuses the call once with the rule as the reason, because context added to a call arrives with its result, too late for a rule about what to do first. Each is given once a session and again after a compaction. `wiki lint` reports lines it can't read. The read tools aren't matched, to keep the hook off the busiest calls.

### Background compile, as an experiment (2026-11-05)

- **Why:** compiling is a cost the user watches at the start of a session, and it is the step that failed in the first week (50 of 109 notes never compiled). A run nobody waits for can take it.
- **What changed:** `wiki compile <wiki>` runs a headless agent on the waiting notes, with `--background` to not wait, and `wiki compile on` has `wiki start` and the session hook start one. The script takes and frees the lock and syncs; the agent only writes pages, the index and the log. Runs are recorded in `~/.local/state/llm-wiki/compile/runs.csv`. Off by default, with no setup question yet: it gets one if the experiment holds. The handbook is unchanged, so sessions still compile at a pause.

### Fixes from a second review by Gemini (2026-11-05)

- **Why:** Gemini reviewed the code again. All seven of its bugs were real, though many details weren't, and three of its other ideas were already done.
- **What changed:** `relay` and MCP `wiki_start` route by the repository, so they find a wiki in any collection. `wiki.sh` flags with no value give an error instead of a silent exit. Callouts in code fences don't count as open. The token tables follow the journal's `exclude`. `setup --list` and completion cover every section and relay's flags. The 12 process-substitution loops in `relay.sh` became heredocs, and the smoke test now scans it and `runlib.sh`. `relay.sh` runs `set -u` only, so that was for the rule, not a live abort.

### The report counts wiki use it can see (2026-11-02)

- **Why:** the report said "17 lookups, 100% answered" for a week of about 67 sessions. Sessions mostly skip logging by hand, so that number looked meaningful and wasn't.
- **What changed:** the report's Wiki use section counts sessions that opened each wiki's pages, from Claude Code and Gemini transcripts. `wiki find` logs its own searches, and the words that found nothing are listed: those are the missing pages. Hand-logged hits and misses are shown as counts, with no percentage. The handbook's logging step stays, since only a session can say whether a page helped.

### No loop fed by process substitution (2026-11-02)

- **Why:** on bash 3.2, the exit of a substituted process can interrupt a blocked `printf`, and under `set -e` that ends the script partway: `wiki start` could lose the rest of a session brief. A test of the pattern failed 10 of 40 runs with the error CI had shown, and pipes and heredocs failed none.
- **What changed:** all 16 loops take a heredoc holding `$(...)`, which finishes before the loop starts, with a guard where a blank line would count. A smoke test keeps `done < <(` out.

### Fixes from a review by Gemini (2026-11-02)

- **Why:** Gemini reviewed the code. About a third of its findings didn't match the code once checked; these did.
- **What changed:** drafted feedback issues now scrub wiki names from every collection, not just the current one. The MCP server logs Chat's lookups to `stats.csv`: reading pages counts as one hit per ten minutes per wiki, and a search that finds nothing as a miss. `upgrade --all` links team skills for Codex and Cursor too. `pending_files` makes one pass instead of a grep per note. `set_collection` keeps the journal, stats and delegation paths in step when a hook switches collection. Tab completion knows `log --source` and the newer setup sections. `.local-work` is git-ignored.

### Web agents read the wikis through GitHub (2026-11-02)

- **Why:** claude.ai can't start a local MCP server. The cheap route was worth testing before anything hosted.
- **What changed:** `docs/other-agents.md` documents a private claude.ai Project with a collection added through the GitHub Integration connector. In a test on 2026-11-02, a plain question got the right rule, its history and the file's path. It knows only the selected files, goes stale until **Sync now**, and can't save notes, so a hosted server moved to Later.

### `wiki setup chat` waits for the app to close (2026-11-01)

- **Why:** the desktop app rewrites its config while it runs, from its own copy, so an entry added meanwhile is gone within about two minutes. Setup wrote it with the app open, then said to quit and reopen.
- **What changed:** asked with the app open, setup waits until it's closed before writing. `wiki setup chat --yes` does the step with no terminal, for an agent the user told to, and refuses while the app is open. An agent's feedback note asked for that form.

### A local MCP server, for sessions with no file access (2026-11-01)

- **Why:** the desktop app's Chat tab can't read files or run commands, so it couldn't use a wiki at all.
- **What changed:** `mcp/server.py`, standard-library Python started by `wiki mcp`, offers `wiki_list`, `wiki_start`, `wiki_search`, `wiki_read`, `wiki_status`, `wiki_capture` and `wiki_feedback`. All but reading go through `wiki.sh`. Reads stay inside the wiki, refusing `..`, absolute paths, links that lead out, and hidden folders. `wiki_capture` commits and pushes; a later session with file access compiles. `wiki setup chat` adds it to the desktop app's config, keeping everything else with a backup, and `wiki mcp --print` gives the entry for other clients.

### Feedback reminders: once a day, and in the weekly report (2026-10-31)

- **Why:** with `share` on, `wiki start` told every session to remind the user about unread notes, so several sessions a day meant several reminders. The weekly report didn't mention them at all.
- **What changed:** `start` passes the reminder on at most once a day, and only for notes from an earlier day, and stays quiet for three days after the user runs `wiki feedback` in a terminal. An agent listing them doesn't count as the user looking. The weekly report's Needs you lists notes waiting, ending with how to read, file and drop them.

### Agents report problems with llm-wiki, opt-in (handbook v27, 2026-10-30)

- **Why:** only the maintainer's own sessions had a rule to report llm-wiki problems, and their notes stayed in his collection. Other users' agents hit problems too, and nothing reached anyone who could fix them.
- **What changed:** `wiki setup feedback` chooses off, notes or share. With it on, `wiki start` prints a Feedback section and `rules/feedback.md` says what's worth a note (bug, friction, docs, idea, each with evidence), at most one per session. `wiki feedback add` saves it with the agent, llm-wiki commit, handbook version and system, outside the collection; the same summary again counts as seen again. `wiki feedback show` drafts the issue with paths, emails, remotes and private names scrubbed; `send` files it on llm-wiki's repository with `gh` or a filled-in browser form, only from a terminal and after a yes. `wiki status` lists notes waiting.

### `wiki sync` with no wiki named (2026-10-30)

- **Why:** a session in another project ran `wiki.sh sync` without a wiki name and got only "error: name a wiki". It was the one failed `wiki` command in 50 Claude sessions since the problem-report rule.
- **What changed:** with no wiki named, `sync` uses the wiki the current folder is in, or the one that covers the current repository, as `start` finds it, and says which. A repository no wiki covers, or a folder outside any repository or wiki, gets an error that says what to run.

### Every call to action says how to resolve it (2026-10-30)

- **Why:** `wiki status` and `wiki report` flagged things (compile due, lint due, an open conflict) without saying what to do, and only a few lines ended with a command.
- **What changed:** `status` gathers every call to action under a To do list after the table; the table keeps its short markers. `report`'s Needs you does the same in place. Each item ends with its fix: `Run:` a terminal command, `Ask an agent:` a request with the exact words (compile, lint and conflicts need an agent), or `Do:` a manual step. A conflict names its page and what to ask. A smoke test fails any item without a fix, so new flags can't ship without one. The status command, its skill and the report's note to agents say to keep each fix.

### Standup says when it can't read a repository (2026-10-30)

- **Why:** in Antigravity's sandbox, `wiki standup` found no commits in any repository and printed only "None found.". Gemini spent five reads of `wiki.sh` working out why before rerunning it outside the sandbox.
- **What changed:** standup checks that git can read each repository before looking for commits. When some can't be read, it says how many, quotes git's first error, and suggests running outside the sandbox or allowing the code folders and `~/.gitconfig*`. When `code_dirs` holds no repositories at all, it says that too. A failing `git version` no longer stops standup.

### Slash commands as skills for other agents (2026-10-30)

- **Why:** Antigravity dropped workflows for skills, and Codex and Cursor on their own have no plugin commands, so `/llm-wiki:status`, `save`, `compile` and `standup` existed only in Claude Code.
- **What changed:** wiki.sh makes a skill from each file in `commands/` (`wiki-status`, `wiki-save`, `wiki-compile`, `wiki-standup`) in the skills folders it already keeps for Antigravity's plugin, Codex and Cursor. A command's inline `wiki.sh` output becomes an instruction to run it by a path the agent can use, and `$ARGUMENTS` becomes the user's request. A marker line in each SKILL.md means only skills made this way are refreshed or removed. They're made rather than kept in the repo, so Claude Code doesn't see each command twice.

### Cursor (2026-10-30)

- **Why:** Cursor runs the Claude Code plugin from Claude Code's own installed copy, which on a directory marketplace can sit days behind. Cursor users without Claude Code got only a pasted user rule: no pull outside the sandbox, no wiki loaded at start.
- **What changed:** `wiki status` says when an installed llm-wiki plugin copy is behind its marketplace, which both Claude Code and Cursor run. `wiki setup cursor` adds a sessionStart hook to `~/.cursor/hooks.json` that runs `wiki start` and replies with `additional_context`, prints the user-rules line, and links the skills into `~/.cursor/skills`. With the Claude Code plugin installed, the hook replies with nothing, so the brief never arrives twice. No compaction hook: Cursor has none after compaction, and its preCompact reply reaches only the person.

### Collections whose branch doesn't track the remote (2026-10-30)

- **Why:** `wiki setup git` adds `origin` but never set the branch's upstream. On a teammate's machine `wiki update` failed with "There is no tracking information for the current branch", and `wiki start` and `wiki sync` pulls fail the same way.
- **What changed:** `start`, `sync` and `update` now set the upstream to origin's branch of the same name when it's missing. When origin has no such branch yet, `start` says the next sync pushes to it, and `sync` and `update` make that first push with `-u`.

### Codex plugin (2026-10-30)

- **Why:** Codex has a plugin system and hooks in Claude Code's shape, but used only a pasted session line: no pull outside its sandbox, no wiki loaded at start, nothing after compaction.
- **What changed:** `wiki setup codex` writes a local marketplace with an llm-wiki plugin to `~/.codex/llm-wiki` and installs it. Its SessionStart hook runs `wiki start` and hands the output to the session; its PostCompact hook says to capture before answering. The hooks call the stable `wiki` command, so they don't change with updates and Codex asks to trust them only once. The rule goes in `~/.codex/AGENTS.md`, replacing the session line, and the skills are linked into `~/.codex/skills`. `setup --list` and `setup --new` know about it. Tested live on 2026-10-30: once trusted, a Codex session got the brief, the pull ran outside the sandbox, and Codex answered from the brief without running `start` again.

### Fixes from the Codex and Cursor tests (2026-10-30)

- **Why:** `docs/agent-test.md`, run by Codex and Cursor, found bugs the Gemini test hadn't.
- **What changed:** a read-only command no longer fails when it can't record its own use. Messages name the path `wiki.sh` was run by, not `./wiki.sh`, so agents copy commands that work. `wiki sync` takes a lock for the whole collection, so two sessions' syncs take turns. When a pull would overwrite uncommitted local copies of incoming files, sync sets aside the identical ones and pulls again, and stops on the rest, never resetting. `wiki start` and `sync` say when a sandbox is the likely cause of a failed pull. `wiki update` on a clone also refreshes an installed plugin's cached copy, whose hook other agents may load. `docs/agent-test.md` is the protocol; `docs/other-agents.md` covers Codex and Cursor.

### `wiki update` (2026-10-30)

- **Why:** an update took a plugin command, a pull, an upgrade per collection, a push and `setup --new`, by hand on each machine; a script for it broke on `wiki collections`' hint line.
- **What changed:** `wiki update` updates the plugin, or pulls the clone, then `exec`s the new version for the rest, so the old script never reads a file that changed under it. The new version pulls, upgrades and pushes each collection, runs `setup --new` at a terminal, and ends with what's left: restarting the Claude app and Antigravity, and the line to paste into open sessions. `upgrade` prints that line too. `wiki collections` writes its hint to stderr.

### Handbook version 26: each project's procedures and tools (2026-10-30)

- **Why:** an agent resuming another agent's work skipped checks, such as CI after a push, that came from the other agent's app rather than from the wiki. And nothing said which tools or MCP servers a project's work needs.
- **What changed:** a project wiki's `wiki/conventions.md` takes `## For agents` and `## Tools` (`- <name> (<cli|mcp|other>): what it's for`). `wiki start` prints both after the shared wikis' and marks each `cli` tool installed or not; nothing in the page is run. The handbook says to follow the project's procedures like the shared ones, to tell the user when a listed tool is missing instead of skipping the step, and to capture procedures and tools as they're learned. `wiki setup tools` offers allow rules for the listed command-line tools in Claude Code and Antigravity, one at a time.

### Gemini's tokens in the weekly report (2026-10-29)

- **Why:** the report counted Claude Code's tokens only, so a week's work in Antigravity was invisible in it.
- **What changed:** with Antigravity installed, `wiki report` adds a "Tokens (Gemini in Antigravity)" table from each transcript step's `input_tokens`, `cache_read_tokens` and `output_tokens`, with an estimate of wiki reads. A conversation counts toward the project its file paths and `git -C` folders point at most. It's a separate table, since the models count tokens differently and are priced differently.

### Work and personal collections (2026-10-29)

- **Why:** one collection on a personal remote held work, client and personal wikis together.
- **What changed:** `~/.config/llm-wiki/collections` lists collections besides `~/wikis`: a name, a folder, and rules that match a repository's folder or remote URL. Every command, `wiki start`, the Claude Code hook and the Antigravity plugin use the collection for the repository at hand; `--collection NAME` picks one by name; `wiki collections` lists them; `status` mentions notes waiting in the others; `WIKIS_DIR` still overrides. `wiki setup collections` adds one and creates it with its shared wiki. Moving existing wikis stays a person's step.
- **Open:** the session line for other agents and the Antigravity plugin's rule name the collection they were written from; each session's `wiki start` output names the right one.

### Handbook version 25: a shorter core (2026-10-29)

- **Why:** every session reads `AGENTS.md`, about 3,000 words, though finding peers and committing by hand matter only some of the time.
- **What changed:** about 2,300 words now. "Other wikis" keeps Ownership and Cite, don't copy; the rest moved to `rules/peers.md`. "Sync" is one paragraph around `wiki.sh sync`; the by-hand steps, conflicts and refused commits moved to a new `rules/sync.md`. "Capture" leads with `wiki.sh capture`. Terse page style, still in Next, would cut further once tested.

### Dependency map (2026-10-29)

- **Why:** an agent changing a shared package couldn't tell which of your repositories use it, or which repository owns a package it saw imported.
- **What changed:** `wiki deps` reads `go.mod`, `package.json` and `pyproject.toml` (three folders deep, skipping nested repositories, `node_modules` and `vendor`) in the repositories under `code_dirs`. It lists which repository owns each package, and which of your repositories use another's. A Go import counts toward the module that contains it. By default it covers only repositories a wiki in the collection covers, so another context's repositories don't leak in; `--all` takes them all, and `exclude` still applies. `--write` saves `data/dependencies.csv` in the shared wiki, with the columns kind, repo, ecosystem, package, owner and file.

### Backfill reads Gemini's Antigravity conversations (2026-10-29)

- **Why:** work done in Antigravity never reached the journal, so standups missed it.
- **What changed:** `wiki journal backfill` also digests `~/.gemini/antigravity/brain/*/…/transcript_full.jsonl`. A conversation doesn't record its workspace, so it goes under the project its file paths and `git -C` folders point at most. The digest marks how many sessions were Gemini's, with the user's prompts, files written or edited, a commit or `wiki.sh sync`, and the last reply. On 2026-10-29 it filed 8 conversations under the right wikis, including llm-wiki and global.

### Antigravity grants for llm-wiki (2026-10-29)

- **Why:** Gemini asked before every wiki file it read and every `wiki.sh` command it ran, because Antigravity grants one path or command at a time unless told otherwise.
- **What changed:** `wiki setup antigravity` offers grants in `userSettings.globalPermissionGrants.allow` (`~/.gemini/config/config.json`, where "Always allow" writes): read and write `~/wikis`, read the template, and `command(wiki.sh)` in both spellings. Folder grants cover everything under them. Setup checks the list is where expected before writing, keeps a backup, and adds nothing beyond llm-wiki's own needs. `wiki permissions` prints them; `setup --list` and `--new` report missing ones.

### Allow rules for the wiki commands (2026-10-29)

- **Why:** the handbook has agents commit and push the wikis with `wiki sync`, but Claude Code's auto mode stops a push and asks, and a session can't grant itself the permission. A v24 compile in one wiki ended with its changes uncommitted.
- **What changed:** `wiki setup` (or `setup permissions`) offers allow rules in `~/.claude/settings.json` for `start`, `capture`, `lock`, `log`, `index` and `sync`, in each spelling sessions use: the plugin's stable command or the clone's script, with `~` and in full, and plain `wiki`. It merges with what's there and keeps a backup. `wiki permissions` prints them for pasting. Adding them stays a person's step at a terminal on purpose: there is no non-interactive way for a session to add them.

### Handbook version 24: no summary page per source (2026-10-29)

- **Why:** each raw note got a page in `wiki/sources/` that only pointed at the pages it fed, 59 in the collection, one more write per note at every compile. Gemini's review proposed dropping them.
- **What changed:** `wiki log --source raw/<file>` records the note in its ingest entry. One check decides "compiled" everywhere (`pending`, `status`, `lint`, the report, the Claude Code hook): a log entry names it, a page lists it in `sources:`, or its old summary page exists, so existing wikis need no migration. `compile.md` drops the summary step. Risk noted in the CHANGELOG: a teammate still on v23 would compile v24 notes again.

### Handbook version 23: `wiki start`, and staleness in commits (2026-10-29)

- **Why:** Gemini skipped the session-start pull in every run, and session start took five or six calls without the plugin's hook. `lint.md` asked for pages far behind their repository's HEAD, which no command checked.
- **What changed:** `wiki start` finds the wiki, pulls with a timeout and the collection's own SSH command, and prints the indexes, `For agents` and what waits. A failed pull is a warning. The handbook's session start and the session line for other agents run it. With Antigravity installed, `wiki setup` adds an llm-wiki plugin whose SessionStart hook runs `wiki start` and hands its output to the conversation, as Gemini proposed after checking Antigravity's own docs. `capture --file` lets agents capture without a pipe or heredoc. `stale` and `lint` count commits behind for pages with a `commit` stamp, report commits a repository doesn't have, and bare hashes in wikis over several repositories, using clones under `code_dirs`.

### Handbook version 22: mechanical checks named, and Gemini's review (2026-10-29)

- **Why:** the handbook didn't name `wiki index` or `wiki lint` yet, and Gemini's review of the repo found checks the handbook asked for that no command did.
- **What changed:** `compile.md` and `lint.md` name `wiki index` and `wiki lint`. `lint` checks `sources:` files. `find` searches page text after index lines. `patterns`, `status` and the report flag an accepted pattern seen again (`AGAIN`). `status` and `pending` with no wiki say when a sandbox hides `raw/`.

### A model other than Claude: Gemini in Antigravity (2026-10-29)

- **Why:** the handbook says it needs no vendor features, and this had never been checked.
- **What changed:** Gemini 3.8 Flash in Antigravity ran a scripted test in a real repository: lookups, checking a page against code, captures, a correction, off the record, compile, sync, and recall in a fresh conversation. It followed the handbook apart from the session-start pull, and found three bugs: the session line didn't say where `wiki.sh` is (PR 19), `capture` reported success on a failed write (PR 20), and `pending` reported nothing waiting when it couldn't list `raw/` (PR 21). `docs/other-agents.md` now covers `~/.gemini/GEMINI.md`, sandboxes, and grading a run from its transcripts.

### `wiki index` and `wiki lint` (2026-10-28)

- **Why:** real use showed 45 shell edits to `index.md` and a throwaway lint script in two weeks.
- **What changed:** `wiki index` updates `index.md` in place from the pages' frontmatter: it refreshes lines, adds missing pages under their category, and drops lines for missing pages and duplicates, keeping the index's own order and headings. It lists every line it changes, so a better index line isn't silently replaced by a stale page summary. `--check` exits 1 when out of step. `wiki lint` reports the mechanical checks across one wiki or all of them, in under half a second for 13 wikis, and changes nothing. The handbook doesn't name them yet: see Next handbook release.

### Fitting real setups (2026-10-28, handbook version 21)

- **Why:** the same review of real use, plus a coworker's failed push test.
- **What changed:** the session hook gives sessions the stable `wiki` command; `which` suggests close matches and the `cover` fix; setup tries normal SSH before asking for a key, and explains push-test failures (https remote, refused key, blocked port, missing repository); reports and standups follow the user's reply style; `/llm-wiki:save` writes journal lines. Handbook v21: status pages carry `as_of` and are rewritten, newer versions of a document supersede older ones, and wikis keep only role and ownership about people. Docs: living with lint hooks, commit rules and commit-message skills; troubleshooting for a failed pull, a failed push test, a refused delete, and a repo under another name; one handbook version a day at most.

### Bookkeeping commands (2026-10-28, handbook version 20)

- **Why:** a review of two weeks of real use found the handbook's by-hand bookkeeping going wrong. In one collection: 61 `date -u` calls to name captures, 13 names rounded to `:00` and 9 with no time, 26 of 73 notes without `Captured:`, 58 shell calls on locks, and a rebase-pull that refused to run while another wiki had uncommitted notes. A digest delete was also refused by a safety check.
- **What changed:** `wiki capture`, `wiki lock`, `wiki log`, `wiki sync`, `wiki delegation log` and `wiki journal backfill --done`. The handbook names each one and keeps the steps by hand. Pulls are merges, never rebases or stashes.

### Harvest Claude Code memory, and two setup fixes (2026-10-28)

- **Why:** the work machine's audit found corrections and working rules saved to Claude Code's per-folder memory, 31 notes in 9 folders, where no other repository or teammate sees them. This machine had 60 in 6.
- **What changed:** `wiki harvest` copies memory notes into the wikis' `raw/`. `user` and `feedback` notes go to the shared wiki, project and reference notes to the wiki of the folder they were saved in (found from that folder's transcripts), and the rest to the shared wiki. A manifest per wiki says where each came from. Identical notes are skipped on rerun, and the memory itself is never touched. A tip points at it when memory has notes newer than the last harvest. Fixed: `wiki setup --new` never asked about tab completion, and `wiki upgrade` didn't commit collection changes such as the anchored ignore rules when no wiki was behind. Also found while testing: bash 3.2 treats an empty array as unbound under `set -u`.

### Shared knowledge reaches every project (2026-10-28, handbook version 19)

- **Why:** audits of two collections found general lessons stuck in project wikis (12 on one machine), sessions that opened the shared wiki only to write to it, no conventions pages anywhere, and zero `Feedback:` lines. The work machine's transcripts showed 11 corrections, 9 of them global, saved to Claude Code's own per-folder memory, which no other repository loads.
- **What changed:** sessions read the shared index and its conventions page's `For agents` section at start. Every capture asks whether another repository needs the item. The Ownership rule lists what belongs in the shared wiki, and "when unsure, keep it here" became a question about whether another repository's session would act differently. Knowledge goes in the wiki, not the agent's memory, and the hook repeats it. Setup and upgrade create the shared conventions page. Compile searches other wikis before starting a page. Lint reports duplicates, stale copies, broken cross-wiki citations, and lessons stuck in a project. Sessions that find a wiki indirectly run `wiki cover`. The weekly report counts corrections and flags a busy week with none.

### Tab completion (2026-10-28)

- **What changed:** `wiki completion zsh|bash` prints a small script that asks `wiki __complete` for candidates on every Tab: commands, wiki names, journal settings and their values, tip names, ranges, and folders for `seed`. `wiki setup` writes it to `~/.config/llm-wiki/` and adds one line to the shell profile, after asking. The candidates live in `wiki.sh`, so updates can't leave completion stale. Found while testing: bash 3.2 joins `"${COMP_WORDS[@]:1}"` into one word when `IFS` is a newline, so the script sets `IFS` only afterwards.

### Weekly report, and two fixes it found (2026-10-28)

- **Why:** to show whether the wikis earn their keep, and to gather what waits on a person into one weekly list instead of more nudges.
- **What changed:** `wiki report` builds the material from data already on disk: tokens per project from Claude Code's transcripts (each reply counted once, though a multi-part reply is recorded several times; scratch folders count toward their project), the estimated share spent reading wikis, what each wiki captured and compiled, hit rates, and a Needs you list. The session hook offers it once a week, and skips that week's tip. On this machine's real week: 33 sessions, 102.7M new input tokens, 5.4B cache reads, and wiki reads about 1.4% of new input.
- **Found while building it:** a session had upgraded every wiki to v18 but never committed, so 39 files sat uncommitted. `wiki upgrade` now commits its own changes, only the files the handbook owns, and leaves a wiki's other uncommitted work alone. And since v14 the collection's `.gitignore` said `delegation.md` unanchored, which also hid every wiki's `rules/delegation.md` in collections made after v14. The patterns are now anchored with `/`, and upgrades rewrite old ones.

### Bulk compile (2026-10-28, handbook version 18)

- **Why:** `wiki seed` can leave 20 documents waiting, and a session compiled them one at a time, rewriting the same topic page once per document, before it got to what the person asked.
- **What changed:** with five or more waiting, `rules/compile.md` has the session read them together, plan pages by topic, write each page once, then write the per-file summary pages. `wiki pending <wiki> --show` prints the waiting files in one call, up to about 150KB, and says when more wait. Seeded files get their own note: read the manifest first, and treat their code claims as unchecked. With more than ten waiting, a session does the person's request first and compiles at the next pause; the hook says so.

### Tips: features your wikis suggest (2026-10-28)

- **Why:** most features, like seed, standup, stats, team skills and backfill, are invisible unless someone reads the docs, so they risked going unused.
- **What changed:** `wiki tips` checks the person's own records for a reason to use each of eight features: a repository with docs but no wiki, skills only on this machine, journal entries but no standup, a young journal with older transcripts, two weeks of lookups, pages unchecked for 90 days, several wikis but no `find`, and delegation never used. The plugin's session hook passes on at most one per session, to mention at a stopping point, never right after compaction or during an upgrade. A shown tip rests 14 days, a muted one for good, and a used feature's tip stops. `wiki status` counts them. State is per machine in `~/.config/llm-wiki/tips`. It ran in 0.13 seconds on a 13-wiki collection.

### Team skills, and seed takes agent instructions (2026-10-28, handbook version 17)

- **Why:** a skill that came out of a repeated procedure landed in one person's `~/.claude/skills`, so the rest of the team never got it, and nothing kept it current. And `wiki seed` skipped `CLAUDE.md`, `AGENTS.md` and a repository's skills, often its best-kept guidance.
- **What changed:** skills live in the owning wiki as `skills/<name>/SKILL.md`, listed in its index. They keep the steps and cite wiki pages for facts. `wiki skills` lists them, and `wiki skills link` links them into `~/.claude/skills`, prefixing a wiki's name when two share a skill name, never touching a skill from elsewhere, and removing links to deleted skills. The plugin's hook links new ones every session, as do `upgrade` and `setup`. Checked: Claude Code loads a symlinked skill folder, even mid-session. `wiki seed` now also takes `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, Cursor, Windsurf and Copilot rules, and `.claude/skills/`.

### Sessions upgrade wikis on their own (2026-10-28)

- **Why:** plugin updates arrived on their own, but the wikis stayed on the old handbook until someone ran `wiki upgrade --all` and committed, on every machine, after every handbook change.
- **What changed:** when the session's wiki is behind the plugin's handbook, the session hook tells the session to pull, run `wiki upgrade --all`, commit and push one `wikis: handbook vN` commit, and say what changed, before reading the new handbook. The hook doesn't upgrade files itself: upgrading before the pull would leave local changes, and the pull would fail if a teammate had pushed the same upgrade. `upgrade` never moves a wiki backwards.

### Install in three steps (2026-10-28)

- **Why:** a dry run as a new coworker, on a fake machine with a stock macOS `PATH`, hit two snags in the seven-step guide: auto-update needed a hand edit to `~/.claude/settings.json`, and the `wiki` command was linked into `~/.local/bin`, which a stock Mac's shell never looks in.
- **What changed:** from the plugin, `wiki setup` now links `wiki` into a writable folder already on the `PATH` (or `~/.local/bin`, adding it to the shell profile after asking), turns on auto-update, offers to install gitleaks with Homebrew, and removes the old `CLAUDE.md` line. `wiki link` does the first part alone, and the session hook points Claude at it. The guide went from seven steps to three: install, start a session, run setup. `wiki status` warns when auto-update is off. The rerun found and fixed a setup crash where an empty `grep` stopped the script.

### Day-one value, stats, and capture after compaction (2026-10-28, handbook version 16)

- **Seed:** `wiki seed` copies a repository's tracked README, top-level guides, `docs/` and decision records into its wiki's `raw/`, most useful first, capped at 20 documents and 100KB each, with a manifest note saying where they came from and that their code claims are unchecked. Reruns copy only what's new. The plugin's hook offers it in a repository with no wiki. PR descriptions were left out: they need an API token.
- **Capture after compaction:** a `PreCompact` hook can block compaction, but its output doesn't reach the model, so blocking would stall the session without prompting a capture. Instead the `SessionStart` hook, which runs again with `"source": "compact"`, asks the session to capture what the summary holds.
- **Stats:** handbook step 6 under Query logs one line per question to `stats.csv`: hit or miss. `wiki stats` shows hit rates. Git ignores the file.
- **Standup:** at most 15 commits per repository, newest first, via the `max_commits` setting or `--max`. Fixed on the way: "through now" cut off at the current minute, dropping the last few seconds of commits, and commits in the same minute were ordered by hash.

### CI and smoke tests (2026-10-28)

- **Why:** every commit on `main` reaches plugin users with auto-update on, and nothing checked a commit before it went out.
- **What changed:** `tests/smoke.sh` holds 54 checks built from the session's manual tests: collection and wiki commands, the files a new wiki gets, upgrade and the ahead-of-template guard, a two-clone union merge, the secret scan with a fake token, the session hook's output and its 2,000-character budget, the `wiki` command, symlinks, plugin mode, journal and standup. It runs in a temp `HOME` in about four seconds. GitHub Actions runs it on Linux and on macOS with Apple's bash 3.2, plus shellcheck and `claude plugin validate`. Sabotaging a copy of the repo (no `.gitattributes`, an oversized hook, a disabled scan) made the matching tests fail.

### Claude Code plugin (2026-10-28)

- **Why:** a line in `CLAUDE.md` relies on the agent choosing to act on it, the skill had to be zipped and uploaded by hand, and coworkers needed several setup steps.
- **What changed:** the repo is a plugin and its own marketplace. A `SessionStart` hook finds the session's wiki the way `wiki.sh which` does and tells the session to read its handbook first, with the waiting-note count and a note when the handbook is behind. It first embedded the handbook and index, about 15KB; in the desktop app's Code tab only a 2KB preview reached the model, so it now points instead, in about 600 characters. Tested in a desktop Code-tab session on 2026-10-28: hook, `/llm-wiki:status`, and the `wiki` command all worked. It runs again after `/clear` and compaction. Commands: `status`, `save`, `compile`, `standup`. The plugin carries `wiki.sh` and the template, and `wiki.sh` skips the `CLAUDE.md` line when run from the plugin, since a line naming the plugin's versioned folder would break on update. The manifest has no `version`, so each pushed commit is an update. The plugin's folder changes with each update, so the hook keeps a `wiki` command in the plugin's data folder, which survives updates, pointed at the current version. Claude offers once to link it onto the `PATH`. The command reads Claude Code's `installed_plugins.json` on every run, so `claude plugin update` takes effect at once, without waiting for a session to repoint it. `wiki.sh` messages name whichever command was typed.

### Scan for secrets before pushing (2026-10-28, handbook version 15)

- **Why:** agents commit and push on their own. "Never store secrets" was a rule, not a check, and a team collection spreads a leak to everyone.
- **What changed:** `hooks/pre-commit` runs gitleaks over staged files. `init --git`, `new --git`, `upgrade` and `setup git` install it in the collection or a wiki's own repo, never a project's repo, and leave an existing hook or `core.hooksPath` alone. A refused commit tells the agent to redact, even in `raw/`, and never to use `--no-verify`. Without gitleaks the hook warns and lets the commit through, and `status` says so.

### Team-sharing fixes (2026-10-28, handbook version 14)

- **Why:** the collection was built for one person. Shared with coworkers, three things broke: two people compiling one wiki conflicted in git, coworkers overwrote each other's delegation mode, and a stale template clone gave no sign.
- **What changed:** each wiki's `.gitattributes` merges `index.md` and `log.md` with git's union driver, and lint reports a page indexed twice. `delegation.md` is git-ignored like its log. `status` flags a wiki ahead of the local template, and `upgrade` leaves it alone.

### Delegation to cheaper models (2026-10-27, handbook version 12)

- **Why:** expensive models spent tokens on volume work, such as test runs, sweeps and boilerplate, that a cheaper model does as well.
- **What changed:** `rules/delegation.md` says when to hand off (self-contained, big, checkable), how to brief, to check before relying on the result, and to log each handoff. `~/wikis/delegation.md` holds the mode, a who-does-what table and an Auto list. Setup asks for the mode, the session line points every session at the file, and `./wiki.sh delegation` sums the log.

### Repeat feedback becomes a fix (2026-10-27, handbook version 11)

- **Why:** the same review comments came back on agent-written code, and the same corrections had to be repeated, such as a shared Go library's metrics being added again in every service that imports it. Repeated procedures and mechanical work cost tokens every time.
- **What changed:** agents add `Feedback:` lines to their notes, filed in the wiki that owns the rule. Compile tallies them in each wiki's `patterns.md`. A ready pattern gets one proposal with evidence, and the fix depends on its kind: a conventions line, a note for code that uses a library, a skill, or a script. Agents check conventions before calling code done. `./wiki.sh patterns` gives the cross-wiki view, and lint reports patterns nobody has proposed.

### Journal backfill (2026-10-22, handbook version 10)

- **Why:** the journal starts empty on the day it's turned on. Past sessions held the work that left no commit.
- **What changed:** `./wiki.sh journal backfill` digests Claude Code transcripts into `journal/backfill.md`, one block per project per day: prompts, files changed, whether it committed, the last reply. Agents turn the digest into entries per the new Backfill section of `rules/journal.md`. `journal note` takes `--day` and `--at`. First real run: 42 project-days over two weeks became 17 entries. It led to two digest fixes: drop prompts written by tools (task notifications, side-session events), and file sessions from scratch folders under the project they ran in.

### Step-by-step setup (2026-10-22)

- **Why:** setup was five commands plus hand edits, and nothing told an existing machine when a template update added a setting.
- **What changed:** `./wiki.sh setup` walks through the collection, git (repo, remote, commit email, a per-repo SSH key, a test push), the Claude Code session line, handbook upgrades, and every journal setting, with validation and re-asking on bad input. It records answered questions per machine in `~/.config/llm-wiki/setup`, so `setup --new` asks only about what's new. `setup --list` shows every value and marks defaults. `setup journal.format` (or `setup format`) edits one setting. `upgrade` ends with a summary: which wikis moved from which version, the `CHANGELOG.md` entries since then, and next steps (commit command, stale session line, new settings, restart running sessions). `status` and `upgrade --all` say when there is something. Journal settings now come from one registry in `wiki.sh`, so a new setting is one line. Handbook unchanged, still version 9.

### Work journal and standups (2026-10-22, handbook version 9)

- **Why:** engineers need a daily summary for standup. Version 8 stopped capturing finished work, so the wikis alone can't supply one.
- **What changed:** `./wiki.sh standup` gathers the user's commits across repositories, journal entries, wiki notes and changes, work in progress, and open checks. The agent writes it up as a standup, a summary, or a detailed report, per `rules/journal.md`. Agents add one journal line per stopping point for work that leaves no commit. On by default, not committed by default. Thirteen settings in `~/wikis/journal/config`.

### Fixes from the first week of real use (2026-10-07, handbook version 8)

- **Why:** a review of the live collection after six days. Ten wikis, 109 captured notes, 53 pages. Four things had gone wrong.
- **Compile wasn't firing.** 50 of 109 notes were never compiled, and five wikis had an empty index. Long working sessions never reach a "pause". Compile now also runs at session start and whenever five notes are waiting.
- **Capture was too eager.** One build session wrote 27 notes in a day, each its own commit. "Finished work" is no longer a trigger. Notes cover decisions, direction, and what the code doesn't show, at stopping points. Captures are committed with the next compile.
- **Lint never ran.** 58 ingests, no lint. Agents don't count log entries unprompted. Every compile now ends by counting, and `./wiki.sh status` flags `lint due` and `compile due`.
- **Timestamps were invented.** Several notes carried round times. The capture step now says to read the clock and never estimate.

### Wikis that cover several repositories (2026-10-01, handbook version 7)

- **Why:** the first real use was a product spread over several repositories. One wiki per repository sent sessions to the wrong wiki and split the same fact across two.
- **What changed:** a wiki covers a project. That is one repository by default, or several listed in its `repos.md`. Sessions resolve a repository to its wiki by name, then by listing. `./wiki.sh cover` and `./wiki.sh which` manage and query the mapping. The staleness rule now covers facts checked against a cited source, not only against code. `./wiki.sh claude` replaces its own older line.

### Core handbook plus on-demand rules (2026-09-30, handbook version 6)

- **Why:** the handbook loaded in full in every session, about 3,800 tokens, and a third of it went unused.
- **What changed:** `template/AGENTS.md` now holds only what every session needs, about 2,500 tokens. Compile, conflicts, lint, and peer-wiki rules moved to `template/rules/` and are read on demand. The skill no longer embeds a copy of the handbook, which cut it from about 5,300 tokens to about 1,500 and removed a second copy to keep in step.

### Stale-knowledge guard (2026-09-30, handbook version 6)

- **Why:** code changes and pages don't. A stale page that answers confidently is worse than no page.
- **What changed:** pages carry `verified` and `commit` stamps. Before acting on a claim about code, the agent checks it against the code when the code is at hand, and files a correction if it no longer holds. Answers from pages verified more than 90 days ago say so. Lint flags pages past 180 days. `./wiki.sh stale` lists them.
