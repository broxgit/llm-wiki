# Maintaining the template

For whoever changes the rules, the script or the plugin. Work in a clone.

## What's here

```
README.md          The landing page.
LICENSE            MIT.
docs/              Setup guides, using it, teams, troubleshooting, this page.
AGENTS.md          Tells an agent this is the template and how to start a wiki from it.
CLAUDE.md          Imports AGENTS.md for Claude Code.
ROADMAP.md         Planned improvements, untested areas, and what was decided against.
CHANGELOG.md       What each handbook version changed. upgrade prints the parts you missed.
NEWS.md            What's new outside the handbook. update and news print what this machine hasn't seen.
wiki.sh            Setup and upkeep. Run it with no arguments for the commands.
go.mod cmd/ internal/  The compiled helper, llm-wiki, which wiki.sh uses for ported commands when it's built. See below.
template/          The scaffold, copied whole to start a wiki.
  AGENTS.md        The core handbook. Loaded in every session.
  rules/           The rest of the handbook. Read on demand.
  CLAUDE.md        Imports the handbook for Claude Code.
  .gitattributes   Lets git merge index.md and log.md from two people without a conflict.
  links.md         Shared wikis this one can fall back to.
  patterns.md      Recurring feedback, tallied toward a fix.
  repos.md         Repositories this wiki covers, when more than one.
  raw/ wiki/ data/ Sources, compiled pages, structured data.
skills/llm-wiki/   The Claude skill that finds, runs, and scaffolds wikis.
.claude-plugin/    The plugin manifest, and the marketplace that lists it.
mcp/server.py      A local MCP server for sessions with no file access. wiki mcp starts it; it runs wiki.sh.
commands/          The plugin's slash commands. wiki.sh also makes skills from them for Antigravity, Codex and Cursor.
tests/smoke.sh     Smoke tests for wiki.sh, the hook and the secret scan. CI runs them.
.github/workflows/ CI: shellcheck, plugin validation, and the smoke tests on Linux and macOS.
helper.lock        The released helper for this commit: its compiler, source hash and a SHA-256 per platform.
scripts/
  helper.sh        Builds the helper for release and writes helper.lock. CI checks it and publishes.
  migrate-to-plugin.sh  Moves a machine from the clone-and-line setup to the plugin.
  microsoft_copilot_setup.py  wiki setup microsoft-copilot: a read-only GitHub App and a Microsoft 365 Copilot agent. Pins Microsoft's toolkit version.
hooks/
  hooks.json       The plugin's hooks: session-start.sh at session start, pre-tool-use.sh before tool calls.
  session-start.sh Finds the session's wiki, points the session at it, keeps the wiki command current, and writes the session's reminders.
  pre-tool-use.sh  Hands a session the wiki reminders that apply to a tool call. reminders.py does the matching.
  pre-commit       The secret scan that wiki.sh installs in wiki repos.
```

## The compiled helper

`wiki.sh` is being ported to Go one command at a time. The Go lives in `cmd/llm-wiki` and `internal/`, uses the standard library only, and builds to `bin/llm-wiki`, which git ignores:

```
go build -o bin/llm-wiki ./cmd/llm-wiki
```

Nobody needs it. `wiki.sh` uses it when it's there and prints the protocol number `wiki.sh` expects, and otherwise runs the Bash and Python it always has. Plugin users don't have it yet. So for now every ported command exists twice, and the rules are:

- **Same output.** A port prints what the old code prints, byte for byte. `tests/smoke.sh` runs both and compares them when `go` is installed. Change both together.
- **New features wait.** A port changes nothing a user can see. Add to a command after its port has landed, not in it.
- **The protocol.** When a ported command's arguments or output change, raise `protocol` in `cmd/llm-wiki/main.go` and `GO_PROTOCOL` in `wiki.sh` together. A binary built from an older checkout is then passed over, not trusted.
- **Fail quietly.** The helper prints a command's output only once it has all of it, so a failure leaves nothing behind and `wiki.sh` falls back.
- **Checks.** `gofmt -l cmd internal`, `go vet ./cmd/... ./internal/...` and `go test ./cmd/... ./internal/...`. Name the packages: `tour/` holds Go too, as sample code for the tour.

`LLM_WIKI_NO_GO=1` makes `wiki.sh` ignore the helper, and `LLM_WIKI_GO=<path>` points it at another build.

### Releasing the helper

People who don't build the helper get it from a GitHub release. `wiki update` and `wiki helper fetch` download the one for their platform and keep it only if its SHA-256 is the one in `helper.lock`, which came with the code they already run. So a download is trusted no further than the code is, and no binary lives in git.

That depends on the build being reproducible: the same source, compiler and flags give the same bytes on any machine. `scripts/helper.sh` builds that way, with the compiler `helper.lock` names.

