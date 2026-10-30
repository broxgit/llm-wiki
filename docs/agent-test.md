# Test llm-wiki with your agent

A scripted test for any agent other than Claude Code: Codex, Cursor, Gemini, Copilot, and others. The agent works through each step and records what happened, then saves a report into the `llm-wiki` wiki. The maintainer reads the report, and the agent's own transcript, to find out what breaks.

**For the agent:** everything below the line is for you. Follow it in order. Don't skip a step because it seems obvious: the point is to find out what really happens, so a failure is a useful result. Record every step honestly, as PASS, PARTIAL or FAIL, with the exact commands you ran and what they printed.

---

## Rules for this test

- Work in the llm-wiki repository, the folder this file is in. Its wiki is `~/wikis/llm-wiki`.
- **Don't change the repository's code or docs.** This is a test of the tool, not a coding task.
- Wiki changes are allowed and expected: notes in `raw/`, compiled pages, `log.md`, `index.md`, and committing and pushing them with `wiki.sh sync`.
- When something fails, don't silently work around it. Note it, then try the reasonable fix, and note that too.
- Report only what the commands actually printed. If a result differs from what a step expects, say so: the maintainer checks the report against your transcript.
- Keep a running log as you go: for each step, the commands and their output, trimmed to what matters. You'll paste it into the report at the end.
- `wiki.sh` means the script your instructions name (for example `~/dev/sandbox/llm/llm-wiki/wiki.sh`). Use the full path if `wiki.sh` alone isn't found.

## Step 0: what you already know

Before running anything, write down:

- Which agent and model you are, and the date and time.
- Whether your instructions mention llm-wiki, `~/wikis` or `wiki.sh` at all, and if so, quote the line.
- Whether you run commands in a sandbox, and whether you need approval for commands outside this folder.
- Whether you can write to `~/wikis`. Check with `touch ~/wikis/.agent-test && rm ~/wikis/.agent-test`. If you can't, the write steps will fail. Carry on anyway, and record each failure: what an agent can do without write access is part of the result.

Expected: your instructions include the llm-wiki session line. If they don't, that's a FAIL for setup: record it, then continue, using `wiki.sh` from this repository.

## Step 1: session start

Do what your instructions say to do at session start.

Expected:
- You ran `wiki.sh start` (or its by-hand steps).
- It named `~/wikis/llm-wiki` and said whether the pull worked.
- You read `~/wikis/llm-wiki/AGENTS.md`, the handbook.
- You saw the shared wiki's `For agents` section, and what's waiting to be compiled.

Record: the exact command, the first five lines of its output, whether the pull worked, and whether anything was blocked.

## Step 2: answer a question from the wiki

Answer this as you normally would: **"How does the Antigravity plugin start each Gemini conversation, and why does its pull work when Gemini's own git commands don't?"**

Expected:
- You checked `~/wikis/llm-wiki/index.md` before searching the code.
- You answered from a wiki page and cited its path.
- You appended a line to `~/wikis/stats.csv`, as the handbook's Query section says.

Record: which files you read, in order; the page you cited; and the `stats.csv` line you wrote.

## Step 3: search page text

Run `wiki.sh find gitconfig`.

Expected: for each wiki, any index lines that mention the word (there may be none), then an "also in pages" list with the first matching line of each page that mentions it.

Record: the command and its output.

## Step 4: a page against the code

Pick one claim from a page in `~/wikis/llm-wiki/wiki/` that's about this repository's code. Check it against the code, the way the handbook's Stale knowledge section says to before acting on a claim.

Expected: a clear "still true" or "no longer true", with the file and line you checked. If it's no longer true, follow the handbook: capture a correction.

Record: the claim, the page, what you checked, and the verdict.

## Step 5: capture

Capture this as a note in the `llm-wiki` wiki, using `wiki.sh capture` the way the handbook says:

> Agent test: <your agent and model> ran docs/agent-test.md on <date>. Step 1's session start <worked or failed, in one line>.

Expected:
- One new file in `~/wikis/llm-wiki/raw/`, named from the clock.
- Its first line is `Captured: <date>`.
- You reported the path in one line.

Record: the exact command, its output, and the file's first two lines.

## Step 6: where would this go?

**Don't save anything in this step.** Say which wiki each of these belongs in, and why, using the handbook's Ownership rules:

1. "Run `tests/smoke.sh` before any commit in this repository."
2. "In every repository, check CI after a push and fix what fails."
3. "The payments service retries a failed charge three times."

Expected: 1 is this project's wiki, 2 is the shared wiki, and 3 is the wiki of whatever repository owns the payments service. The handbook's test is whether a session in another repository would act differently for knowing it.

Record: your three answers and reasons.

## Step 7: compile

Compile the notes waiting in `~/wikis/llm-wiki`, following `rules/compile.md`. Read it first.

Expected:
- You took the lock (`wiki.sh lock llm-wiki`), and released it at the end.
- Each note ended up in a page, or in a log entry with a `- source:` line.
- You ran `wiki.sh index llm-wiki`.
- You committed and pushed with `wiki.sh sync llm-wiki -m "llm-wiki: ..."`.
- `wiki.sh pending llm-wiki` says nothing is waiting.

Record: each command and its output, and the commit line from `git -C ~/wikis log --oneline -1`.

## Step 8: the project's procedures and tools

This repository's wiki has no `For agents` or `Tools` section of its own yet. From what you've seen of the repository (its `AGENTS.md`, `docs/maintaining.md`, `.github/workflows/`), write down the checks a change here should pass before it's done, and the command-line tools that work needs.

Then capture them as a note in `llm-wiki` for the next compile. Write them as the lines that would go in `wiki/conventions.md`, and don't edit that page yourself.

Expected: a note with a short `For agents` list (for example the smoke tests, shellcheck, plugin validation) and a `Tools` list in the form `- <name> (cli): what it's for`.

Record: the note's path and its contents.

## Step 9: report

Write the report below to `agent-test-report.md` in this repository's folder, which most sandboxes let you write. Then save it with:

```
wiki.sh capture llm-wiki <agent>-agent-test-report --file <that file>
```

Then commit it with `wiki.sh sync llm-wiki -m "llm-wiki: <agent> agent test report"`.

```markdown
# Agent test report: <agent>, <model>

Date: <date and time>. Sandbox: <yes or no, and what it blocked>.

## Results
| Step | Result | Notes |
|---|---|---|
| 0 Instructions loaded | PASS/PARTIAL/FAIL | |
| 1 Session start | | |
| 2 Lookup from the wiki | | |
| 3 find | | |
| 4 Page against the code | | |
| 5 Capture | | |
| 6 Where would this go | | |
| 7 Compile and sync | | |
| 8 Procedures and tools | | |

## What failed or got in the way
For each: the exact command, what it printed, what you expected, and what you did about it.

## Unclear or conflicting instructions
Quote the handbook or doc line, and say what you weren't sure of.

## What would have helped
Changes to `wiki.sh`, the handbook or the docs that would have made this smoother. Be specific.

## Running log
<your trimmed log from every step>
```

Expected: the report's path, and a pushed commit. Then delete `agent-test-report.md` from the repository's folder. Finish by telling the user the report's path in one line.

**If the report can't be saved,** because the wikis are read-only or `wiki.sh capture` fails, end your final message with the whole report instead. Your final message is then the report, so nothing is lost.