- **After changing anything under `cmd/` or `internal/`** (tests aside), run `scripts/helper.sh lock` and commit `helper.lock`. A smoke test fails when the lock is behind the source.
- **CI's `helper` job** builds every platform on Linux, fails unless the result is what the lock says, and publishes it as the release `helper-<source hash>`. It does this on the pull request, so the release exists before the merge.
- **To move to a newer compiler,** change the `toolchain` line in `helper.lock` and run `scripts/helper.sh lock`.
- **A pull request from a fork** can't publish. Push its branch to this repository to release it.

Session start fetches too, in the background, when the release a checkout names isn't on the machine: the Claude Code hook and `wiki start` both call `helper_auto`. It is quiet, tries once in six hours, and `wiki helper auto off` turns it off. `wiki setup` asks about it once.

`wiki helper` says which helper a checkout is using. `wiki.sh` looks for one built in the checkout, then the release its lock names, then any older release on the machine that speaks the same protocol. Downloads go under `~/.local/share/llm-wiki/helper/`, outside the plugin's folder, so a plugin update doesn't remove them. Old ones aren't cleaned up yet.

Ported so far: both token tables in `wiki report` (`report_tokens` and `report_tokens_gemini`), the body of `wiki standup` (`standup_activity`, in `internal/standup`), and the Python of `wiki journal backfill`. The Gemini table's Python stops at the first step it can't read, so its port doesn't copy each way of failing. It returns an error on anything it isn't sure of, and the Python decides. `cmd_standup` keeps the options, the dates and `--save`, runs under `LC_ALL=C` so order and matching don't depend on the locale, and passes its repositories and comma lists in final form. Anything that port isn't sure of, such as a pattern with a bracket or a file grep would call binary, is an error, and the Bash answers. The digest of `wiki journal backfill` (`journal-backfill`, in `internal/backfill`) is written to a temporary file and renamed into place, so a failed run leaves an old digest as it was. `journal_backfill` keeps the options, the dates and `--done`. Like the Gemini table, it returns an error on any record the Python might read differently or stop at, such as a line that is JSON but not an object, bad UTF-8 or a lone surrogate, and the Python answers. `internal/pyjson` holds the Python behaviours a port has to copy, such as the length of `json.dumps`, and `internal/pyos` the ones from `os.path`, `pathlib`, `fnmatch` and `datetime`, with the git lookups that name a folder's project.

`wiki which` is ported too (`which`, in `internal/routing`), for a name or, with none, for the repository the command runs in. Routing is more than that command: `wiki.sh` still chooses the collection, which every command does before it starts, and `which_wiki` stays for `start`, `sync`, `new` and `cover`. Both of the helper's answers leave by stdout, under a first line that says which one follows, `covered` or `uncovered`: the advice for a repository no wiki covers belongs on stderr with exit 1, and from a helper that would look like a failure. The port returns an error on a folder or file it can't read, on two wikis that list one repository, and on a name with a backslash or a line break, and the Bash answers. `which_miss` runs its `tr`, `grep` and `sort` under `LC_ALL=C`, so its close matches don't depend on the locale.

`wiki find` is ported too (`find`, in `internal/find`). `cmd_find` asks the helper, prints what it answers, and logs the search to `stats.csv` itself, so a search is logged once and the same way whichever answers: the helper's first line says how it went, `found <wiki>` with the first wiki that had a result, or `none`. The Bash it falls back to is `find_search`, which runs its `grep`, `awk`, `sed`, `cut` and `sort` under `LC_ALL=C`, with `local LC_ALL=C` for the order of the wikis. So everything is by byte in both: only the letters of ASCII match whatever their case, a page's line is cut at 120 bytes, and a file that isn't UTF-8 is read like any other. A cut at a byte can end inside a UTF-8 character, and the MCP server, which reads `find` through Python as text, fails on that. So both then drop the start of a character from the end of the line: `FIND_CUT` in `wiki.sh`, a `sed` that goes by byte, and `whole` in the Go. It is the same rule for text that isn't UTF-8, where a Latin-1 letter at the end of a line reads as such a start and goes too. `mcp/server.py` reads what `wiki.sh` prints with `errors="replace"`, so bytes that aren't UTF-8 come back as U+FFFD and never end a call. The log line is written outside that function, in the user's locale as before. The port returns an error, and the Bash answers, on a folder or file it can't read, a word with a backslash (awk's `-v` reads it as an escape) or a line break, a file with a NUL byte, a link under `wiki/` (GNU grep follows one named on its command line and BSD grep doesn't), and a wiki or page whose name has a backslash or a line break. The helper stops reading pages once it has five to show, which changes nothing: the Bash takes a line from no page after its fifth. The MCP server's `wiki_search` runs `wiki find`, so it gets the port with no change of its own.

## Change the rules

The handbook is `template/AGENTS.md` plus `template/rules/`. `AGENTS.md` loads in every session, so it holds only what every session needs. The rules files are read on demand: compile, conflicts, lint, peers, journal, patterns, delegation.

1. Edit them.
2. Bump the version at the top of `template/AGENTS.md`.
3. Add a section for that version to `CHANGELOG.md`, written for the person upgrading: what changed, and `- Do:` lines for anything they need to do. `wiki upgrade` prints it.
4. Run `wiki upgrade --all` to roll it out to your own wikis.

The tour in `tour/guide.md` runs on the real handbook, and holds some of its steps back for later chapters. When a handbook change moves a step the tour shows, such as when to compile or propose a pattern, check the guide still fits. `tests/smoke.sh` checks that the sandbox has what the guide promises, not what an agent does with it.

Batch handbook changes: at most one version a day. Each version makes every machine's next session upgrade and commit. Seven versions in one day left people seeing "behind template" over and over.

## Add a setting

A journal setting is one line in `JOURNAL_SETTINGS` in `wiki.sh`: key, type, basic or advanced, default, description. That line writes the config entry, validates `journal set`, and makes `wiki setup --new` ask about it on every machine. Anything else a person configures needs its own step in `cmd_setup`, recorded with `setup_mark`.

## Release

Merging to `main` is the release. The plugin has no version number, so every commit on `main` reaches plugin users with auto-update on, and a broken one breaks everyone's sessions at once. So:

1. Work on a branch.
2. Run the smoke tests: `tests/smoke.sh`. They take a few minutes, run in a temp folder with their own `HOME`, and never touch your wikis. Install gitleaks first, or the secret-scan tests are skipped.
3. Push the branch and open a pull request. CI runs shellcheck, `claude plugin validate`, and the smoke tests on Linux and on macOS with Apple's bash 3.2, in four parts at once on each.
4. Merge when CI is green. GitHub enforces this: `main` is protected, so it takes a pull request with all three CI checks passing, for admins too. In an emergency, untick "Do not allow bypassing the above settings" in the repository's Settings → Branches, and tick it again afterwards.

Add a smoke test when you fix a bug or add a command. Each one is a line or two: see the helpers at the top of `tests/smoke.sh`.

### The smoke test's parts

On macOS the whole suite took nine minutes in CI, so CI runs it in four parts, each its own job: `tests/smoke.sh --part <n>`. `tests/smoke.sh` with no option still runs everything, in order. `tests/smoke.sh --list` shows which part each section is in.

The table at the top of `tests/smoke.sh` holds, for each section, its part and the earlier sections it uses: the ones that made a wiki, a repository, a file or a setting it reads. A part runs its own sections and, without counting their checks, the sections they use from other parts, in the suite's order. So a part starts from the state its sections expect, without copying setup into them.

To add a section:

1. Write it as `if section "<name>"; then` ... `fi`, like the others. The function a check needs from another section belongs with the helpers at the top, not in the section that first used it.
2. Add a line to the table: its part, its name, and the earlier sections whose state it reads. A section missing from the table fails the run.
3. Put it in the part that is quickest now. `SMOKE_TIMES=1 tests/smoke.sh --part <n>` prints how long each section takes. CI prints the same, so the macOS job logs give the real times. The two slowest sections, the weekly report and the standup, each take most of a part.
4. Run `tests/smoke-parts.sh`. It runs the whole suite and every part, and fails unless each check of the whole run is made in exactly one part, and every check passes. A check that passes in its part only because state is missing, such as a `lacks` with nothing there to find, is the risk it can't see. When a section reads what another made, name that section in the table.

To add a part, add its number to the `smoke` matrix in `.github/workflows/ci.yml`. The lint job fails when the matrix and the table don't list the same parts. Branch protection requires `smoke (ubuntu-latest)` and `smoke (macos-latest)`, which pass when every part has, so the required checks stay the same.

A change people will notice belongs in the setup guides or [Using it](using.md), not only in the CHANGELOG, and gets an entry at the top of `NEWS.md`: one line for each thing a user would notice, as the top of that file says. A new entry reaches plugin users through `wiki status`, even if they never run `wiki update`. The one `claude plugin validate` warning, no `version`, is on purpose.

To try a change before pushing it, install the plugin from your clone: `claude plugin marketplace add <path to clone>`, then `claude plugin install llm-wiki@llm-wiki`. A marketplace added from a local path runs straight from your working tree, so a new session picks up your edits. Switch back with `claude plugin marketplace remove llm-wiki` and the install steps in [Set up with Claude Code](claude-code.md).

Every call to action that `wiki status` or `wiki report` prints ends with its fix: `Run:` a terminal command, `Ask an agent:` the exact request, or `Do:` a manual step. Add new flags to status's To do list with `todo_add`. A smoke test fails any item without a fix.

Keep the session hook's output short. Claude Code shows the model only a short preview of a long hook output and saves the rest to a file, which the model may never read. The hook points at the handbook rather than embedding it for this reason.

`ROADMAP.md` lists what's planned and what's still untested. When you finish an item, move it to Done and say what changed.
